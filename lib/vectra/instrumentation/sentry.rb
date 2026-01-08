# frozen_string_literal: true

module Vectra
  module Instrumentation
    # Sentry error tracking adapter
    #
    # Automatically reports Vectra errors to Sentry with context.
    #
    # @example Enable Sentry instrumentation
    #   # config/initializers/vectra.rb
    #   require 'vectra/instrumentation/sentry'
    #
    #   Vectra.configure do |config|
    #     config.instrumentation = true
    #   end
    #
    #   Vectra::Instrumentation::Sentry.setup!
    #
    module Sentry
      class << self
        # Setup Sentry instrumentation
        #
        # @param capture_all_errors [Boolean] Capture all errors, not just failures (default: false)
        # @param fingerprint_by_operation [Boolean] Group errors by operation (default: true)
        # @return [void]
        def setup!(capture_all_errors: false, fingerprint_by_operation: true)
          @capture_all_errors = capture_all_errors
          @fingerprint_by_operation = fingerprint_by_operation

          unless defined?(::Sentry)
            warn "Sentry gem not found. Install with: gem 'sentry-ruby'"
            return
          end

          Vectra::Instrumentation.on_operation do |event|
            record_breadcrumb(event)
            capture_error(event) if event.failure?
          end
        end

        private

        # Add breadcrumb for operation tracing
        def record_breadcrumb(event)
          ::Sentry.add_breadcrumb(
            ::Sentry::Breadcrumb.new(
              category: "vectra",
              message: "#{event.operation} on #{event.index}",
              level: event.success? ? "info" : "error",
              data: {
                provider: event.provider.to_s,
                operation: event.operation.to_s,
                index: event.index,
                duration_ms: event.duration,
                vector_count: event.metadata[:vector_count],
                result_count: event.metadata[:result_count]
              }.compact
            )
          )
        end

        # Capture error with context
        def capture_error(event)
          ::Sentry.with_scope do |scope|
            scope.set_tags(
              vectra_provider: event.provider.to_s,
              vectra_operation: event.operation.to_s,
              vectra_index: event.index
            )

            scope.set_context("vectra", build_context(event))

            # Custom fingerprint to group similar errors
            if @fingerprint_by_operation
              scope.set_fingerprint(build_fingerprint(event))
            end

            # Set error level based on error type
            scope.set_level(error_level(event.error))

            ::Sentry.capture_exception(event.error)
          end
        end

        # Build context hash for Sentry
        def build_context(event)
          {
            provider: event.provider.to_s,
            operation: event.operation.to_s,
            index: event.index,
            duration_ms: event.duration,
            metadata: event.metadata
          }
        end

        # Build fingerprint array for error grouping
        def build_fingerprint(event)
          ["vectra", event.provider.to_s, event.operation.to_s, event.error.class.name]
        end

        # Determine error level based on error type
        def error_level(error)
          case error
          when Vectra::RateLimitError
            :warning
          when Vectra::ValidationError
            :info
          when Vectra::ServerError, Vectra::ConnectionError, Vectra::TimeoutError
            :error
          when Vectra::AuthenticationError
            :fatal
          end
        end
      end
    end
  end
end
