# frozen_string_literal: true

module Vectra
  # Circuit Breaker pattern for handling provider failures
  #
  # Prevents cascading failures by temporarily stopping requests to a failing provider.
  # The circuit has three states:
  # - :closed - Normal operation, requests pass through
  # - :open - Requests fail immediately without calling provider
  # - :half_open - Limited requests allowed to test if provider recovered
  #
  # @example Basic usage
  #   breaker = Vectra::CircuitBreaker.new(
  #     failure_threshold: 5,
  #     recovery_timeout: 30
  #   )
  #
  #   breaker.call do
  #     client.query(index: "my-index", vector: vec, top_k: 10)
  #   end
  #
  # @example With fallback
  #   breaker.call(fallback: -> { cached_results }) do
  #     client.query(...)
  #   end
  #
  # @example Per-provider circuit breakers
  #   breakers = {
  #     pinecone: Vectra::CircuitBreaker.new(name: "pinecone"),
  #     qdrant: Vectra::CircuitBreaker.new(name: "qdrant")
  #   }
  #
  class CircuitBreaker
    STATES = [:closed, :open, :half_open].freeze

    # Error raised when circuit is open
    class OpenCircuitError < Vectra::Error
      attr_reader :circuit_name, :failures, :opened_at

      def initialize(circuit_name:, failures:, opened_at:)
        @circuit_name = circuit_name
        @failures = failures
        @opened_at = opened_at
        super("Circuit '#{circuit_name}' is open after #{failures} failures")
      end
    end

    attr_reader :name, :state, :failure_count, :success_count,
                :last_failure_at, :opened_at

    # Initialize a new circuit breaker
    #
    # @param name [String] Circuit name for logging/metrics
    # @param failure_threshold [Integer] Failures before opening circuit (default: 5)
    # @param success_threshold [Integer] Successes in half-open to close (default: 3)
    # @param recovery_timeout [Integer] Seconds before trying half-open (default: 30)
    # @param monitored_errors [Array<Class>] Errors that count as failures
    def initialize(
      name: "default",
      failure_threshold: 5,
      success_threshold: 3,
      recovery_timeout: 30,
      monitored_errors: nil
    )
      @name = name
      @failure_threshold = failure_threshold
      @success_threshold = success_threshold
      @recovery_timeout = recovery_timeout
      @monitored_errors = monitored_errors || default_monitored_errors

      @state = :closed
      @failure_count = 0
      @success_count = 0
      @last_failure_at = nil
      @opened_at = nil
      @mutex = Mutex.new
    end

    # Execute block through circuit breaker
    #
    # @param fallback [Proc, nil] Fallback to call when circuit is open
    # @yield The operation to execute
    # @return [Object] Result of block or fallback
    # @raise [OpenCircuitError] If circuit is open and no fallback provided
    def call(fallback: nil)
      check_state!

      if open?
        return handle_open_circuit(fallback)
      end

      execute_with_monitoring { yield }
    rescue *@monitored_errors => e
      record_failure(e)
      raise
    end

    # Force circuit to closed state (manual reset)
    #
    # @return [void]
    def reset!
      @mutex.synchronize do
        transition_to(:closed)
        @failure_count = 0
        @success_count = 0
        @last_failure_at = nil
        @opened_at = nil
      end
    end

    # Force circuit to open state (manual trip)
    #
    # @return [void]
    def trip!
      @mutex.synchronize do
        transition_to(:open)
        @opened_at = Time.now
      end
    end

    # Check if circuit is closed (normal operation)
    #
    # @return [Boolean]
    def closed?
      state == :closed
    end

    # Check if circuit is open (blocking requests)
    #
    # @return [Boolean]
    def open?
      state == :open
    end

    # Check if circuit is half-open (testing recovery)
    #
    # @return [Boolean]
    def half_open?
      state == :half_open
    end

    # Get circuit statistics
    #
    # @return [Hash]
    def stats
      {
        name: name,
        state: state,
        failure_count: failure_count,
        success_count: success_count,
        failure_threshold: @failure_threshold,
        success_threshold: @success_threshold,
        recovery_timeout: @recovery_timeout,
        last_failure_at: last_failure_at,
        opened_at: opened_at
      }
    end

    private

    def default_monitored_errors
      [
        Vectra::ServerError,
        Vectra::ConnectionError,
        Vectra::TimeoutError
      ]
    end

    def check_state!
      @mutex.synchronize do
        # Check if we should transition from open to half-open
        if open? && recovery_timeout_elapsed?
          transition_to(:half_open)
          @success_count = 0
        end
      end
    end

    def recovery_timeout_elapsed?
      return false unless opened_at

      Time.now - opened_at >= @recovery_timeout
    end

    def handle_open_circuit(fallback)
      if fallback
        log_fallback
        fallback.call
      else
        raise OpenCircuitError.new(
          circuit_name: name,
          failures: failure_count,
          opened_at: opened_at
        )
      end
    end

    def execute_with_monitoring
      result = yield
      record_success
      result
    end

    def record_success
      @mutex.synchronize do
        @success_count += 1

        # In half-open, check if we should close
        if half_open? && @success_count >= @success_threshold
          transition_to(:closed)
          @failure_count = 0
          log_circuit_closed
        end
      end
    end

    def record_failure(error)
      @mutex.synchronize do
        @failure_count += 1
        @last_failure_at = Time.now

        # In half-open, immediately open again
        if half_open?
          transition_to(:open)
          @opened_at = Time.now
          log_circuit_reopened(error)
          return
        end

        # In closed, check threshold
        if closed? && @failure_count >= @failure_threshold
          transition_to(:open)
          @opened_at = Time.now
          log_circuit_opened(error)
        end
      end
    end

    def transition_to(new_state)
      @state = new_state
    end

    def log_circuit_opened(error)
      logger&.error(
        "[Vectra::CircuitBreaker] Circuit '#{name}' opened after #{failure_count} failures. " \
        "Last error: #{error.class} - #{error.message}"
      )
    end

    def log_circuit_closed
      logger&.info(
        "[Vectra::CircuitBreaker] Circuit '#{name}' closed after #{success_count} successes"
      )
    end

    def log_circuit_reopened(error)
      logger&.warn(
        "[Vectra::CircuitBreaker] Circuit '#{name}' reopened. " \
        "Recovery failed: #{error.class} - #{error.message}"
      )
    end

    def log_fallback
      logger&.info(
        "[Vectra::CircuitBreaker] Circuit '#{name}' open, using fallback"
      )
    end

    def logger
      Vectra.configuration.logger
    end
  end

  # Circuit breaker registry for managing multiple circuits
  #
  # @example
  #   Vectra::CircuitBreakerRegistry.register(:pinecone, failure_threshold: 3)
  #   Vectra::CircuitBreakerRegistry.register(:qdrant, failure_threshold: 5)
  #
  #   Vectra::CircuitBreakerRegistry[:pinecone].call { ... }
  #
  module CircuitBreakerRegistry
    class << self
      # Get or create a circuit breaker
      #
      # @param name [Symbol, String] Circuit name
      # @return [CircuitBreaker]
      def [](name)
        circuits[name.to_sym]
      end

      # Register a new circuit breaker
      #
      # @param name [Symbol, String] Circuit name
      # @param options [Hash] CircuitBreaker options
      # @return [CircuitBreaker]
      def register(name, **options)
        circuits[name.to_sym] = CircuitBreaker.new(name: name.to_s, **options)
      end

      # Get all registered circuits
      #
      # @return [Hash<Symbol, CircuitBreaker>]
      def all
        circuits.dup
      end

      # Reset all circuits
      #
      # @return [void]
      def reset_all!
        circuits.each_value(&:reset!)
      end

      # Get stats for all circuits
      #
      # @return [Hash<Symbol, Hash>]
      def stats
        circuits.transform_values(&:stats)
      end

      # Clear all registered circuits
      #
      # @return [void]
      def clear!
        @circuits = {}
      end

      private

      def circuits
        @circuits ||= {}
      end
    end
  end
end
