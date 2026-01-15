# frozen_string_literal: true

module Vectra
  module Middleware
    # Instrumentation middleware for metrics and monitoring
    #
    # Emits instrumentation events for all operations, compatible with
    # Vectra's existing instrumentation system.
    #
    # @example Enable instrumentation middleware
    #   Vectra::Client.use Vectra::Middleware::Instrumentation
    #
    # @example With custom event handler
    #   Vectra.on_operation do |event|
    #     puts "Operation: #{event[:operation]}, Duration: #{event[:duration_ms]}ms"
    #   end
    #
    #   Vectra::Client.use Vectra::Middleware::Instrumentation
    #
    class Instrumentation < Base
      def call(request, app)
        start_time = Time.now

        response = app.call(request)

        duration_ms = ((Time.now - start_time) * 1000).round(2)

        # Emit instrumentation event
        Vectra::Instrumentation.instrument(
          operation: request.operation,
          provider: request.provider,
          index: request.index,
          namespace: request.namespace,
          duration_ms: duration_ms,
          success: response.success?,
          error: response.error&.class&.name,
          metadata: response.metadata
        )

        response
      end
    end
  end
end
