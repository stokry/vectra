# frozen_string_literal: true

module Vectra
  module Instrumentation
    # New Relic instrumentation adapter
    #
    # Automatically reports Vectra metrics to New Relic APM.
    #
    # @example Enable New Relic instrumentation
    #   # config/initializers/vectra.rb
    #   require 'vectra/instrumentation/new_relic'
    #
    #   Vectra.configure do |config|
    #     config.instrumentation = true
    #   end
    #
    #   Vectra::Instrumentation::NewRelic.setup!
    #
    module NewRelic
      class << self
        # Setup New Relic instrumentation
        #
        # @return [void]
        def setup!
          return unless defined?(::NewRelic::Agent)

          Vectra::Instrumentation.on_operation do |event|
            record_metrics(event)
            record_transaction(event)
          end
        end

        private

        # Record custom metrics
        def record_metrics(event)
          prefix = "Custom/Vectra/#{event.provider}/#{event.operation}"

          ::NewRelic::Agent.record_metric("#{prefix}/duration", event.duration)
          ::NewRelic::Agent.record_metric("#{prefix}/calls", 1)

          if event.success?
            ::NewRelic::Agent.record_metric("#{prefix}/success", 1)

            # Record result count if available
            if event.metadata[:result_count]
              ::NewRelic::Agent.record_metric("#{prefix}/results", event.metadata[:result_count])
            end
          else
            ::NewRelic::Agent.record_metric("#{prefix}/error", 1)
          end
        end

        # Add to transaction trace
        def record_transaction(event)
          ::NewRelic::Agent.add_custom_attributes(
            vectra_operation: event.operation,
            vectra_provider: event.provider,
            vectra_index: event.index,
            vectra_duration: event.duration
          )

          return unless event.failure?

          ::NewRelic::Agent.notice_error(event.error)
        end
      end
    end
  end
end
