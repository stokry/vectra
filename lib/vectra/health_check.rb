# frozen_string_literal: true

require "timeout"

module Vectra
  # Health check functionality for Vectra clients
  #
  # Provides health check methods to verify connectivity and status
  # of vector database providers.
  #
  # @example Basic health check
  #   client = Vectra::Client.new(provider: :pinecone, ...)
  #   result = client.health_check
  #   puts result[:healthy]  # => true/false
  #
  # @example Detailed health check
  #   result = client.health_check(
  #     index: "my-index",
  #     include_stats: true
  #   )
  #
  module HealthCheck
    # Perform health check on the provider
    #
    # @param index [String, nil] Index to check (uses first available if nil)
    # @param include_stats [Boolean] Include index statistics
    # @param timeout [Float] Health check timeout in seconds
    # @return [HealthCheckResult]
    def health_check(index: nil, include_stats: false, timeout: 5)
      start_time = Time.now

      # For health checks we bypass client middleware and call the provider
      # directly to avoid interference from custom stacks.
      indexes = with_timeout(timeout) { provider.list_indexes }
      index_name = index || indexes.first&.dig(:name)

      result = base_result(start_time, indexes)
      add_index_stats(result, index_name, include_stats, timeout)
      add_pool_stats(result)

      HealthCheckResult.new(**result)
    rescue StandardError => e
      failure_result(start_time, e)
    end

    # Quick health check - just tests connectivity
    #
    # @param timeout [Float] Timeout in seconds
    # @return [Boolean] true if healthy
    def healthy?(timeout: 5)
      health_check(timeout: timeout).healthy?
    end

    private

    def with_timeout(seconds, &)
      Timeout.timeout(seconds, &)
    rescue Timeout::Error
      raise Vectra::TimeoutError, "Health check timed out after #{seconds}s"
    end

    def base_result(start_time, indexes)
      {
        healthy: true,
        provider: provider_name,
        latency_ms: latency_since(start_time),
        indexes_available: indexes.size,
        checked_at: current_time_iso
      }
    end

    def add_index_stats(result, index_name, include_stats, timeout)
      return unless include_stats && index_name

      stats = with_timeout(timeout) { provider.stats(index: index_name) }
      result[:index] = index_name
      result[:stats] = {
        vector_count: stats[:total_vector_count],
        dimension: stats[:dimension]
      }.compact
    end

    def add_pool_stats(result)
      return unless provider.respond_to?(:pool_stats)

      pool = provider.pool_stats
      result[:pool] = pool unless pool[:status] == "not_initialized"
    end

    def failure_result(start_time, error)
      HealthCheckResult.new(
        healthy: false,
        provider: provider_name,
        latency_ms: latency_since(start_time),
        error: error.class.name,
        error_message: error.message,
        checked_at: current_time_iso
      )
    end

    def latency_since(start_time)
      ((Time.now - start_time) * 1000).round(2)
    end

    def current_time_iso
      Time.now.utc.iso8601
    end
  end

  # Health check result object
  #
  # @example
  #   result = client.health_check
  #   if result.healthy?
  #     puts "All good! Latency: #{result.latency_ms}ms"
  #   else
  #     puts "Error: #{result.error_message}"
  #   end
  #
  class HealthCheckResult
    attr_reader :provider, :latency_ms, :indexes_available, :checked_at,
                :index, :stats, :pool, :error, :error_message

    def initialize(healthy:, provider:, latency_ms:, checked_at:,
                   indexes_available: nil, index: nil, stats: nil,
                   pool: nil, error: nil, error_message: nil)
      @healthy = healthy
      @provider = provider
      @latency_ms = latency_ms
      @checked_at = checked_at
      @indexes_available = indexes_available
      @index = index
      @stats = stats
      @pool = pool
      @error = error
      @error_message = error_message
    end

    # Check if the health check passed
    #
    # @return [Boolean]
    def healthy?
      @healthy
    end

    # Check if the health check failed
    #
    # @return [Boolean]
    def unhealthy?
      !@healthy
    end

    # Convert to hash
    #
    # @return [Hash]
    def to_h
      {
        healthy: @healthy,
        provider: provider,
        latency_ms: latency_ms,
        checked_at: checked_at,
        indexes_available: indexes_available,
        index: index,
        stats: stats,
        pool: pool,
        error: error,
        error_message: error_message
      }.compact
    end

    # Convert to JSON
    #
    # @return [String]
    def to_json(*)
      JSON.generate(to_h)
    end
  end

  # Aggregate health checker for multiple providers
  #
  # @example
  #   checker = Vectra::AggregateHealthCheck.new(
  #     pinecone: pinecone_client,
  #     qdrant: qdrant_client,
  #     pgvector: pgvector_client
  #   )
  #
  #   result = checker.check_all
  #   puts result[:overall_healthy]
  #
  class AggregateHealthCheck
    attr_reader :clients

    # Initialize aggregate health checker
    #
    # @param clients [Hash<Symbol, Client>] Named clients to check
    def initialize(**clients)
      @clients = clients
    end

    # Check health of all clients
    #
    # @param parallel [Boolean] Run checks in parallel
    # @param timeout [Float] Timeout per check
    # @return [Hash] Aggregate results
    def check_all(parallel: true, timeout: 5)
      start_time = Time.now

      results = if parallel
                  check_parallel(timeout)
                else
                  check_sequential(timeout)
                end

      healthy_count = results.count { |_, r| r.healthy? }
      all_healthy = healthy_count == results.size

      {
        overall_healthy: all_healthy,
        healthy_count: healthy_count,
        total_count: results.size,
        total_latency_ms: ((Time.now - start_time) * 1000).round(2),
        checked_at: Time.now.utc.iso8601,
        results: results.transform_values(&:to_h)
      }
    end

    # Check if all providers are healthy
    #
    # @return [Boolean]
    def all_healthy?(timeout: 5)
      check_all(timeout: timeout)[:overall_healthy]
    end

    # Check if any provider is healthy
    #
    # @return [Boolean]
    def any_healthy?(timeout: 5)
      check_all(timeout: timeout)[:healthy_count].positive?
    end

    private

    def check_parallel(timeout)
      threads = clients.map do |name, client|
        Thread.new { [name, client.health_check(timeout: timeout)] }
      end

      threads.to_h(&:value)
    end

    def check_sequential(timeout)
      clients.transform_values { |client| client.health_check(timeout: timeout) }
    end
  end
end
