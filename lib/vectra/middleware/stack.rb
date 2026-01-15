# frozen_string_literal: true

module Vectra
  module Middleware
    # Middleware stack executor
    #
    # Builds and executes a chain of middleware around provider calls.
    # Similar to Rack middleware, each middleware wraps the next one
    # in the chain until reaching the actual provider.
    #
    # @example Basic usage
    #   provider = Vectra::Providers::Memory.new
    #   middlewares = [LoggingMiddleware.new, RetryMiddleware.new]
    #   stack = Stack.new(provider, middlewares)
    #
    #   result = stack.call(:upsert, index: 'test', vectors: [...])
    #
    class Stack
      # @param provider [Vectra::Providers::Base] The actual provider
      # @param middlewares [Array<Base>] Array of middleware instances
      def initialize(provider, middlewares = [])
        @provider = provider
        @middlewares = middlewares
      end

      # Execute the middleware stack for an operation
      #
      # @param operation [Symbol] The operation to perform (:upsert, :query, etc.)
      # @param params [Hash] The operation parameters
      # @return [Object] The result from the provider
      # @raise [Exception] Any error from middleware or provider
      def call(operation, **params)
        request = Request.new(operation: operation, **params)

        # Build middleware chain
        app = build_chain(request)

        # Execute chain
        response = app.call(request)

        # Raise if error occurred
        raise response.error if response.error

        response.result
      end

      private

      # Build the middleware chain
      #
      # @param request [Request] The request object (unused here, but available)
      # @return [Proc] The complete middleware chain
      def build_chain(_request)
        # Final app: actual provider call
        final_app = lambda do |req|
          begin
            # Remove middleware-specific params before calling provider
            provider_params = req.to_h.reject { |k, _| k == :provider }
            result = @provider.public_send(req.operation, **provider_params)
            Response.new(result: result)
          rescue StandardError => e
            Response.new(error: e)
          end
        end

        # Wrap with middlewares in reverse order
        # (last middleware in array is first to execute)
        @middlewares.reverse.inject(final_app) do |next_app, middleware|
          lambda do |req|
            middleware.call(req, next_app)
          end
        end
      end
    end
  end
end
