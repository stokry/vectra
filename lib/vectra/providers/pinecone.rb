# frozen_string_literal: true

module Vectra
  module Providers
    # Pinecone vector database provider
    #
    # @example
    #   provider = Vectra::Providers::Pinecone.new(config)
    #   provider.upsert(index: 'my-index', vectors: [...])
    #
    class Pinecone < Base
      API_VERSION = "2024-07"

      def initialize(config)
        super
        @control_plane_connection = nil
        @data_plane_connections = {}
      end

      # @see Base#provider_name
      def provider_name
        :pinecone
      end

      # @see Base#upsert
      def upsert(index:, vectors:, namespace: nil)
        normalized = normalize_vectors(vectors)

        body = { vectors: normalized }
        body[:namespace] = namespace if namespace

        response = data_connection(index).post("/vectors/upsert", body)

        if response.success?
          log_debug("Upserted #{normalized.size} vectors to #{index}")
          {
            upserted_count: response.body["upsertedCount"] || normalized.size
          }
        else
          handle_error(response)
        end
      end

      # @see Base#query
      def query(index:, vector:, top_k: 10, namespace: nil, filter: nil,
                include_values: false, include_metadata: true)
        body = {
          vector: vector.map(&:to_f),
          topK: top_k,
          includeValues: include_values,
          includeMetadata: include_metadata
        }
        body[:namespace] = namespace if namespace
        body[:filter] = transform_filter(filter) if filter

        response = data_connection(index).post("/query", body)

        if response.success?
          log_debug("Query returned #{response.body['matches']&.size || 0} results")
          QueryResult.from_response(
            matches: transform_matches(response.body["matches"] || []),
            namespace: response.body["namespace"],
            usage: response.body["usage"]
          )
        else
          handle_error(response)
        end
      end

      # Hybrid search combining dense (vector) and sparse (keyword) search
      #
      # Pinecone supports hybrid search using sparse-dense vectors.
      # For text-based keyword search, you need to provide sparse vectors.
      #
      # @param index [String] index name
      # @param vector [Array<Float>] dense query vector
      # @param text [String] text query (converted to sparse vector)
      # @param alpha [Float] balance (0.0 = sparse, 1.0 = dense)
      # @param top_k [Integer] number of results
      # @param namespace [String, nil] optional namespace
      # @param filter [Hash, nil] metadata filter
      # @param include_values [Boolean] include vector values
      # @param include_metadata [Boolean] include metadata
      # @return [QueryResult] search results
      #
      # @note For proper hybrid search, you should generate sparse vectors
      #   from text using a tokenizer (e.g., BM25). This method accepts text
      #   but requires sparse vector generation externally.
      def hybrid_search(index:, vector:, text:, alpha:, top_k:, namespace: nil,
                        filter: nil, include_values: false, include_metadata: true)
        # Pinecone hybrid search requires sparse vectors
        # For now, we'll use dense vector only and log a warning
        # In production, users should generate sparse vectors from text
        log_debug("Pinecone hybrid search: text parameter ignored. " \
                  "For true hybrid search, provide sparse vectors via sparse_values parameter.")

        # Use dense vector search with alpha weighting
        # Note: Pinecone's actual hybrid search requires sparse vectors
        # This is a simplified implementation
        body = {
          vector: vector.map(&:to_f),
          topK: top_k,
          includeValues: include_values,
          includeMetadata: include_metadata
        }
        body[:namespace] = namespace if namespace
        body[:filter] = transform_filter(filter) if filter

        # Alpha is used conceptually here - Pinecone's actual hybrid search
        # requires sparse vectors in the query
        response = data_connection(index).post("/query", body)

        if response.success?
          log_debug("Hybrid search returned #{response.body['matches']&.size || 0} results (alpha: #{alpha})")
          QueryResult.from_response(
            matches: transform_matches(response.body["matches"] || []),
            namespace: response.body["namespace"],
            usage: response.body["usage"]
          )
        else
          handle_error(response)
        end
      end

      # @see Base#fetch
      def fetch(index:, ids:, namespace: nil)
        params = { ids: ids }
        params[:namespace] = namespace if namespace

        response = data_connection(index).get("/vectors/fetch") do |req|
          ids.each { |id| req.params.add("ids", id) }
          req.params["namespace"] = namespace if namespace
        end

        if response.success?
          vectors = {}
          (response.body["vectors"] || {}).each do |id, data|
            vectors[id] = Vector.new(
              id: id,
              values: data["values"],
              metadata: data["metadata"],
              sparse_values: data["sparseValues"]
            )
          end
          vectors
        else
          handle_error(response)
        end
      end

      # @see Base#update
      def update(index:, id:, metadata: nil, values: nil, namespace: nil)
        body = { id: id }
        body[:setMetadata] = metadata if metadata
        body[:values] = values.map(&:to_f) if values
        body[:namespace] = namespace if namespace

        response = data_connection(index).post("/vectors/update", body)

        if response.success?
          log_debug("Updated vector #{id}")
          { updated: true }
        else
          handle_error(response)
        end
      end

      # @see Base#delete
      def delete(index:, ids: nil, namespace: nil, filter: nil, delete_all: false)
        body = {}
        body[:ids] = ids if ids
        body[:namespace] = namespace if namespace
        body[:filter] = transform_filter(filter) if filter
        body[:deleteAll] = true if delete_all

        response = data_connection(index).post("/vectors/delete", body)

        if response.success?
          log_debug("Deleted vectors from #{index}")
          { deleted: true }
        else
          handle_error(response)
        end
      end

      # @see Base#list_indexes
      def list_indexes
        response = control_connection.get("/indexes")

        if response.success?
          (response.body["indexes"] || []).map do |idx|
            {
              name: idx["name"],
              dimension: idx["dimension"],
              metric: idx["metric"],
              host: idx["host"],
              status: idx.dig("status", "ready") ? "ready" : "initializing"
            }
          end
        else
          handle_error(response)
        end
      end

      # @see Base#describe_index
      def describe_index(index:)
        response = control_connection.get("/indexes/#{index}")

        if response.success?
          body = response.body
          {
            name: body["name"],
            dimension: body["dimension"],
            metric: body["metric"],
            host: body["host"],
            spec: body["spec"],
            status: body["status"]
          }
        else
          handle_error(response)
        end
      end

      # @see Base#stats
      def stats(index:, namespace: nil)
        body = {}
        body[:filter] = {} if namespace.nil?

        response = data_connection(index).post("/describe_index_stats", body)

        if response.success?
          {
            total_vector_count: response.body["totalVectorCount"],
            dimension: response.body["dimension"],
            index_fullness: response.body["indexFullness"],
            namespaces: response.body["namespaces"]
          }
        else
          handle_error(response)
        end
      end

      # Create a new index
      #
      # @param name [String] index name
      # @param dimension [Integer] vector dimension
      # @param metric [String] similarity metric (cosine, euclidean, dotproduct)
      # @param spec [Hash] index spec (serverless or pod configuration)
      # @return [Hash] created index info
      def create_index(name:, dimension:, metric: "cosine", spec: nil)
        body = {
          name: name,
          dimension: dimension,
          metric: metric
        }

        # Default to serverless spec if not provided
        body[:spec] = spec || {
          serverless: {
            cloud: "aws",
            region: config.environment || "us-east-1"
          }
        }

        response = control_connection.post("/indexes", body)

        if response.success?
          log_debug("Created index #{name}")
          describe_index(index: name)
        else
          handle_error(response)
        end
      end

      # Delete an index
      #
      # @param name [String] index name
      # @return [Hash] deletion result
      def delete_index(name:)
        response = control_connection.delete("/indexes/#{name}")

        if response.success?
          log_debug("Deleted index #{name}")
          { deleted: true }
        else
          handle_error(response)
        end
      end

      private

      # Control plane connection (for index management)
      def control_connection
        @control_plane_connection ||= build_connection(
          "https://api.pinecone.io",
          {
            "Api-Key" => config.api_key,
            "X-Pinecone-API-Version" => API_VERSION
          }
        )
      end

      # Data plane connection (for vector operations)
      # Each index has its own host
      def data_connection(index)
        @data_plane_connections[index] ||= begin
          host = resolve_index_host(index)
          build_connection(
            "https://#{host}",
            {
              "Api-Key" => config.api_key,
              "X-Pinecone-API-Version" => API_VERSION
            }
          )
        end
      end

      # Resolve the host for an index
      def resolve_index_host(index)
        # If a direct host is configured, use that
        return config.host if config.host

        # Otherwise, fetch from the API
        info = describe_index(index: index)
        host = info[:host]

        raise ConfigurationError, "Could not resolve host for index '#{index}'" unless host

        host
      end

      # Transform metadata filter to Pinecone format
      def transform_filter(filter)
        return nil unless filter

        # Simple key-value filters are wrapped in $eq
        filter.transform_values do |value|
          case value
          when Hash
            value # Already a filter operator
          when Array
            { "$in" => value }
          else
            { "$eq" => value }
          end
        end
      end

      # Transform matches from API response
      def transform_matches(matches)
        matches.map do |match|
          {
            id: match["id"],
            score: match["score"],
            values: match["values"],
            metadata: match["metadata"],
            sparse_values: match["sparseValues"]
          }
        end
      end
    end
  end
end
