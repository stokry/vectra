# frozen_string_literal: true

require "securerandom"

module Vectra
  module Middleware
    # Request ID tracking middleware
    #
    # Generates a unique request ID for each operation and propagates it
    # through logs and instrumentation. Standard practice in production APIs
    # for request tracing and debugging.
    #
    # @example Enable request ID tracking
    #   Vectra::Client.use Vectra::Middleware::RequestId
    #
    # @example With custom ID generator
    #   Vectra::Client.use Vectra::Middleware::RequestId, generator: ->(prefix) { "#{prefix}-#{Time.now.to_i}" }
    #
    # @example Access request ID in logs
    #   # Request ID is automatically added to request.metadata
    #   # and propagated to instrumentation events
    #
    class RequestId < Base
      DEFAULT_ID_LENGTH = 16
      DEFAULT_PREFIX = "vectra"

      # @param generator [Proc, nil] Custom ID generator proc (default: SecureRandom.hex)
      # @param prefix [String] Prefix for request IDs (default: "vectra")
      # @param logger [Logger, nil] Custom logger for logging request IDs
      # @param on_assign [Proc, nil] Callback invoked when ID is assigned
      def initialize(generator: nil, prefix: DEFAULT_PREFIX, logger: nil, on_assign: nil)
        super()
        @prefix = prefix
        @logger = logger || Vectra.configuration.logger
        @on_assign = on_assign
        @generator = generator || ->(p) { "#{p}_#{SecureRandom.hex(DEFAULT_ID_LENGTH)}" }
      end

      def before(request)
        # Generate unique request ID
        request_id = @generator.call(@prefix)

        # Store in request metadata (not in params to avoid provider issues)
        request.metadata[:request_id] = request_id

        # Invoke callback if provided
        @on_assign&.call(request_id)

        # Log request ID
        log_request_id(request, request_id) if @logger
      end

      def after(request, response)
        # Propagate request ID to response metadata
        if request.metadata[:request_id]
          response.metadata[:request_id] = request.metadata[:request_id]
        end

        # Log completion
        log_completion(request, response) if @logger
      end

      def on_error(request, error)
        # Log error with request ID
        log_error(request, error) if @logger
      end

      private

      def log_request_id(request, request_id)
        @logger.info(
          "[Vectra] request_id=#{request_id} " \
          "operation=#{request.operation} " \
          "index=#{request.index}"
        )
      end

      def log_completion(request, response)
        status = response.success? ? "success" : "failure"
        @logger.info(
          "[Vectra] request_id=#{request.metadata[:request_id]} " \
          "status=#{status}"
        )
      end

      def log_error(request, error)
        @logger.error(
          "[Vectra] request_id=#{request.metadata[:request_id]} " \
          "error=#{error.class} " \
          "message=#{error.message}"
        )
      end
    end
  end
end
