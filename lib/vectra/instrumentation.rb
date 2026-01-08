# frozen_string_literal: true

module Vectra
  # Instrumentation and observability hooks
  #
  # Provides hooks for monitoring tools like New Relic, Datadog, and custom loggers.
  # Records metrics for all vector operations including duration, result counts, and errors.
  #
  # @example Enable instrumentation
  #   Vectra.configure do |config|
  #     config.instrumentation = true
  #   end
  #
  # @example Custom instrumentation handler
  #   Vectra.on_operation do |event|
  #     puts "#{event.operation} took #{event.duration}ms"
  #   end
  #
  module Instrumentation
    # Event object passed to instrumentation handlers
    #
    # @attr_reader [Symbol] operation The operation type (:upsert, :query, :fetch, etc.)
    # @attr_reader [Symbol] provider The provider name (:pinecone, :pgvector, etc.)
    # @attr_reader [String] index The index/table name
    # @attr_reader [Float] duration Duration in milliseconds
    # @attr_reader [Hash] metadata Additional operation metadata
    # @attr_reader [Exception, nil] error Exception if operation failed
    class Event
      attr_reader :operation, :provider, :index, :duration, :metadata, :error

      def initialize(operation:, provider:, index:, duration:, metadata: {}, error: nil)
        @operation = operation
        @provider = provider
        @index = index
        @duration = duration
        @metadata = metadata
        @error = error
      end

      # Check if operation succeeded
      #
      # @return [Boolean]
      def success?
        error.nil?
      end

      # Check if operation failed
      #
      # @return [Boolean]
      def failure?
        !success?
      end
    end

    class << self
      # Register an instrumentation handler
      #
      # The block will be called for every vector operation with an Event object.
      #
      # @yield [event] The instrumentation event
      # @yieldparam event [Event] Event details
      #
      # @example
      #   Vectra::Instrumentation.on_operation do |event|
      #     StatsD.timing("vectra.#{event.operation}", event.duration)
      #     StatsD.increment("vectra.#{event.operation}.#{event.success? ? 'success' : 'error'}")
      #   end
      #
      def on_operation(&block)
        handlers << block
      end

      # Instrument a vector operation
      #
      # @param operation [Symbol] Operation name
      # @param provider [Symbol] Provider name
      # @param index [String] Index name
      # @param metadata [Hash] Additional metadata
      # @yield The operation to instrument
      # @return [Object] The result of the block
      #
      # @api private
      def instrument(operation:, provider:, index:, metadata: {})
        return yield unless enabled?

        start_time = Time.now
        error = nil
        result = nil

        begin
          result = yield
        rescue => e
          error = e
          raise
        ensure
          duration = ((Time.now - start_time) * 1000).round(2)

          event = Event.new(
            operation: operation,
            provider: provider,
            index: index,
            duration: duration,
            metadata: metadata,
            error: error
          )

          notify_handlers(event)
        end

        result
      end

      # Check if instrumentation is enabled
      #
      # @return [Boolean]
      def enabled?
        Vectra.configuration.instrumentation
      end

      # Clear all handlers (useful for testing)
      #
      # @api private
      def clear_handlers!
        @handlers = []
      end

      private

      def handlers
        @handlers ||= []
      end

      def notify_handlers(event)
        handlers.each do |handler|
          handler.call(event)
        rescue => e
          # Don't let instrumentation errors crash the app
          warn "Vectra instrumentation handler error: #{e.message}"
        end
      end
    end
  end
end
