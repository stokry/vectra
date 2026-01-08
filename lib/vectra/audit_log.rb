# frozen_string_literal: true

module Vectra
  # Audit logging for security and compliance
  #
  # Provides structured audit logs for security-sensitive operations,
  # including authentication, authorization, and data access.
  #
  # @example Basic usage
  #   audit = Vectra::AuditLog.new(output: "log/audit.json.log")
  #
  #   audit.log_access(
  #     user_id: "user123",
  #     operation: "query",
  #     index: "sensitive-data",
  #     result_count: 10
  #   )
  #
  class AuditLog
    # Audit event types
    EVENT_TYPES = %i[
      access
      authentication
      authorization
      configuration_change
      credential_rotation
      data_modification
      error
    ].freeze

    attr_reader :logger, :enabled

    # Initialize audit logger
    #
    # @param output [IO, String] Log output destination
    # @param enabled [Boolean] Enable/disable audit logging
    # @param metadata [Hash] Default metadata for all events
    def initialize(output: $stdout, enabled: true, **metadata)
      @enabled = enabled
      @logger = enabled ? Vectra::JsonLogger.new(output, **metadata) : nil
    end

    # Log access event
    #
    # @param user_id [String, nil] User identifier
    # @param operation [Symbol, String] Operation type
    # @param index [String] Index accessed
    # @param result_count [Integer, nil] Number of results
    # @param metadata [Hash] Additional metadata
    def log_access(operation:, index: nil, result_count: nil, user_id: nil, **metadata)
      log_event(
        type: :access,
        user_id: user_id,
        operation: operation.to_s,
        resource: index,
        result_count: result_count,
        **metadata
      )
    end

    # Log authentication event
    #
    # @param user_id [String, nil] User identifier
    # @param success [Boolean] Authentication success
    # @param provider [String, nil] Provider name
    # @param metadata [Hash] Additional metadata
    def log_authentication(success:, provider: nil, user_id: nil, **metadata)
      log_event(
        type: :authentication,
        user_id: user_id,
        success: success,
        provider: provider,
        **metadata
      )
    end

    # Log authorization event
    #
    # @param user_id [String] User identifier
    # @param resource [String] Resource accessed
    # @param allowed [Boolean] Authorization result
    # @param reason [String, nil] Reason if denied
    def log_authorization(user_id:, resource:, allowed:, reason: nil)
      log_event(
        type: :authorization,
        user_id: user_id,
        resource: resource,
        allowed: allowed,
        reason: reason
      )
    end

    # Log configuration change
    #
    # @param user_id [String] User who made change
    # @param change_type [String] Type of change
    # @param old_value [Object, nil] Previous value
    # @param new_value [Object, nil] New value
    def log_configuration_change(user_id:, change_type:, old_value: nil, new_value: nil)
      log_event(
        type: :configuration_change,
        user_id: user_id,
        change_type: change_type,
        old_value: sanitize_value(old_value),
        new_value: sanitize_value(new_value)
      )
    end

    # Log credential rotation
    #
    # @param provider [String] Provider name
    # @param success [Boolean] Rotation success
    # @param rotated_by [String, nil] User who initiated rotation
    def log_credential_rotation(provider:, success:, rotated_by: nil)
      log_event(
        type: :credential_rotation,
        provider: provider,
        success: success,
        rotated_by: rotated_by
      )
    end

    # Log data modification
    #
    # @param user_id [String, nil] User identifier
    # @param operation [String] Operation (upsert, delete, update)
    # @param index [String] Index modified
    # @param record_count [Integer] Number of records affected
    def log_data_modification(operation:, index:, record_count:, user_id: nil)
      log_event(
        type: :data_modification,
        user_id: user_id,
        operation: operation.to_s,
        resource: index,
        record_count: record_count
      )
    end

    # Log error event
    #
    # @param error [Exception] Error that occurred
    # @param context [Hash] Error context
    def log_error(error:, **context)
      log_event(
        type: :error,
        error_class: error.class.name,
        error_message: error.message,
        severity: error_severity(error),
        **context
      )
    end

    private

    def log_event(type:, **data)
      return unless @enabled && @logger

      @logger.info(
        "audit.#{type}",
        event_type: type.to_s,
        timestamp: Time.now.utc.iso8601(3),
        **data
      )
    end

    def sanitize_value(value)
      case value
      when String
        # Mask sensitive values: keep a short prefix and suffix, hide the middle
        return value unless value.length >= 10

        prefix = value[0, 9]
        suffix = value[-4, 4]
        "#{prefix}...#{suffix}"
      when Hash
        value.transform_values { |v| sanitize_value(v) }
      else
        value
      end
    end

    def error_severity(error)
      case error
      when Vectra::AuthenticationError
        "critical"
      when Vectra::ServerError, Vectra::ConnectionError
        "high"
      when Vectra::RateLimitError
        "medium"
      else
        "low"
      end
    end
  end

  # Global audit log instance
  module AuditLogging
    class << self
      attr_accessor :audit_log

      # Setup global audit logging
      #
      # @param output [IO, String] Log output
      # @param enabled [Boolean] Enable audit logging
      # @param metadata [Hash] Default metadata
      # @return [AuditLog]
      def setup!(output: "log/audit.json.log", enabled: true, **metadata)
        @audit_log = AuditLog.new(output: output, enabled: enabled, **metadata)
      end

      # Log audit event
      #
      # @param type [Symbol] Event type
      # @param data [Hash] Event data
      def log(type, **data)
        return unless @audit_log

        @audit_log.public_send("log_#{type}", **data)
      rescue NoMethodError
        # Event type not supported
        @audit_log.instance_variable_get(:@logger)&.info("audit.#{type}", **data)
      end
    end
  end
end
