# frozen_string_literal: true

module Vectra
  module Middleware
    # Retry middleware for handling transient failures
    #
    # Automatically retries failed requests with configurable backoff strategy.
    #
    # @example With default settings (3 attempts, exponential backoff)
    #   Vectra::Client.use Vectra::Middleware::Retry
    #
    # @example With custom settings
    #   Vectra::Client.use Vectra::Middleware::Retry, max_attempts: 5, backoff: :linear
    #
    # @example Per-client retry
    #   client = Vectra::Client.new(
    #     provider: :pinecone,
    #     middleware: [[Vectra::Middleware::Retry, { max_attempts: 3 }]]
    #   )
    #
    class Retry < Base
      # @param max_attempts [Integer] Maximum number of attempts (default: 3)
      # @param backoff [Symbol, Numeric] Backoff strategy (:exponential, :linear) or fixed delay
      def initialize(max_attempts: 3, backoff: :exponential)
        super()
        @max_attempts = max_attempts
        @backoff = backoff
      end

      def call(request, app)
        attempt = 0
        last_error = nil

        loop do
          attempt += 1

          begin
            response = app.call(request)

            # If successful, return immediately
            if response.success?
              response.metadata[:retry_count] = attempt - 1
              return response
            end

            # If error is retryable and we haven't exceeded max attempts, retry
            if response.error && retryable?(response.error) && attempt < @max_attempts
              sleep(backoff_delay(attempt))
              next
            end

            # Error is not retryable or max attempts reached, return response
            response.metadata[:retry_count] = attempt - 1
            return response
          rescue StandardError => e
            last_error = e

            # If error is retryable and we haven't exceeded max attempts, retry
            if retryable?(e) && attempt < @max_attempts
              sleep(backoff_delay(attempt))
              next
            end

            # Error is not retryable or max attempts reached, raise
            raise
          end
        end
      end

      private

      # Check if error is retryable
      #
      # @param error [Exception] The error to check
      # @return [Boolean] true if error is retryable
      def retryable?(error)
        error.is_a?(Vectra::RateLimitError) ||
          error.is_a?(Vectra::ConnectionError) ||
          error.is_a?(Vectra::TimeoutError) ||
          error.is_a?(Vectra::ServerError)
      end

      # Calculate backoff delay
      #
      # @param attempt [Integer] Current attempt number
      # @return [Float] Delay in seconds
      def backoff_delay(attempt)
        case @backoff
        when :exponential
          # 0.2s, 0.4s, 0.8s, 1.6s, ...
          (2**(attempt - 1)) * 0.2
        when :linear
          # 0.5s, 1.0s, 1.5s, 2.0s, ...
          attempt * 0.5
        when Numeric
          @backoff
        else
          1.0
        end
      end
    end
  end
end
