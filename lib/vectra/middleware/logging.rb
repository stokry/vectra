# frozen_string_literal: true

module Vectra
  module Middleware
    # Logging middleware for tracking operations
    #
    # Logs before and after each operation, including timing information.
    #
    # @example With default logger
    #   Vectra::Client.use Vectra::Middleware::Logging
    #
    # @example With custom logger
    #   logger = Logger.new($stdout)
    #   Vectra::Client.use Vectra::Middleware::Logging, logger: logger
    #
    # @example Per-client logging
    #   client = Vectra::Client.new(
    #     provider: :qdrant,
    #     middleware: [Vectra::Middleware::Logging]
    #   )
    #
    class Logging < Base
      def initialize(logger: nil)
        super()
        @logger = logger || Vectra.configuration.logger
      end

      def before(request)
        return unless @logger

        @start_time = Time.now
        @logger.info(
          "[Vectra] #{request.operation.upcase} " \
          "index=#{request.index} " \
          "namespace=#{request.namespace || 'default'}"
        )
      end

      def after(request, response)
        return unless @logger
        return unless @start_time

        duration_ms = ((Time.now - @start_time) * 1000).round(2)
        response.metadata[:duration_ms] = duration_ms

        if response.success?
          @logger.info("[Vectra] ✅ #{request.operation} completed in #{duration_ms}ms")
        else
          @logger.error("[Vectra] ❌ #{request.operation} failed: #{response.error.message}")
        end
      end

      def on_error(request, error)
        return unless @logger

        @logger.error(
          "[Vectra] 💥 #{request.operation} exception: #{error.class} - #{error.message}"
        )
      end
    end
  end
end
