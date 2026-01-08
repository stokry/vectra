# frozen_string_literal: true

require 'connection_pool'

module Vectra
  # Retry helper for transient errors
  #
  # Provides exponential backoff retry logic for database operations.
  #
  # @example
  #   include Vectra::Retry
  #
  #   with_retry(max_attempts: 3) do
  #     connection.exec_params(sql, params)
  #   end
  #
  module Retry
    # Errors that should be retried
    RETRYABLE_PG_ERRORS = [
      "PG::ConnectionBad",
      "PG::UnableToSend",
      "PG::AdminShutdown",
      "PG::CrashShutdown",
      "PG::CannotConnectNow",
      "PG::TooManyConnections",
      "PG::SerializationFailure",
      "PG::DeadlockDetected"
    ].freeze

    # Execute block with retry logic
    #
    # @param max_attempts [Integer] Maximum number of attempts (default: from config)
    # @param base_delay [Float] Initial delay in seconds (default: from config)
    # @param max_delay [Float] Maximum delay in seconds (default: 30)
    # @param backoff_factor [Float] Multiplier for each retry (default: 2)
    # @param jitter [Boolean] Add randomness to delay (default: true)
    # @yield The block to execute with retry logic
    # @return [Object] The result of the block
    #
    # @example
    #   result = with_retry(max_attempts: 5) do
    #     perform_database_operation
    #   end
    #
    def with_retry(max_attempts: nil, base_delay: nil, max_delay: 30, backoff_factor: 2, jitter: true, &block)
      max_attempts ||= config.max_retries
      base_delay ||= config.retry_delay

      attempt = 0
      last_error = nil

      loop do
        attempt += 1

        begin
          return block.call
        rescue StandardError => e
          last_error = e

          # Don't retry if not retryable or out of attempts
          should_retry = retryable_error?(e) && attempt < max_attempts

          unless should_retry
            log_error("Operation failed after #{attempt} attempts", e)
            raise
          end

          # Calculate delay with exponential backoff
          delay = calculate_delay(
            attempt: attempt,
            base_delay: base_delay,
            max_delay: max_delay,
            backoff_factor: backoff_factor,
            jitter: jitter
          )

          log_retry(attempt, max_attempts, delay, e)
          sleep(delay)
        end
      end
    end

    private

    # Check if error should be retried
    #
    # @param error [Exception] The error to check
    # @return [Boolean]
    def retryable_error?(error)
      error_class = error.class.name

      # Check if it's a retryable PG error
      return true if RETRYABLE_PG_ERRORS.include?(error_class)

      # Check if it's a connection pool timeout
      return true if error.instance_of?(::ConnectionPool::TimeoutError)

      # Check message for specific patterns
      error_message = error.message.downcase
      error_message.include?("timeout") ||
        error_message.include?("connection") ||
        error_message.include?("temporary")
    end

    # Calculate exponential backoff delay
    #
    # @param attempt [Integer] Current attempt number
    # @param base_delay [Float] Base delay in seconds
    # @param max_delay [Float] Maximum delay in seconds
    # @param backoff_factor [Float] Multiplier for each retry
    # @param jitter [Boolean] Add randomness
    # @return [Float] Delay in seconds
    def calculate_delay(attempt:, base_delay:, max_delay:, backoff_factor:, jitter:)
      # Exponential backoff: base_delay * (backoff_factor ^ (attempt - 1))
      delay = base_delay * (backoff_factor**(attempt - 1))

      # Cap at max_delay
      delay = [delay, max_delay].min

      # Add jitter (±25% randomness)
      if jitter
        jitter_amount = delay * 0.25
        delay += rand(-jitter_amount..jitter_amount)
      end

      delay.clamp(base_delay, max_delay)
    end

    # Log retry attempt
    #
    # @param attempt [Integer] Current attempt
    # @param max_attempts [Integer] Maximum attempts
    # @param delay [Float] Delay before next attempt
    # @param error [Exception] The error that triggered retry
    def log_retry(attempt, max_attempts, delay, error)
      return unless config.logger

      config.logger.warn(
        "[Vectra] Retry attempt #{attempt}/#{max_attempts} after error: " \
        "#{error.class} - #{error.message}. Waiting #{delay.round(2)}s..."
      )
    end
  end
end
