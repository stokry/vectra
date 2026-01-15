# frozen_string_literal: true

module Vectra
  module Providers
    # In-memory vector database provider for testing
    #
    # This provider stores all vectors in memory using Ruby hashes.
    # Perfect for testing without external dependencies.
    #
    # @example Usage in tests
    #   Vectra.configure do |config|
    #     config.provider = :memory if Rails.env.test?
    #   end
    #
    #   client = Vectra::Client.new
    #   client.upsert(index: 'test', vectors: [...])
    #
    class Memory < Base
      def initialize(config)
        super
        # Storage structure: @storage[index][namespace][id] = Vector
        @storage = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }
        @index_configs = {} # Store index configurations (dimension, metric)
      end

      # @see Base#provider_name
      def provider_name
        :memory
      end

      # @see Base#upsert
      def upsert(index:, vectors:, namespace: nil)
        normalized = normalize_vectors(vectors)
        ns = namespace || ""

        normalized.each do |vec|
          # Infer dimension from first vector if not set
          if @index_configs[index].nil?
            @index_configs[index] = {
              dimension: vec[:values].length,
              metric: "cosine"
            }
          end

          # Store vector
          vector_obj = Vector.new(
            id: vec[:id],
            values: vec[:values],
            metadata: vec[:metadata] || {}
          )
          @storage[index][ns][vec[:id]] = vector_obj
        end

        log_debug("Upserted #{normalized.size} vectors to #{index}")
        { upserted_count: normalized.size }
      end

      # @see Base#query
      def query(index:, vector:, top_k: 10, namespace: nil, filter: nil,
                include_values: false, include_metadata: true)
        ns = namespace || ""
        candidates = @storage[index][ns].values

        # Apply metadata filter
        if filter
          candidates = candidates.select { |v| matches_filter?(v, filter) }
        end

        # Calculate similarity scores
        matches = candidates.map do |vec|
          score = calculate_similarity(vector, vec.values, index)
          build_match(vec, score, include_values, include_metadata)
        end

        # Sort by score (descending) and take top_k
        matches.sort_by! { |m| -m[:score] }
        matches = matches.first(top_k)

        log_debug("Query returned #{matches.size} results")
        QueryResult.from_response(matches: matches, namespace: namespace)
      end

      # Text-only search using simple keyword matching in metadata
      #
      # For testing purposes only. Performs case-insensitive keyword matching
      # in metadata values. Not a real BM25/full-text search implementation.
      #
      # @param index [String] index name
      # @param text [String] text query for keyword search
      # @param top_k [Integer] number of results
      # @param namespace [String, nil] optional namespace
      # @param filter [Hash, nil] metadata filter
      # @param include_values [Boolean] include vector values
      # @param include_metadata [Boolean] include metadata
      # @return [QueryResult] search results
      def text_search(index:, text:, top_k:, namespace: nil, filter: nil,
                      include_values: false, include_metadata: true)
        ns = namespace || ""
        candidates = @storage[index][ns].values

        # Apply metadata filter first
        if filter
          candidates = candidates.select { |v| matches_filter?(v, filter) }
        end

        # Simple keyword matching in metadata values (case-insensitive)
        text_lower = text.to_s.downcase
        matches = candidates.map do |vec|
          # Search in all metadata values
          metadata_text = (vec.metadata || {}).values.map(&:to_s).join(" ").downcase
          matches_text = metadata_text.include?(text_lower)

          next unless matches_text

          # Simple scoring: count how many words match
          query_words = text_lower.split(/\s+/)
          matched_words = query_words.count { |word| metadata_text.include?(word) }
          score = matched_words.to_f / query_words.size

          build_match(vec, score, include_values, include_metadata)
        end.compact

        # Sort by score (descending) and take top_k
        matches.sort_by! { |m| -m[:score] }
        matches = matches.first(top_k)

        log_debug("Text search returned #{matches.size} results")
        QueryResult.from_response(matches: matches, namespace: namespace)
      end

      # @see Base#fetch
      def fetch(index:, ids:, namespace: nil)
        ns = namespace || ""
        vectors = {}

        ids.each do |id|
          vec = @storage[index][ns][id]
          vectors[id] = vec if vec
        end

        vectors
      end

      # @see Base#update
      def update(index:, id:, metadata:, namespace: nil)
        ns = namespace || ""
        vec = @storage[index][ns][id]

        raise NotFoundError, "Vector '#{id}' not found in index '#{index}'" unless vec

        # Merge metadata
        new_metadata = (vec.metadata || {}).merge(metadata.transform_keys(&:to_s))
        updated_vec = Vector.new(
          id: vec.id,
          values: vec.values,
          metadata: new_metadata,
          sparse_values: vec.sparse_values
        )
        @storage[index][ns][id] = updated_vec

        log_debug("Updated vector #{id}")
        { updated: true }
      end

      # @see Base#delete
      def delete(index:, ids: nil, namespace: nil, filter: nil, delete_all: false)
        ns = namespace || ""

        if delete_all
          @storage[index].clear
        elsif ids
          ids.each { |id| @storage[index][ns].delete(id) }
        elsif namespace && !filter
          @storage[index].delete(ns)
        elsif filter
          # Delete vectors matching filter
          @storage[index][ns].delete_if { |_id, vec| matches_filter?(vec, filter) }
        else
          raise ValidationError, "Must specify ids, filter, namespace, or delete_all"
        end

        log_debug("Deleted vectors from #{index}")
        { deleted: true }
      end

      # @see Base#list_indexes
      def list_indexes
        @index_configs.keys.map { |name| describe_index(index: name) }
      end

      # @see Base#describe_index
      def describe_index(index:)
        config = @index_configs[index]
        raise NotFoundError, "Index '#{index}' not found" unless config

        {
          name: index,
          dimension: config[:dimension],
          metric: config[:metric],
          status: "ready"
        }
      end

      # @see Base#stats
      def stats(index:, namespace: nil)
        config = @index_configs[index]
        raise NotFoundError, "Index '#{index}' not found" unless config

        if namespace
          ns = namespace
          count = @storage[index][ns].size
          namespaces = { ns => { vector_count: count } }
        else
          # Count all namespaces
          namespaces = {}
          @storage[index].each do |ns, vectors|
            namespaces[ns] = { vector_count: vectors.size }
          end
          count = @storage[index].values.sum(&:size)
        end

        {
          total_vector_count: count,
          dimension: config[:dimension],
          namespaces: namespaces
        }
      end

      # Clear all stored data (useful for tests)
      #
      # @return [void]
      def clear!
        @storage.clear
        @index_configs.clear
      end

      private

      # Calculate similarity score based on index metric
      def calculate_similarity(query_vector, candidate_vector, index)
        config = @index_configs[index] || { metric: "cosine" }
        metric = config[:metric] || "cosine"

        case metric.to_s.downcase
        when "euclidean", "l2"
          # Convert distance to similarity (1 / (1 + distance))
          distance = euclidean_distance(query_vector, candidate_vector)
          1.0 / (1.0 + distance)
        when "dot_product", "inner_product", "dot"
          dot_product(query_vector, candidate_vector)
        else # cosine (default)
          cosine_similarity(query_vector, candidate_vector)
        end
      end

      # Calculate cosine similarity
      def cosine_similarity(vec_a, vec_b)
        raise ArgumentError, "Vectors must have same dimension" if vec_a.length != vec_b.length

        dot = vec_a.zip(vec_b).sum { |a, b| a * b }
        mag_a = Math.sqrt(vec_a.sum { |v| v**2 })
        mag_b = Math.sqrt(vec_b.sum { |v| v**2 })

        return 0.0 if mag_a.zero? || mag_b.zero?

        dot / (mag_a * mag_b)
      end

      # Calculate Euclidean distance
      def euclidean_distance(vec_a, vec_b)
        raise ArgumentError, "Vectors must have same dimension" if vec_a.length != vec_b.length

        Math.sqrt(vec_a.zip(vec_b).sum { |a, b| (a - b)**2 })
      end

      # Calculate dot product
      def dot_product(vec_a, vec_b)
        raise ArgumentError, "Vectors must have same dimension" if vec_a.length != vec_b.length

        vec_a.zip(vec_b).sum { |a, b| a * b }
      end

      # Check if vector matches filter
      def matches_filter?(vector, filter)
        filter.all? do |key, value|
          vec_value = vector.metadata[key.to_s]
          matches_filter_value?(vec_value, value)
        end
      end

      # Check if a value matches filter criteria
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def matches_filter_value?(actual, expected)
        case expected
        when Hash
          # Support operators like { "$gt" => 5, "$lt" => 10 }
          expected.all? do |op, val|
            case op.to_s
            when "$eq"
              actual == val
            when "$ne"
              actual != val
            when "$gt"
              actual.is_a?(Numeric) && val.is_a?(Numeric) && actual > val
            when "$gte"
              actual.is_a?(Numeric) && val.is_a?(Numeric) && actual >= val
            when "$lt"
              actual.is_a?(Numeric) && val.is_a?(Numeric) && actual < val
            when "$lte"
              actual.is_a?(Numeric) && val.is_a?(Numeric) && actual <= val
            when "$in"
              val.is_a?(Array) && val.include?(actual)
            else
              actual == expected
            end
          end
        when Array
          expected.include?(actual)
        else
          actual == expected
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Build match hash from vector
      def build_match(vector, score, include_values, include_metadata)
        match = {
          id: vector.id,
          score: score
        }
        match[:values] = vector.values if include_values
        match[:metadata] = vector.metadata if include_metadata
        match[:sparse_values] = vector.sparse_values if vector.sparse?
        match
      end

      # Override validate_config! - Memory provider doesn't need host or API key
      # rubocop:disable Naming/PredicateMethod
      def validate_config!
        # Memory provider has no special requirements
        true
      end
      # rubocop:enable Naming/PredicateMethod
    end
  end
end
