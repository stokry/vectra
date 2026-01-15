# frozen_string_literal: true

module Vectra
  module Middleware
    # Base class for all middleware
    #
    # Middleware can hook into three lifecycle events:
    # - before(request): Called before the next middleware/provider
    # - after(request, response): Called after successful execution
    # - on_error(request, error): Called when an error occurs
    #
    # @example Simple logging middleware
    #   class LoggingMiddleware < Vectra::Middleware::Base
    #     def before(request)
    #       puts "Starting #{request.operation}"
    #     end
    #
    #     def after(request, response)
    #       puts "Completed #{request.operation}"
    #     end
    #   end
    #
    # @example Error handling middleware
    #   class ErrorHandlerMiddleware < Vectra::Middleware::Base
    #     def on_error(request, error)
    #       ErrorTracker.notify(error, context: { operation: request.operation })
    #     end
    #   end
    #
    class Base
      # Execute the middleware
      #
      # This is the main entry point called by the middleware stack.
      # It handles the before/after/error lifecycle hooks.
      #
      # @param request [Request] The request object
      # @param app [Proc] The next middleware in the chain
      # @return [Response] The response object
      def call(request, app)
        # Before hook
        before(request)

        # Call next middleware
        response = app.call(request)

        # Check if response has an error
        if response.error
          on_error(request, response.error)
        end

        # After hook
        after(request, response)

        response
      rescue StandardError => e
        # Error handling hook (for exceptions raised directly)
        on_error(request, e)
        raise
      end

      protected

      # Hook called before the next middleware
      #
      # Override this method to add logic before the operation executes.
      #
      # @param request [Request] The request object
      # @return [void]
      def before(request)
        # Override in subclass
      end

      # Hook called after successful execution
      #
      # Override this method to add logic after the operation completes.
      #
      # @param request [Request] The request object
      # @param response [Response] The response object
      # @return [void]
      def after(request, response)
        # Override in subclass
      end

      # Hook called when an error occurs
      #
      # Override this method to add error handling logic.
      # The error will be re-raised after this hook executes.
      #
      # @param request [Request] The request object
      # @param error [Exception] The error that occurred
      # @return [void]
      def on_error(request, error)
        # Override in subclass
      end
    end
  end
end
