# frozen_string_literal: true

module Vectra
  module Middleware
    # PII Redaction middleware for protecting sensitive data
    #
    # Automatically redacts Personally Identifiable Information (PII) from
    # metadata before upserting to vector databases.
    #
    # @example With default patterns (email, phone, SSN)
    #   Vectra::Client.use Vectra::Middleware::PIIRedaction
    #
    # @example With custom patterns
    #   custom_patterns = {
    #     credit_card: /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/,
    #     api_key: /sk-[a-zA-Z0-9]{32}/
    #   }
    #   Vectra::Client.use Vectra::Middleware::PIIRedaction, patterns: custom_patterns
    #
    class PIIRedaction < Base
      # Default PII patterns
      DEFAULT_PATTERNS = {
        email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
        phone: /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,
        ssn: /\b\d{3}-\d{2}-\d{4}\b/,
        credit_card: /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/
      }.freeze

      def initialize(patterns: DEFAULT_PATTERNS)
        super()
        @patterns = patterns
      end

      def before(request)
        return unless request.operation == :upsert
        return unless request.params[:vectors]

        # Redact PII from metadata in all vectors
        request.params[:vectors].each do |vector|
          next unless vector[:metadata]

          vector[:metadata] = redact_metadata(vector[:metadata])
        end
      end

      private

      # Redact PII from metadata hash
      #
      # @param metadata [Hash] Metadata to redact
      # @return [Hash] Redacted metadata
      def redact_metadata(metadata)
        metadata.transform_values do |value|
          next value unless value.is_a?(String)

          redacted = value.dup
          @patterns.each do |type, pattern|
            redacted.gsub!(pattern, "[REDACTED_#{type.upcase}]")
          end
          redacted
        end
      end
    end
  end
end
