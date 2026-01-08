# frozen_string_literal: true

module Vectra
  module Instrumentation
    # Datadog instrumentation adapter
    #
    # Automatically reports Vectra metrics to Datadog using DogStatsD.
    #
    # @example Enable Datadog instrumentation
    #   # config/initializers/vectra.rb
    #   require 'vectra/instrumentation/datadog'
    #
    #   Vectra.configure do |config|
    #     config.instrumentation = true
    #   end
    #
    #   Vectra::Instrumentation::Datadog.setup!(
    #     host: ENV['DD_AGENT_HOST'] || 'localhost',
    #     port: ENV['DD_DOGSTATSD_PORT']&.to_i || 8125
    #   )
    #
    module Datadog
      class << self
        attr_reader :statsd

        # Setup Datadog instrumentation
        #
        # @param host [String] DogStatsD host
        # @param port [Integer] DogStatsD port
        # @param namespace [String] Metric namespace
        # @return [void]
        def setup!(host: 'localhost', port: 8125, namespace: 'vectra')
          require 'datadog/statsd'

          @statsd = ::Datadog::Statsd.new(host, port, namespace: namespace)

          Vectra::Instrumentation.on_operation do |event|
            record_metrics(event)
          end
        rescue LoadError
          warn "Datadog StatsD gem not found. Install with: gem 'dogstatsd-ruby'"
        end

        private

        # Record metrics to Datadog
        def record_metrics(event)
          return unless statsd

          tags = [
            "provider:#{event.provider}",
            "operation:#{event.operation}",
            "index:#{event.index}",
            "status:#{event.success? ? 'success' : 'error'}"
          ]

          # Record timing
          statsd.timing('operation.duration', event.duration, tags: tags)

          # Record count
          statsd.increment('operation.count', tags: tags)

          # Record result count if available
          if event.metadata[:result_count]
            statsd.gauge('operation.results', event.metadata[:result_count], tags: tags)
          end

          # Record vector count if available
          if event.metadata[:vector_count]
            statsd.gauge('operation.vectors', event.metadata[:vector_count], tags: tags)
          end

          # Record errors
          if event.failure?
            error_tags = tags + ["error_type:#{event.error.class.name}"]
            statsd.increment('operation.error', tags: error_tags)
          end
        end
      end
    end
  end
end
