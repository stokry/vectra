# frozen_string_literal: true

# Ensure HealthCheck is loaded before Client
require_relative "health_check" unless defined?(Vectra::HealthCheck)
require_relative "configuration" unless defined?(Vectra::Configuration)

# Ensure Providers are loaded before Client (for Rails autoloading compatibility)
require_relative "providers/base" unless defined?(Vectra::Providers::Base)
require_relative "providers/pinecone" unless defined?(Vectra::Providers::Pinecone)
require_relative "providers/qdrant" unless defined?(Vectra::Providers::Qdrant)
require_relative "providers/weaviate" unless defined?(Vectra::Providers::Weaviate)
require_relative "providers/pgvector" unless defined?(Vectra::Providers::Pgvector)
require_relative "providers/memory" unless defined?(Vectra::Providers::Memory)

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
  # rubocop:disable Metrics/ClassLength
  class Client
    include Vectra::HealthCheck

    attr_reader :config, :provider, :default_index, :default_namespace

    class << self
      # Get the global middleware stack
      #
      # @return [Array<Array>] Array of [middleware_class, options] pairs
      def middleware
        @middleware ||= []
      end

      # Add middleware to the global stack
      #
      # @param middleware_class [Class] Middleware class
      # @param options [Hash] Options to pass to middleware constructor
      #
      # @example Add global logging middleware
      #   Vectra::Client.use Vectra::Middleware::Logging
      #
      # @example Add middleware with options
      #   Vectra::Client.use Vectra::Middleware::Retry, max_attempts: 5
      #
      def use(middleware_class, **options)
        middleware << [middleware_class, options]
      end

      # Clear all global middleware
      #
      # @return [void]
      def clear_middleware!
        @middleware = []
      end
    end

    # Initialize a new Client
    #
    # @param provider [Symbol, nil] provider name (:pinecone, :qdrant, :weaviate)
    # @param api_key [String, nil] API key
    # @param environment [String, nil] environment/region
    # @param host [String, nil] custom host URL
    # @param options [Hash] additional options
    # @option options [String] :index default index name
    # @option options [String] :namespace default namespace
    # @option options [Array<Class, Object>] :middleware instance-level middleware
    def initialize(provider: nil, api_key: nil, environment: nil, host: nil, **options)
      @config = build_config(provider, api_key, environment, host, options)
      @config.validate!
      @provider = build_provider
      @default_index = options[:index]
      @default_namespace = options[:namespace]
      @middleware = build_middleware_stack(options[:middleware])
    end

    # Upsert vectors into an index
    #
    # @param vectors [Array<Hash, Vector>] vectors to upsert
    # @param index [String, nil] the index/collection name (falls back to client's default)
    # @param namespace [String, nil] optional namespace (provider-specific, falls back to client's default)
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
    def upsert(vectors:, index: nil, namespace: nil)
      index ||= default_index
      namespace ||= default_namespace
      validate_index!(index)
      validate_vectors!(vectors)

      Instrumentation.instrument(
        operation: :upsert,
        provider: provider_name,
        index: index,
        metadata: { vector_count: vectors.size }
      ) do
        @middleware.call(:upsert, index: index, vectors: vectors, namespace: namespace, provider: provider_name)
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

      # Fall back to default index/namespace when not provided
      index ||= default_index
      namespace ||= default_namespace

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
        result = @middleware.call(
          :query,
          index: index,
          vector: vector,
          top_k: top_k,
          namespace: namespace,
          filter: filter,
          include_values: include_values,
          include_metadata: include_metadata,
          provider: provider_name
        )
      end

      result
    end

    # Fetch vectors by IDs
    #
    # @param ids [Array<String>] vector IDs to fetch
    # @param index [String, nil] the index/collection name (falls back to client's default)
    # @param namespace [String, nil] optional namespace (falls back to client's default)
    # @return [Hash<String, Vector>] hash of ID to Vector
    #
    # @example Fetch vectors
    #   vectors = client.fetch(index: 'my-index', ids: ['vec1', 'vec2'])
    #   vectors['vec1'].values # => [0.1, 0.2, 0.3]
    #
    def fetch(ids:, index: nil, namespace: nil)
      index ||= default_index
      namespace ||= default_namespace
      validate_index!(index)
      validate_ids!(ids)

      Instrumentation.instrument(
        operation: :fetch,
        provider: provider_name,
        index: index,
        metadata: { id_count: ids.size }
      ) do
        @middleware.call(:fetch, index: index, ids: ids, namespace: namespace, provider: provider_name)
      end
    end

    # Update a vector's metadata or values
    #
    # @param id [String] vector ID
    # @param index [String, nil] the index/collection name (falls back to client's default)
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
    def update(id:, index: nil, metadata: nil, values: nil, namespace: nil)
      index ||= default_index
      namespace ||= default_namespace
      validate_index!(index)
      validate_id!(id)

      raise ValidationError, "Must provide metadata or values to update" if metadata.nil? && values.nil?

      Instrumentation.instrument(
        operation: :update,
        provider: provider_name,
        index: index,
        metadata: { has_metadata: !metadata.nil?, has_values: !values.nil? }
      ) do
        @middleware.call(
          :update,
          index: index,
          id: id,
          metadata: metadata,
          values: values,
          namespace: namespace,
          provider: provider_name
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
    def delete(index: nil, ids: nil, namespace: nil, filter: nil, delete_all: false)
      index ||= default_index
      namespace ||= default_namespace
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
        @middleware.call(
          :delete,
          index: index,
          ids: ids,
          namespace: namespace,
          filter: filter,
          delete_all: delete_all,
          provider: provider_name
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
      @middleware.call(:list_indexes, provider: provider_name)
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
    def describe_index(index: nil)
      index ||= default_index
      validate_index!(index)
      @middleware.call(:describe_index, index: index, provider: provider_name)
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
    def stats(index: nil, namespace: nil)
      index ||= default_index
      namespace ||= default_namespace
      validate_index!(index)
      @middleware.call(:stats, index: index, namespace: namespace, provider: provider_name)
    end

    # Create a new index
    #
    # @param name [String] the index name
    # @param dimension [Integer] vector dimension
    # @param metric [String] distance metric (default: "cosine")
    # @param options [Hash] provider-specific options
    # @return [Hash] index information
    # @raise [NotImplementedError] if provider doesn't support index creation
    #
    # @example
    #   client.create_index(name: 'documents', dimension: 384, metric: 'cosine')
    #
    def create_index(name:, dimension:, metric: "cosine", **options)
      unless provider.respond_to?(:create_index)
        raise NotImplementedError, "Provider #{provider_name} does not support index creation"
      end

      Instrumentation.instrument(
        operation: :create_index,
        provider: provider_name,
        index: name,
        metadata: { dimension: dimension, metric: metric }
      ) do
        @middleware.call(:create_index, name: name, dimension: dimension, metric: metric, provider: provider_name, **options)
      end
    end

    # Delete an index
    #
    # @param name [String] the index name
    # @return [Hash] delete response
    # @raise [NotImplementedError] if provider doesn't support index deletion
    #
    # @example
    #   client.delete_index(name: 'documents')
    #
    def delete_index(name:)
      unless provider.respond_to?(:delete_index)
        raise NotImplementedError, "Provider #{provider_name} does not support index deletion"
      end

      Instrumentation.instrument(
        operation: :delete_index,
        provider: provider_name,
        index: name
      ) do
        @middleware.call(:delete_index, name: name, provider: provider_name)
      end
    end

    # List all namespaces in an index
    #
    # @param index [String] the index name
    # @return [Array<String>] list of namespace names
    #
    # @example
    #   namespaces = client.list_namespaces(index: 'documents')
    #   namespaces.each { |ns| puts "Namespace: #{ns}" }
    #
    def list_namespaces(index: nil)
      index ||= default_index
      validate_index!(index)
      stats_data = provider.stats(index: index)
      namespaces = stats_data[:namespaces] || {}
      namespaces.keys.reject(&:empty?) # Exclude empty/default namespace
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
      index ||= default_index
      namespace ||= default_namespace
      validate_index!(index)
      validate_query_vector!(vector)
      raise ValidationError, "Text query cannot be nil or empty" if text.nil? || text.empty?
      raise ValidationError, "Alpha must be between 0.0 and 1.0" unless (0.0..1.0).include?(alpha)

      unless provider.respond_to?(:hybrid_search)
        raise UnsupportedFeatureError,
              "Hybrid search is not supported by #{provider_name} provider"
      end

      @middleware.call(
        :hybrid_search,
        index: index,
        vector: vector,
        text: text,
        alpha: alpha,
        top_k: top_k,
        namespace: namespace,
        filter: filter,
        include_values: include_values,
        include_metadata: include_metadata,
        provider: provider_name
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
        Vectra::Providers::Pinecone.new(config)
      when :qdrant
        Vectra::Providers::Qdrant.new(config)
      when :weaviate
        Vectra::Providers::Weaviate.new(config)
      when :pgvector
        Vectra::Providers::Pgvector.new(config)
      when :memory
        Vectra::Providers::Memory.new(config)
      else
        raise UnsupportedProviderError, "Provider '#{config.provider}' is not supported"
      end
    end

    def build_middleware_stack(instance_middleware = nil)
      # Combine class-level + instance-level middleware
      all_middleware = self.class.middleware.map do |klass, opts|
        klass.new(**opts)
      end

      if instance_middleware
        all_middleware += Array(instance_middleware).map do |mw|
          mw.is_a?(Class) ? mw.new : mw
        end
      end

      Middleware::Stack.new(@provider, all_middleware)
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

    # Temporarily override default index within a block.
    #
    # @param index [String] temporary index name
    # @yield [Client] yields self with overridden index
    # @return [Object] block result
    def with_index(index)
      previous = @default_index
      @default_index = index
      yield self
    ensure
      @default_index = previous
    end

    # Temporarily override default namespace within a block.
    #
    # @param namespace [String] temporary namespace
    # @yield [Client] yields self with overridden namespace
    # @return [Object] block result
    def with_namespace(namespace)
      previous = @default_namespace
      @default_namespace = namespace
      yield self
    ensure
      @default_namespace = previous
    end

    # Temporarily override both index and namespace within a block.
    #
    # @param index [String] temporary index name
    # @param namespace [String] temporary namespace
    # @yield [Client] yields self with overridden index and namespace
    # @return [Object] block result
    def with_index_and_namespace(index, namespace)
      with_index(index) do
        with_namespace(namespace) do
          yield self
        end
      end
    end

    public :with_index, :with_namespace, :with_index_and_namespace
  end
  # rubocop:enable Metrics/ClassLength
end
