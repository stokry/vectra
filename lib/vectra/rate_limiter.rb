# frozen_string_literal: true

module Vectra
  # Proactive rate limiter using token bucket algorithm
  #
  # Throttles requests BEFORE sending to prevent rate limit errors from providers.
  # Uses token bucket algorithm for smooth rate limiting with burst support.
  #
  # @example Basic usage
  #   limiter = Vectra::RateLimiter.new(
  #     requests_per_second: 10,
  #     burst_size: 20
  #   )
  #
  #   limiter.acquire do
  #     client.query(...)
  #   end
  #
  # @example With client wrapper
  #   client = Vectra::RateLimitedClient.new(
  #     Vectra::Client.new(...),
  #     requests_per_second: 10
  #   )
  #   client.query(...)  # Automatically rate limited
  #
  class RateLimiter
    class RateLimitExceededError < Vectra::Error
      attr_reader :wait_time

      def initialize(wait_time:)
        @wait_time = wait_time
        super("Rate limit exceeded. Retry after #{wait_time.round(2)} seconds")
      end
    end

    attr_reader :requests_per_second, :burst_size

    # Initialize rate limiter
    #
    # @param requests_per_second [Float] Sustained request rate
    # @param burst_size [Integer] Maximum burst capacity (default: 2x RPS)
    def initialize(requests_per_second:, burst_size: nil)
      @requests_per_second = requests_per_second.to_f
      @burst_size = burst_size || (requests_per_second * 2).to_i
      @tokens = @burst_size.to_f
      @last_refill = Time.now
      @mutex = Mutex.new
    end

    # Acquire a token and execute block
    #
    # @param wait [Boolean] Wait for token if not available (default: true)
    # @param timeout [Float] Maximum wait time in seconds (default: 30)
    # @yield Block to execute after acquiring token
    # @return [Object] Result of block
    # @raise [RateLimitExceededError] If wait is false and no token available
    def acquire(wait: true, timeout: 30, &)
      acquired = try_acquire(wait: wait, timeout: timeout)

      unless acquired
        wait_time = time_until_token
        raise RateLimitExceededError.new(wait_time: wait_time)
      end

      yield
    end

    # Try to acquire a token without blocking
    #
    # @return [Boolean] true if token acquired
    def try_acquire(wait: false, timeout: 30)
      deadline = Time.now + timeout

      loop do
        @mutex.synchronize do
          refill_tokens
          if @tokens >= 1
            @tokens -= 1
            return true
          end
        end

        return false unless wait
        return false if Time.now >= deadline

        # Wait a bit before retrying
        sleep([time_until_token, 0.1].min)
      end
    end

    # Get current token count
    #
    # @return [Float]
    def available_tokens
      @mutex.synchronize do
        refill_tokens
        @tokens
      end
    end

    # Get time until next token is available
    #
    # @return [Float] Seconds until next token
    def time_until_token
      @mutex.synchronize do
        refill_tokens
        return 0 if @tokens >= 1

        tokens_needed = 1 - @tokens
        tokens_needed / @requests_per_second
      end
    end

    # Get rate limiter statistics
    #
    # @return [Hash]
    def stats
      @mutex.synchronize do
        refill_tokens
        {
          requests_per_second: @requests_per_second,
          burst_size: @burst_size,
          available_tokens: @tokens.round(2),
          time_until_token: @tokens >= 1 ? 0 : ((1 - @tokens) / @requests_per_second).round(3)
        }
      end
    end

    # Reset the rate limiter to full capacity
    #
    # @return [void]
    def reset!
      @mutex.synchronize do
        @tokens = @burst_size.to_f
        @last_refill = Time.now
      end
    end

    private

    def refill_tokens
      now = Time.now
      elapsed = now - @last_refill
      @last_refill = now

      # Add tokens based on elapsed time
      new_tokens = elapsed * @requests_per_second
      @tokens = [@tokens + new_tokens, @burst_size.to_f].min
    end
  end

  # Client wrapper with automatic rate limiting
  #
  # @example
  #   client = Vectra::RateLimitedClient.new(
  #     Vectra::Client.new(provider: :pinecone, ...),
  #     requests_per_second: 10,
  #     burst_size: 20
  #   )
  #
  #   client.query(...)  # Automatically waits if rate limited
  #
  class RateLimitedClient
    RATE_LIMITED_METHODS = [:upsert, :query, :fetch, :update, :delete].freeze

    attr_reader :client, :limiter

    # Initialize rate limited client
    #
    # @param client [Client] The underlying Vectra client
    # @param requests_per_second [Float] Request rate limit
    # @param burst_size [Integer] Burst capacity
    # @param wait [Boolean] Wait for rate limit (default: true)
    def initialize(client, requests_per_second:, burst_size: nil, wait: true)
      @client = client
      @limiter = RateLimiter.new(
        requests_per_second: requests_per_second,
        burst_size: burst_size
      )
      @wait = wait
    end

    # Rate-limited upsert
    def upsert(...)
      with_rate_limit { client.upsert(...) }
    end

    # Rate-limited query
    def query(...)
      with_rate_limit { client.query(...) }
    end

    # Rate-limited fetch
    def fetch(...)
      with_rate_limit { client.fetch(...) }
    end

    # Rate-limited update
    def update(...)
      with_rate_limit { client.update(...) }
    end

    # Rate-limited delete
    def delete(...)
      with_rate_limit { client.delete(...) }
    end

    # Pass through other methods without rate limiting
    def method_missing(method, *, **, &)
      if client.respond_to?(method)
        client.public_send(method, *, **, &)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      client.respond_to?(method, include_private) || super
    end

    # Get rate limiter stats
    #
    # @return [Hash]
    def rate_limit_stats
      limiter.stats
    end

    private

    def with_rate_limit(&)
      limiter.acquire(wait: @wait, &)
    end
  end

  # Per-provider rate limiter registry
  #
  # @example
  #   # Configure rate limits per provider
  #   Vectra::RateLimiterRegistry.configure(:pinecone, requests_per_second: 100)
  #   Vectra::RateLimiterRegistry.configure(:qdrant, requests_per_second: 50)
  #
  #   # Get limiter for provider
  #   limiter = Vectra::RateLimiterRegistry[:pinecone]
  #   limiter.acquire { ... }
  #
  module RateLimiterRegistry
    class << self
      # Configure rate limiter for provider
      #
      # @param provider [Symbol] Provider name
      # @param requests_per_second [Float] Request rate
      # @param burst_size [Integer] Burst capacity
      # @return [RateLimiter]
      def configure(provider, requests_per_second:, burst_size: nil)
        limiters[provider.to_sym] = RateLimiter.new(
          requests_per_second: requests_per_second,
          burst_size: burst_size
        )
      end

      # Get limiter for provider
      #
      # @param provider [Symbol] Provider name
      # @return [RateLimiter, nil]
      def [](provider)
        limiters[provider.to_sym]
      end

      # Get all configured limiters
      #
      # @return [Hash<Symbol, RateLimiter>]
      def all
        limiters.dup
      end

      # Get stats for all limiters
      #
      # @return [Hash<Symbol, Hash>]
      def stats
        limiters.transform_values(&:stats)
      end

      # Reset all limiters
      #
      # @return [void]
      def reset_all!
        limiters.each_value(&:reset!)
      end

      # Clear all limiters
      #
      # @return [void]
      def clear!
        @limiters = {}
      end

      private

      def limiters
        @limiters ||= {}
      end
    end
  end
end
