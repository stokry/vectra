# frozen_string_literal: true

require "digest"

module Vectra
  # Optional caching layer for frequently queried vectors
  #
  # Provides in-memory caching with TTL support for query results
  # and fetched vectors to reduce database load.
  #
  # @example Basic usage
  #   cache = Vectra::Cache.new(ttl: 300, max_size: 1000)
  #   cached_client = Vectra::CachedClient.new(client, cache: cache)
  #
  #   # First call hits the database
  #   result1 = cached_client.query(index: 'idx', vector: vec, top_k: 10)
  #
  #   # Second call returns cached result
  #   result2 = cached_client.query(index: 'idx', vector: vec, top_k: 10)
  #
  class Cache
    DEFAULT_TTL = 300 # 5 minutes
    DEFAULT_MAX_SIZE = 1000

    attr_reader :ttl, :max_size

    # Initialize cache
    #
    # @param ttl [Integer] time-to-live in seconds (default: 300)
    # @param max_size [Integer] maximum cache entries (default: 1000)
    def initialize(ttl: DEFAULT_TTL, max_size: DEFAULT_MAX_SIZE)
      @ttl = ttl
      @max_size = max_size
      @store = {}
      @timestamps = {}
      @mutex = Mutex.new
    end

    # Get value from cache
    #
    # @param key [String] cache key
    # @return [Object, nil] cached value or nil if not found/expired
    def get(key)
      @mutex.synchronize do
        return nil unless @store.key?(key)

        if expired?(key)
          delete_entry(key)
          return nil
        end

        @store[key]
      end
    end

    # Set value in cache
    #
    # @param key [String] cache key
    # @param value [Object] value to cache
    # @return [Object] the cached value
    def set(key, value)
      @mutex.synchronize do
        evict_if_needed
        @store[key] = value
        @timestamps[key] = Time.now
        value
      end
    end

    # Get or set value with block
    #
    # @param key [String] cache key
    # @yield block to compute value if not cached
    # @return [Object] cached or computed value
    def fetch(key)
      cached = get(key)
      return cached unless cached.nil?

      value = yield
      set(key, value)
      value
    end

    # Delete entry from cache
    #
    # @param key [String] cache key
    # @return [Object, nil] deleted value
    def delete(key)
      @mutex.synchronize { delete_entry(key) }
    end

    # Clear all cache entries
    #
    # @return [void]
    def clear
      @mutex.synchronize do
        @store.clear
        @timestamps.clear
      end
    end

    # Get cache statistics
    #
    # @return [Hash] cache stats
    def stats
      @mutex.synchronize do
        {
          size: @store.size,
          max_size: max_size,
          ttl: ttl,
          keys: @store.keys
        }
      end
    end

    # Check if key exists and is not expired
    #
    # @param key [String] cache key
    # @return [Boolean]
    def exist?(key)
      @mutex.synchronize do
        return false unless @store.key?(key)
        return false if expired?(key)

        true
      end
    end

    private

    def expired?(key)
      return true unless @timestamps.key?(key)

      Time.now - @timestamps[key] > ttl
    end

    def delete_entry(key)
      @timestamps.delete(key)
      @store.delete(key)
    end

    def evict_if_needed
      return if @store.size < max_size

      # Remove oldest entries
      entries_to_remove = (@store.size - max_size) + (@max_size * 0.1).to_i
      oldest = @timestamps.sort_by { |_, v| v }.first(entries_to_remove)
      oldest.each { |key, _| delete_entry(key) }
    end
  end

  # Client wrapper with caching support
  #
  # Wraps a Vectra::Client to add transparent caching for query and fetch operations.
  #
  class CachedClient
    attr_reader :client, :cache

    # Initialize cached client
    #
    # @param client [Client] the underlying Vectra client
    # @param cache [Cache] cache instance (creates default if nil)
    # @param cache_queries [Boolean] whether to cache query results (default: true)
    # @param cache_fetches [Boolean] whether to cache fetch results (default: true)
    def initialize(client, cache: nil, cache_queries: true, cache_fetches: true)
      @client = client
      @cache = cache || Cache.new
      @cache_queries = cache_queries
      @cache_fetches = cache_fetches
    end

    # Query with caching
    #
    # @see Client#query
    def query(index:, vector:, top_k: 10, namespace: nil, filter: nil, **options)
      return client.query(index: index, vector: vector, top_k: top_k,
                          namespace: namespace, filter: filter, **options) unless @cache_queries

      key = query_cache_key(index, vector, top_k, namespace, filter)
      cache.fetch(key) do
        client.query(index: index, vector: vector, top_k: top_k,
                     namespace: namespace, filter: filter, **options)
      end
    end

    # Fetch with caching
    #
    # @see Client#fetch
    def fetch(index:, ids:, namespace: nil)
      return client.fetch(index: index, ids: ids, namespace: namespace) unless @cache_fetches

      # Check cache for each ID
      results = {}
      uncached_ids = []

      ids.each do |id|
        key = fetch_cache_key(index, id, namespace)
        cached = cache.get(key)
        if cached
          results[id] = cached
        else
          uncached_ids << id
        end
      end

      # Fetch uncached IDs
      if uncached_ids.any?
        fetched = client.fetch(index: index, ids: uncached_ids, namespace: namespace)
        fetched.each do |id, vector|
          key = fetch_cache_key(index, id, namespace)
          cache.set(key, vector)
          results[id] = vector
        end
      end

      results
    end

    # Pass through other methods to underlying client
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

    # Invalidate cache entries for an index
    #
    # @param index [String] index name
    def invalidate_index(index)
      cache.stats[:keys].each do |key|
        cache.delete(key) if key.start_with?("#{index}:")
      end
    end

    # Clear entire cache
    def clear_cache
      cache.clear
    end

    private

    def query_cache_key(index, vector, top_k, namespace, filter)
      vector_hash = Digest::MD5.hexdigest(vector.to_s)[0, 16]
      filter_hash = filter ? Digest::MD5.hexdigest(filter.to_s)[0, 8] : "nofilter"
      "#{index}:q:#{vector_hash}:#{top_k}:#{namespace || 'default'}:#{filter_hash}"
    end

    def fetch_cache_key(index, id, namespace)
      "#{index}:f:#{id}:#{namespace || 'default'}"
    end
  end
end
