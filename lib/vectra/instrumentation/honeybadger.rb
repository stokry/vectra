# frozen_string_literal: true

module Vectra
  module Instrumentation
    # Honeybadger error tracking adapter
    #
    # Automatically reports Vectra errors to Honeybadger with context.
    #
    # @example Enable Honeybadger instrumentation
    #   # config/initializers/vectra.rb
    #   require 'vectra/instrumentation/honeybadger'
    #
    #   Vectra.configure do |config|
    #     config.instrumentation = true
    #   end
    #
    #   Vectra::Instrumentation::Honeybadger.setup!
    #
    module Honeybadger
      class << self
        # Setup Honeybadger instrumentation
        #
        # @param notify_on_rate_limit [Boolean] Report rate limit errors (default: false)
        # @param notify_on_validation [Boolean] Report validation errors (default: false)
        # @return [void]
        def setup!(notify_on_rate_limit: false, notify_on_validation: false)
          @notify_on_rate_limit = notify_on_rate_limit
          @notify_on_validation = notify_on_validation

          unless defined?(::Honeybadger)
            warn "Honeybadger gem not found. Install with: gem 'honeybadger'"
            return
          end

          Vectra::Instrumentation.on_operation do |event|
            add_breadcrumb(event)
            notify_error(event) if should_notify?(event)
          end
        end

        private

        # Add breadcrumb for operation tracing
        def add_breadcrumb(event)
          ::Honeybadger.add_breadcrumb(
            "Vectra #{event.operation}",
            category: "vectra",
            metadata: {
              provider: event.provider.to_s,
              operation: event.operation.to_s,
              index: event.index,
              duration_ms: event.duration,
              success: event.success?,
              vector_count: event.metadata[:vector_count],
              result_count: event.metadata[:result_count]
            }.compact
          )
        end

        # Check if error should be reported
        def should_notify?(event)
          return false if event.success?

          case event.error
          when Vectra::RateLimitError
            @notify_on_rate_limit
          when Vectra::ValidationError
            @notify_on_validation
          else
            true
          end
        end

        # Notify Honeybadger of error
        def notify_error(event)
          ::Honeybadger.notify(
            event.error,
            context: {
              vectra: {
                provider: event.provider.to_s,
                operation: event.operation.to_s,
                index: event.index,
                duration_ms: event.duration,
                metadata: event.metadata
              }
            },
            tags: build_tags(event),
            fingerprint: build_fingerprint(event)
          )
        end

        # Build tags for error grouping
        def build_tags(event)
          [
            "vectra",
            "provider:#{event.provider}",
            "operation:#{event.operation}",
            error_severity(event.error)
          ]
        end

        # Build fingerprint for error grouping
        def build_fingerprint(event)
          [
            "vectra",
            event.provider.to_s,
            event.operation.to_s,
            event.error.class.name
          ].join("-")
        end

        # Determine severity tag
        def error_severity(error)
          case error
          when Vectra::AuthenticationError
            "severity:critical"
          when Vectra::ServerError
            "severity:high"
          when Vectra::RateLimitError
            "severity:medium"
          else
            "severity:low"
          end
        end
      end
    end
  end
end
