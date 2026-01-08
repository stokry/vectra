# frozen_string_literal: true

require "concurrent"

module Vectra
  # Connection pool with warmup support
  #
  # Provides connection pooling for database providers with configurable
  # pool size, timeout, and connection warmup.
  #
  # @example Basic usage
  #   pool = Vectra::Pool.new(size: 5, timeout: 5) { create_connection }
  #   pool.warmup(3) # Pre-create 3 connections
  #
  #   pool.with_connection do |conn|
  #     conn.execute("SELECT 1")
  #   end
  #
  class Pool
    class TimeoutError < Vectra::Error; end
    class PoolExhaustedError < Vectra::Error; end

    attr_reader :size, :timeout

    # Initialize connection pool
    #
    # @param size [Integer] maximum pool size
    # @param timeout [Integer] checkout timeout in seconds
    # @yield connection factory block
    def initialize(size:, timeout: 5, &block)
      raise ArgumentError, "Connection factory block required" unless block_given?

      @size = size
      @timeout = timeout
      @factory = block
      @pool = Concurrent::Array.new
      @checked_out = Concurrent::AtomicFixnum.new(0)
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @shutdown = false
    end

    # Warmup the pool by pre-creating connections
    #
    # @param count [Integer] number of connections to create (default: pool size)
    # @return [Integer] number of connections created
    def warmup(count = nil)
      count ||= size
      count = [count, size].min
      created = 0

      count.times do
        break if @pool.size >= size

        conn = create_connection
        if conn
          @pool << conn
          created += 1
        end
      end

      created
    end

    # Execute block with a connection from the pool
    #
    # @yield [connection] the checked out connection
    # @return [Object] result of the block
    def with_connection
      conn = checkout
      begin
        yield conn
      ensure
        checkin(conn)
      end
    end

    # Checkout a connection from the pool
    #
    # @return [Object] a connection
    # @raise [TimeoutError] if checkout times out
    # @raise [PoolExhaustedError] if pool is exhausted
    def checkout
      raise PoolExhaustedError, "Pool has been shutdown" if @shutdown

      deadline = Time.now + timeout

      @mutex.synchronize do
        loop do
          # Try to get an existing connection
          conn = @pool.pop
          if conn
            @checked_out.increment
            return conn if healthy?(conn)

            # Connection is unhealthy, discard and try again
            close_connection(conn)
            next
          end

          # Try to create a new connection if under limit
          if @checked_out.value + @pool.size < size
            conn = create_connection
            if conn
              @checked_out.increment
              return conn
            end
          end

          # Wait for a connection to be returned
          remaining = deadline - Time.now
          raise TimeoutError, "Connection checkout timed out after #{timeout}s" if remaining <= 0

          @condition.wait(@mutex, remaining)
        end
      end
    end

    # Return a connection to the pool
    #
    # @param connection [Object] connection to return
    def checkin(connection)
      return if @shutdown

      @mutex.synchronize do
        @checked_out.decrement
        if healthy?(connection) && @pool.size < size
          @pool << connection
        else
          close_connection(connection)
        end
        @condition.signal
      end
    end

    # Shutdown the pool, closing all connections
    #
    # @return [void]
    def shutdown
      @shutdown = true
      @mutex.synchronize do
        while (conn = @pool.pop)
          close_connection(conn)
        end
      end
    end

    # Get pool statistics
    #
    # @return [Hash] pool stats
    def stats
      {
        size: size,
        available: @pool.size,
        checked_out: @checked_out.value,
        total_created: @pool.size + @checked_out.value,
        shutdown: @shutdown
      }
    end

    # Check if pool is healthy (public method)
    #
    # @return [Boolean]
    def pool_healthy?
      !@shutdown && @pool.size + @checked_out.value > 0
    end

    private

    # Internal health check for individual connections
    def healthy?(conn)
      return false if conn.nil?
      return true unless conn.respond_to?(:status)

      # For PG connections, check status. Otherwise assume healthy.
      if defined?(PG::CONNECTION_OK)
        conn.status == PG::CONNECTION_OK
      else
        # If PG not loaded, assume connection is healthy if it exists
        true
      end
    rescue StandardError
      false
    end

    def create_connection
      @factory.call
    rescue StandardError => e
      Vectra.configuration.logger&.error("Pool: Failed to create connection: #{e.message}")
      nil
    end

    def close_connection(conn)
      conn.close if conn.respond_to?(:close)
    rescue StandardError => e
      Vectra.configuration.logger&.warn("Pool: Error closing connection: #{e.message}")
    end
  end

  # Pooled connection module for pgvector
  module PooledConnection
    # Get a pooled connection
    #
    # @return [Pool] connection pool
    def connection_pool
      @connection_pool ||= create_pool
    end

    # Warmup the connection pool
    #
    # @param count [Integer] number of connections to pre-create
    # @return [Integer] connections created
    def warmup_pool(count = nil)
      connection_pool.warmup(count)
    end

    # Execute with pooled connection
    #
    # @yield [connection] database connection
    def with_pooled_connection(&)
      connection_pool.with_connection(&)
    end

    # Shutdown the connection pool
    def shutdown_pool
      @connection_pool&.shutdown
      @connection_pool = nil
    end

    # Get pool statistics
    #
    # @return [Hash]
    def pool_stats
      return { status: "not_initialized" } unless @connection_pool

      connection_pool.stats
    end

    private

    def create_pool
      pool_size = config.pool_size || 5
      pool_timeout = config.pool_timeout || 5

      Pool.new(size: pool_size, timeout: pool_timeout) do
        create_raw_connection
      end
    end

    def create_raw_connection
      require "pg"
      conn_params = parse_connection_params
      PG.connect(conn_params)
    end
  end
end
