# frozen_string_literal: true

require "json"
require "logger"

module Vectra
  # Structured JSON logger for Vectra operations
  #
  # Provides consistent, machine-readable logging for all Vectra operations.
  # Output is JSON formatted for easy parsing by log aggregators.
  #
  # @example Basic usage
  #   Vectra.configure do |config|
  #     config.logger = Vectra::JsonLogger.new(STDOUT)
  #   end
  #
  # @example With file output
  #   Vectra.configure do |config|
  #     config.logger = Vectra::JsonLogger.new("log/vectra.log")
  #   end
  #
  # @example With custom metadata
  #   logger = Vectra::JsonLogger.new(STDOUT, app: "my-app", env: "production")
  #
  class JsonLogger
    SEVERITY_LABELS = {
      Logger::DEBUG => "debug",
      Logger::INFO => "info",
      Logger::WARN => "warn",
      Logger::ERROR => "error",
      Logger::FATAL => "fatal"
    }.freeze

    attr_reader :output, :default_metadata

    # Initialize JSON logger
    #
    # @param output [IO, String] Output destination (IO object or file path)
    # @param metadata [Hash] Default metadata to include in all log entries
    def initialize(output = $stdout, **metadata)
      @output = resolve_output(output)
      @default_metadata = metadata
      @mutex = Mutex.new
    end

    # Log debug message
    #
    # @param message [String] Log message
    # @param data [Hash] Additional data
    def debug(message, **data)
      log(Logger::DEBUG, message, **data)
    end

    # Log info message
    #
    # @param message [String] Log message
    # @param data [Hash] Additional data
    def info(message, **data)
      log(Logger::INFO, message, **data)
    end

    # Log warning message
    #
    # @param message [String] Log message
    # @param data [Hash] Additional data
    def warn(message, **data)
      log(Logger::WARN, message, **data)
    end

    # Log error message
    #
    # @param message [String] Log message
    # @param data [Hash] Additional data
    def error(message, **data)
      log(Logger::ERROR, message, **data)
    end

    # Log fatal message
    #
    # @param message [String] Log message
    # @param data [Hash] Additional data
    def fatal(message, **data)
      log(Logger::FATAL, message, **data)
    end

    # Log Vectra operation event
    #
    # @param event [Instrumentation::Event] Operation event
    def log_operation(event)
      data = {
        provider: event.provider.to_s,
        operation: event.operation.to_s,
        index: event.index,
        duration_ms: event.duration,
        success: event.success?
      }

      # Add metadata
      data[:vector_count] = event.metadata[:vector_count] if event.metadata[:vector_count]
      data[:result_count] = event.metadata[:result_count] if event.metadata[:result_count]

      # Add error info if present
      if event.error
        data[:error_class] = event.error.class.name
        data[:error_message] = event.error.message
      end

      level = event.success? ? Logger::INFO : Logger::ERROR
      log(level, "vectra.#{event.operation}", **data)
    end

    # Close the logger
    #
    # @return [void]
    def close
      @output.close if @output.respond_to?(:close) && @output != $stdout && @output != $stderr
    end

    private

    def log(severity, message, **data)
      entry = build_entry(severity, message, data)

      @mutex.synchronize do
        @output.puts(JSON.generate(entry))
        @output.flush if @output.respond_to?(:flush)
      end
    end

    def build_entry(severity, message, data)
      {
        timestamp: Time.now.utc.iso8601(3),
        level: SEVERITY_LABELS[severity],
        logger: "vectra",
        message: message
      }.merge(default_metadata).merge(data).compact
    end

    def resolve_output(output)
      case output
      when IO, StringIO
        output
      when String
        File.open(output, "a")
      else
        $stdout
      end
    end
  end

  # Instrumentation handler for JSON logging
  #
  # @example Enable JSON logging
  #   require 'vectra/logging'
  #
  #   Vectra::Logging.setup!(
  #     output: "log/vectra.json.log",
  #     app: "my-service"
  #   )
  #
  module Logging
    class << self
      attr_reader :logger

      # Setup JSON logging for Vectra
      #
      # @param output [IO, String] Log output
      # @param metadata [Hash] Default metadata
      # @return [JsonLogger]
      def setup!(output: $stdout, **metadata)
        @logger = JsonLogger.new(output, **metadata)

        # Register as instrumentation handler
        Vectra::Instrumentation.on_operation do |event|
          @logger.log_operation(event)
        end

        # Also set as Vectra's logger for retry/error logging
        Vectra.configuration.logger = @logger

        @logger
      end

      # Log a custom event
      #
      # @param level [Symbol] Log level (:debug, :info, :warn, :error, :fatal)
      # @param message [String] Log message
      # @param data [Hash] Additional data
      def log(level, message, **data)
        return unless @logger

        @logger.public_send(level, message, **data)
      end
    end
  end

  # Log formatter for standard Ruby Logger that outputs JSON
  #
  # @example With standard Logger
  #   logger = Logger.new(STDOUT)
  #   logger.formatter = Vectra::JsonFormatter.new(app: "my-app")
  #
  class JsonFormatter
    attr_reader :default_metadata

    def initialize(**metadata)
      @default_metadata = metadata
    end

    def call(severity, time, _progname, message)
      entry = {
        timestamp: time.utc.iso8601(3),
        level: severity.downcase,
        logger: "vectra",
        message: format_message(message)
      }.merge(default_metadata)

      # Parse structured data if message is a hash
      if message.is_a?(Hash)
        entry.merge!(message)
        entry[:message] = message[:message] || message[:msg] || "operation"
      end

      "#{JSON.generate(entry.compact)}\n"
    end

    private

    def format_message(message)
      case message
      when String
        message
      when Exception
        "#{message.class}: #{message.message}"
      when Hash
        message[:message] || message.to_s
      else
        message.to_s
      end
    end
  end
end
