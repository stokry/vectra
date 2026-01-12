# frozen_string_literal: true

module Vectra
  # Unified client for vector database operations
  #
  # The Client class provides a unified interface to interact with various
  # vector database providers. It automatically routes operations to the
  # configured provider.
  #
  # @example Using global configuration
  #   Vectra.configure do |config|
  #     config.provider = :pinecone
  #     config.api_key = ENV['PINECONE_API_KEY']
  #     config.environment = 'us-east-1'
  #   end
  #
  #   client = Vectra::Client.new
  #   client.upsert(index: 'my-index', vectors: [...])
  #
  # @example Using instance configuration
  #   client = Vectra::Client.new(
  #     provider: :pinecone,
  #     api_key: ENV['PINECONE_API_KEY'],
  #     environment: 'us-east-1'
  #   )
  #
  class Client
    include HealthCheck

    attr_reader :config, :provider

    # Initialize a new Client
    #
    # @param provider [Symbol, nil] provider name (:pinecone, :qdrant, :weaviate)
    # @param api_key [String, nil] API key
    # @param environment [String, nil] environment/region
    # @param host [String, nil] custom host URL
    # @param options [Hash] additional options
    def initialize(provider: nil, api_key: nil, environment: nil, host: nil, **options)
      @config = build_config(provider, api_key, environment, host, options)
      @config.validate!
      @provider = build_provider
    end

    # Upsert vectors into an index
    #
    # @param index [String] the index/collection name
    # @param vectors [Array<Hash, Vector>] vectors to upsert
    # @param namespace [String, nil] optional namespace (provider-specific)
    # @return [Hash] upsert response with :upserted_count
    #
    # @example Upsert vectors
    #   client.upsert(
    #     index: 'my-index',
    #     vectors: [
    #       { id: 'vec1', values: [0.1, 0.2, 0.3], metadata: { text: 'Hello' } },
    #       { id: 'vec2', values: [0.4, 0.5, 0.6], metadata: { text: 'World' } }
    #     ]
    #   )
    #
    def upsert(index:, vectors:, namespace: nil)
      validate_index!(index)
      validate_vectors!(vectors)

      Instrumentation.instrument(
        operation: :upsert,
        provider: provider_name,
        index: index,
        metadata: { vector_count: vectors.size }
      ) do
        provider.upsert(index: index, vectors: vectors, namespace: namespace)
      end
    end

    # Query vectors by similarity
    #
    # @param index [String] the index/collection name
    # @param vector [Array<Float>] query vector
    # @param top_k [Integer] number of results to return (default: 10)
    # @param namespace [String, nil] optional namespace
    # @param filter [Hash, nil] metadata filter
    # @param include_values [Boolean] include vector values in response
    # @param include_metadata [Boolean] include metadata in response
    # @return [QueryResult] query results
    #
    # @example Simple query
    #   results = client.query(
    #     index: 'my-index',
    #     vector: [0.1, 0.2, 0.3],
    #     top_k: 5
    #   )
    #
    # @example Query with filter
    #   results = client.query(
    #     index: 'my-index',
    #     vector: [0.1, 0.2, 0.3],
    #     top_k: 10,
    #     filter: { category: 'programming' }
    #   )
    #
    # @example Chainable query builder
    #   results = client.query("my-index")
    #     .vector([0.1, 0.2, 0.3])
    #     .top_k(10)
    #     .filter(category: "programming")
    #     .with_metadata
    #     .execute
    #
    def query(index_arg = nil, index: nil, vector: nil, top_k: 10, namespace: nil, filter: nil,
              include_values: false, include_metadata: true)
      # If called with a positional index string only, return a query builder:
      #   client.query("docs").vector(vec).top_k(10).filter(...).execute
      if index_arg && index.nil? && vector.nil? && !block_given?
        return QueryBuilder.new(self, index_arg)
      end

      # Handle positional argument for index in non-builder case
      index = index_arg if index_arg && index.nil?

      # Backwards-compatible path: perform query immediately
      validate_index!(index)
      validate_query_vector!(vector)

      result = nil
      Instrumentation.instrument(
        operation: :query,
        provider: provider_name,
        index: index,
        metadata: { top_k: top_k }
      ) do
        result = provider.query(
          index: index,
          vector: vector,
          top_k: top_k,
          namespace: namespace,
          filter: filter,
          include_values: include_values,
          include_metadata: include_metadata
        )
      end

      result
    end

    # Fetch vectors by IDs
    #
    # @param index [String] the index/collection name
    # @param ids [Array<String>] vector IDs to fetch
    # @param namespace [String, nil] optional namespace
    # @return [Hash<String, Vector>] hash of ID to Vector
    #
    # @example Fetch vectors
    #   vectors = client.fetch(index: 'my-index', ids: ['vec1', 'vec2'])
    #   vectors['vec1'].values # => [0.1, 0.2, 0.3]
    #
    def fetch(index:, ids:, namespace: nil)
      validate_index!(index)
      validate_ids!(ids)

      Instrumentation.instrument(
        operation: :fetch,
        provider: provider_name,
        index: index,
        metadata: { id_count: ids.size }
      ) do
        provider.fetch(index: index, ids: ids, namespace: namespace)
      end
    end

    # Update a vector's metadata or values
    #
    # @param index [String] the index/collection name
    # @param id [String] vector ID
    # @param metadata [Hash, nil] new metadata (merged with existing)
    # @param values [Array<Float>, nil] new vector values
    # @param namespace [String, nil] optional namespace
    # @return [Hash] update response
    #
    # @example Update metadata
    #   client.update(
    #     index: 'my-index',
    #     id: 'vec1',
    #     metadata: { category: 'updated' }
    #   )
    #
    def update(index:, id:, metadata: nil, values: nil, namespace: nil)
      validate_index!(index)
      validate_id!(id)

      raise ValidationError, "Must provide metadata or values to update" if metadata.nil? && values.nil?

      Instrumentation.instrument(
        operation: :update,
        provider: provider_name,
        index: index,
        metadata: { has_metadata: !metadata.nil?, has_values: !values.nil? }
      ) do
        provider.update(
          index: index,
          id: id,
          metadata: metadata,
          values: values,
          namespace: namespace
        )
      end
    end

    # Delete vectors
    #
    # @param index [String] the index/collection name
    # @param ids [Array<String>, nil] vector IDs to delete
    # @param namespace [String, nil] optional namespace
    # @param filter [Hash, nil] delete by metadata filter
    # @param delete_all [Boolean] delete all vectors in namespace
    # @return [Hash] delete response
    #
    # @example Delete by IDs
    #   client.delete(index: 'my-index', ids: ['vec1', 'vec2'])
    #
    # @example Delete by filter
    #   client.delete(index: 'my-index', filter: { category: 'old' })
    #
    # @example Delete all
    #   client.delete(index: 'my-index', delete_all: true)
    #
    def delete(index:, ids: nil, namespace: nil, filter: nil, delete_all: false)
      validate_index!(index)

      if ids.nil? && filter.nil? && !delete_all
        raise ValidationError, "Must provide ids, filter, or delete_all"
      end

      Instrumentation.instrument(
        operation: :delete,
        provider: provider_name,
        index: index,
        metadata: { id_count: ids&.size, delete_all: delete_all, has_filter: !filter.nil? }
      ) do
        provider.delete(
          index: index,
          ids: ids,
          namespace: namespace,
          filter: filter,
          delete_all: delete_all
        )
      end
    end

    # List all indexes
    #
    # @return [Array<Hash>] list of index information
    #
    # @example
    #   indexes = client.list_indexes
    #   indexes.each { |idx| puts idx[:name] }
    #
    def list_indexes
      provider.list_indexes
    end

    # Describe an index
    #
    # @param index [String] the index name
    # @return [Hash] index details
    #
    # @example
    #   info = client.describe_index(index: 'my-index')
    #   puts info[:dimension]
    #
    def describe_index(index:)
      validate_index!(index)
      provider.describe_index(index: index)
    end

    # Get index statistics
    #
    # @param index [String] the index name
    # @param namespace [String, nil] optional namespace
    # @return [Hash] index statistics
    #
    # @example
    #   stats = client.stats(index: 'my-index')
    #   puts "Total vectors: #{stats[:total_vector_count]}"
    #
    def stats(index:, namespace: nil)
      validate_index!(index)
      provider.stats(index: index, namespace: namespace)
    end

    # Hybrid search combining semantic (vector) and keyword (text) search
    #
    # Combines the best of both worlds: semantic understanding from vectors
    # and exact keyword matching from text search.
    #
    # @param index [String] the index/collection name
    # @param vector [Array<Float>] query vector for semantic search
    # @param text [String] text query for keyword search
    # @param alpha [Float] balance between semantic and keyword (0.0 = pure keyword, 1.0 = pure semantic)
    # @param top_k [Integer] number of results to return
    # @param namespace [String, nil] optional namespace
    # @param filter [Hash, nil] metadata filter
    # @param include_values [Boolean] include vector values in results
    # @param include_metadata [Boolean] include metadata in results
    # @return [QueryResult] search results
    #
    # @example Basic hybrid search
    #   results = client.hybrid_search(
    #     index: 'docs',
    #     vector: embedding,
    #     text: 'ruby programming',
    #     alpha: 0.7  # 70% semantic, 30% keyword
    #   )
    #
    # @example Pure semantic (alpha = 1.0)
    #   results = client.hybrid_search(
    #     index: 'docs',
    #     vector: embedding,
    #     text: 'ruby',
    #     alpha: 1.0
    #   )
    #
    # @example Pure keyword (alpha = 0.0)
    #   results = client.hybrid_search(
    #     index: 'docs',
    #     vector: embedding,
    #     text: 'ruby programming',
    #     alpha: 0.0
    #   )
    #
    def hybrid_search(index:, vector:, text:, alpha: 0.5, top_k: 10, namespace: nil,
                      filter: nil, include_values: false, include_metadata: true)
      validate_index!(index)
      validate_query_vector!(vector)
      raise ValidationError, "Text query cannot be nil or empty" if text.nil? || text.empty?
      raise ValidationError, "Alpha must be between 0.0 and 1.0" unless (0.0..1.0).include?(alpha)

      unless provider.respond_to?(:hybrid_search)
        raise UnsupportedFeatureError,
              "Hybrid search is not supported by #{provider_name} provider"
      end

      provider.hybrid_search(
        index: index,
        vector: vector,
        text: text,
        alpha: alpha,
        top_k: top_k,
        namespace: namespace,
        filter: filter,
        include_values: include_values,
        include_metadata: include_metadata
      )
    end

    # Get the provider name
    #
    # @return [Symbol]
    def provider_name
      provider.provider_name
    end

    # Quick health check - tests if provider connection is healthy
    #
    # @param timeout [Float] timeout in seconds (default: 5)
    # @return [Boolean] true if connection is healthy
    #
    # @example
    #   if client.healthy?
    #     client.upsert(...)
    #   else
    #     handle_unhealthy_connection
    #   end
    def healthy?
      start = Time.now
      provider.list_indexes
      true
    rescue StandardError => e
      log_error("Health check failed", e)
      false
    ensure
      duration = ((Time.now - start) * 1000).round(2) if defined?(start)
      log_debug("Health check completed in #{duration}ms") if duration
    end

    # Ping provider and get connection health status with latency
    #
    # @param timeout [Float] timeout in seconds (default: 5)
    # @return [Hash] health status with :healthy, :provider, :latency_ms
    #
    # @example
    #   status = client.ping
    #   puts "Provider: #{status[:provider]}, Healthy: #{status[:healthy]}, Latency: #{status[:latency_ms]}ms"
    def ping
      start = Time.now
      healthy = true
      error_info = nil

      begin
        provider.list_indexes
      rescue StandardError => e
        healthy = false
        error_info = { error: e.class.name, error_message: e.message }
        log_error("Health check failed", e)
      end

      duration = ((Time.now - start) * 1000).round(2)

      result = {
        healthy: healthy,
        provider: provider_name,
        latency_ms: duration
      }

      result.merge!(error_info) if error_info
      result
    end

    # Chainable query builder
    #
    # @api public
    # @example
    #   results = client.query("docs")
    #     .vector(embedding)
    #     .top_k(20)
    #     .namespace("prod")
    #     .filter(category: "ruby")
    #     .with_metadata
    #     .execute
    #
    class QueryBuilder
      def initialize(client, index)
        @client = client
        @index = index
        @vector = nil
        @top_k = 10
        @namespace = nil
        @filter = nil
        @include_values = false
        @include_metadata = true
      end

      attr_reader :index

      def vector(value)
        @vector = value
        self
      end

      def top_k(value)
        @top_k = value.to_i
        self
      end

      def namespace(value)
        @namespace = value
        self
      end

      def filter(value = nil, **kwargs)
        @filter = value || kwargs
        self
      end

      def with_values
        @include_values = true
        self
      end

      def with_metadata
        @include_metadata = true
        self
      end

      def without_metadata
        @include_metadata = false
        self
      end

      # Execute the built query and return a QueryResult
      def execute
        @client.query(
          index: @index,
          vector: @vector,
          top_k: @top_k,
          namespace: @namespace,
          filter: @filter,
          include_values: @include_values,
          include_metadata: @include_metadata
        )
      end
    end

    private

    def build_config(provider_name, api_key, environment, host, options)
      # Start with global config or new config
      cfg = Vectra.configuration.dup

      # Override with provided values
      cfg.provider = provider_name if provider_name
      cfg.api_key = api_key if api_key
      cfg.environment = environment if environment
      cfg.host = host if host
      cfg.timeout = options[:timeout] if options[:timeout]
      cfg.open_timeout = options[:open_timeout] if options[:open_timeout]
      cfg.max_retries = options[:max_retries] if options[:max_retries]
      cfg.retry_delay = options[:retry_delay] if options[:retry_delay]
      cfg.logger = options[:logger] if options[:logger]

      cfg
    end

    def build_provider
      case config.provider
      when :pinecone
        Providers::Pinecone.new(config)
      when :qdrant
        Providers::Qdrant.new(config)
      when :weaviate
        Providers::Weaviate.new(config)
      when :pgvector
        Providers::Pgvector.new(config)
      when :memory
        Providers::Memory.new(config)
      else
        raise UnsupportedProviderError, "Provider '#{config.provider}' is not supported"
      end
    end

    def validate_index!(index)
      raise ValidationError, "Index name cannot be nil" if index.nil?
      raise ValidationError, "Index name must be a string" unless index.is_a?(String)
      raise ValidationError, "Index name cannot be empty" if index.empty?
    end

    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def validate_vectors!(vectors)
      raise ValidationError, "Vectors cannot be nil" if vectors.nil?
      raise ValidationError, "Vectors must be an array" unless vectors.is_a?(Array)
      raise ValidationError, "Vectors cannot be empty" if vectors.empty?

      # Check dimension consistency
      first_vector = vectors.first
      first_values = first_vector.is_a?(Vector) ? first_vector.values : first_vector[:values]
      first_dim = first_values&.size

      return unless first_dim

      vectors.each_with_index do |vec, index|
        values = vec.is_a?(Vector) ? vec.values : vec[:values]
        dim = values&.size

        next unless dim && dim != first_dim

        raise ValidationError,
              "Inconsistent vector dimensions at index #{index}: " \
              "expected #{first_dim}, got #{dim}. " \
              "All vectors in a batch must have the same dimension."
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def validate_query_vector!(vector)
      raise ValidationError, "Query vector cannot be nil" if vector.nil?
      raise ValidationError, "Query vector must be an array" unless vector.is_a?(Array)
      raise ValidationError, "Query vector cannot be empty" if vector.empty?
    end

    def validate_ids!(ids)
      raise ValidationError, "IDs cannot be nil" if ids.nil?
      raise ValidationError, "IDs must be an array" unless ids.is_a?(Array)
      raise ValidationError, "IDs cannot be empty" if ids.empty?
    end

    def validate_id!(id)
      raise ValidationError, "ID cannot be nil" if id.nil?
      raise ValidationError, "ID must be a string" unless id.is_a?(String)
      raise ValidationError, "ID cannot be empty" if id.empty?
    end

    def log_error(message, error = nil)
      return unless config.logger

      config.logger.error("[Vectra] #{message}")
      config.logger.error("[Vectra] #{error.class}: #{error.message}") if error
      config.logger.error("[Vectra] #{error.backtrace&.first(3)&.join("\n")}") if error&.backtrace
    end

    def log_debug(message, data = nil)
      return unless config.logger

      config.logger.debug("[Vectra] #{message}")
      config.logger.debug("[Vectra] #{data.inspect}") if data
    end
  end
end
