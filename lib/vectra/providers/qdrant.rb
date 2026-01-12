# frozen_string_literal: true

module Vectra
  module Providers
    # Qdrant vector database provider
    #
    # Qdrant is an open-source vector similarity search engine with extended filtering support.
    #
    # @example Basic usage
    #   Vectra.configure do |config|
    #     config.provider = :qdrant
    #     config.api_key = ENV['QDRANT_API_KEY']
    #     config.host = 'https://your-cluster.qdrant.io'
    #   end
    #
    #   client = Vectra::Client.new
    #   client.upsert(index: 'my-collection', vectors: [...])
    #
    # rubocop:disable Metrics/ClassLength
    class Qdrant < Base
      # @see Base#provider_name
      def provider_name
        :qdrant
      end

      # @see Base#upsert
      def upsert(index:, vectors:, namespace: nil)
        normalized = normalize_vectors(vectors)

        points = normalized.map do |vec|
          point = {
            id: generate_point_id(vec[:id]),
            vector: vec[:values]
          }

          payload = vec[:metadata] || {}
          payload["_namespace"] = namespace if namespace
          point[:payload] = payload unless payload.empty?

          point
        end

        body = {
          points: points
        }

        response = with_error_handling { connection.put("/collections/#{index}/points", body) }

        if response.success?
          log_debug("Upserted #{normalized.size} vectors to #{index}")
          { upserted_count: normalized.size }
        else
          handle_error(response)
        end
      end

      # @see Base#query
      def query(index:, vector:, top_k: 10, namespace: nil, filter: nil,
                include_values: false, include_metadata: true)
        body = {
          vector: vector.map(&:to_f),
          limit: top_k,
          with_vector: include_values,
          with_payload: include_metadata
        }

        # Build filter with namespace if provided
        qdrant_filter = build_filter(filter, namespace)
        body[:filter] = qdrant_filter if qdrant_filter

        response = with_error_handling { connection.post("/collections/#{index}/points/search", body) }

        if response.success?
          matches = transform_search_results(response.body["result"] || [])
          log_debug("Query returned #{matches.size} results")

          QueryResult.from_response(
            matches: matches,
            namespace: namespace
          )
        else
          handle_error(response)
        end
      end

      # Hybrid search combining vector and text search
      #
      # Uses Qdrant's prefetch + rescore API for efficient hybrid search
      #
      # @param index [String] collection name
      # @param vector [Array<Float>] query vector
      # @param text [String] text query for keyword search
      # @param alpha [Float] balance (0.0 = keyword, 1.0 = vector)
      # @param top_k [Integer] number of results
      # @param namespace [String, nil] optional namespace
      # @param filter [Hash, nil] metadata filter
      # @param include_values [Boolean] include vector values
      # @param include_metadata [Boolean] include metadata
      # @return [QueryResult] search results
      def hybrid_search(index:, vector:, text:, alpha:, top_k:, namespace: nil,
                        filter: nil, include_values: false, include_metadata: true)
        qdrant_filter = build_filter(filter, namespace)
        body = build_hybrid_search_body(vector, text, alpha, top_k, qdrant_filter,
                                        include_values, include_metadata)

        response = with_error_handling do
          connection.post("/collections/#{index}/points/query", body)
        end

        handle_hybrid_search_response(response, alpha, namespace)
      end

      # @see Base#fetch
      def fetch(index:, ids:, namespace: nil) # rubocop:disable Lint/UnusedMethodArgument
        point_ids = ids.map { |id| generate_point_id(id) }

        body = {
          ids: point_ids,
          with_vector: true,
          with_payload: true
        }

        response = with_error_handling { connection.post("/collections/#{index}/points", body) }

        if response.success?
          vectors = {}
          (response.body["result"] || []).each do |point|
            original_id = extract_original_id(point["id"])
            vectors[original_id] = Vector.new(
              id: original_id,
              values: point["vector"],
              metadata: clean_payload(point["payload"])
            )
          end
          vectors
        else
          handle_error(response)
        end
      end

      # @see Base#update
      def update(index:, id:, metadata: nil, values: nil, namespace: nil)
        point_id = generate_point_id(id)

        # Update payload (metadata) if provided
        if metadata
          payload = metadata.dup
          payload["_namespace"] = namespace if namespace

          payload_body = {
            points: [point_id],
            payload: payload
          }

          response = with_error_handling { connection.post("/collections/#{index}/points/payload", payload_body) }
          handle_error(response) unless response.success?
        end

        # Update vector if provided
        if values
          vector_body = {
            points: [
              {
                id: point_id,
                vector: values.map(&:to_f)
              }
            ]
          }

          response = with_error_handling { connection.put("/collections/#{index}/points", vector_body) }
          handle_error(response) unless response.success?
        end

        log_debug("Updated vector #{id}")
        { updated: true }
      end

      # @see Base#delete
      def delete(index:, ids: nil, namespace: nil, filter: nil, delete_all: false)
        if delete_all
          # Delete all points in collection
          body = { filter: {} }
        elsif ids
          # Delete by IDs
          point_ids = ids.map { |id| generate_point_id(id) }
          body = { points: point_ids }
        elsif filter || namespace
          # Delete by filter
          body = { filter: build_filter(filter, namespace) }
        else
          raise ValidationError, "Must specify ids, filter, or delete_all"
        end

        response = with_error_handling { connection.post("/collections/#{index}/points/delete", body) }

        if response.success?
          log_debug("Deleted vectors from #{index}")
          { deleted: true }
        else
          handle_error(response)
        end
      end

      # @see Base#list_indexes
      def list_indexes
        response = with_error_handling { connection.get("/collections") }

        if response.success?
          (response.body["result"]&.dig("collections") || []).map do |col|
            # Get collection info for each
            info = describe_index(index: col["name"])
            info
          rescue StandardError
            { name: col["name"], status: "unknown" }
          end
        else
          handle_error(response)
        end
      end

      # @see Base#describe_index
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def describe_index(index:)
        response = with_error_handling { connection.get("/collections/#{index}") }

        if response.success?
          result = response.body["result"]
          config = result["config"]
          params = config&.dig("params") || {}
          vectors_config = params["vectors"] || {}

          # Handle both named and unnamed vector configs
          dimension = if vectors_config.is_a?(Hash) && vectors_config["size"]
                        vectors_config["size"]
                      elsif vectors_config.is_a?(Hash)
                        vectors_config.values.first&.dig("size")
                      end

          distance = vectors_config["distance"] || vectors_config.values.first&.dig("distance")

          {
            name: index,
            dimension: dimension,
            metric: distance_to_metric(distance),
            status: result["status"],
            vectors_count: result["vectors_count"],
            points_count: result["points_count"]
          }
        else
          handle_error(response)
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # @see Base#stats
      def stats(index:, namespace: nil)
        info = describe_index(index: index)

        {
          total_vector_count: info[:points_count] || info[:vectors_count] || 0,
          dimension: info[:dimension],
          status: info[:status],
          namespaces: namespace ? { namespace => { vector_count: 0 } } : {}
        }
      end

      # Create a new collection
      #
      # @param name [String] collection name
      # @param dimension [Integer] vector dimension
      # @param metric [String] similarity metric (cosine, euclidean, dot_product)
      # @param on_disk [Boolean] store vectors on disk
      # @return [Hash] created collection info
      def create_index(name:, dimension:, metric: "cosine", on_disk: false)
        body = {
          vectors: {
            size: dimension,
            distance: metric_to_distance(metric),
            on_disk: on_disk
          }
        }

        response = with_error_handling { connection.put("/collections/#{name}", body) }

        if response.success?
          log_debug("Created collection #{name}")
          describe_index(index: name)
        else
          handle_error(response)
        end
      end

      # Delete a collection
      #
      # @param name [String] collection name
      # @return [Hash] deletion result
      def delete_index(name:)
        response = with_error_handling { connection.delete("/collections/#{name}") }

        if response.success?
          log_debug("Deleted collection #{name}")
          { deleted: true }
        else
          handle_error(response)
        end
      end

      private

      def build_hybrid_search_body(vector, text, alpha, top_k, filter, include_values, include_metadata)
        body = {
          prefetch: {
            query: { text: text },
            limit: top_k * 2
          },
          query: { vector: vector.map(&:to_f) },
          limit: top_k,
          params: { alpha: alpha },
          with_vector: include_values,
          with_payload: include_metadata
        }

        body[:prefetch][:filter] = filter if filter
        body[:query][:filter] = filter if filter
        body
      end

      def handle_hybrid_search_response(response, alpha, namespace)
        if response.success?
          matches = transform_search_results(response.body["result"] || [])
          log_debug("Hybrid search returned #{matches.size} results (alpha: #{alpha})")

          QueryResult.from_response(
            matches: matches,
            namespace: namespace
          )
        else
          handle_error(response)
        end
      end

      def validate_config!
        super
        raise ConfigurationError, "Host must be configured for Qdrant" if config.host.nil? || config.host.empty?
      end

      def connection
        @connection ||= build_connection(
          config.host,
          auth_headers
        )
      end

      # Wrap HTTP calls to handle Faraday::RetriableResponse
      def with_error_handling
        yield
      rescue Faraday::RetriableResponse => e
        handle_retriable_response(e)
      end

      # Extract error message from Qdrant response format
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def extract_error_message(body)
        case body
        when Hash
          # Qdrant wraps errors in "status" key
          status = body["status"] || body
          msg = status["error"] || body["message"] || body["error_message"] || body.to_s

          # Add details
          details = status["details"] || status["error_details"]
          if details
            details_str = details.is_a?(Hash) ? details.to_json : details.to_s
            msg += " (#{details_str})" unless msg.include?(details_str)
          end

          # Add field-specific errors
          if status["errors"].is_a?(Array)
            field_errors = status["errors"].map { |e| e.is_a?(Hash) ? e["field"] || e["message"] : e }.join(", ")
            msg += " [Fields: #{field_errors}]" if field_errors && !msg.include?(field_errors)
          end

          msg
        when String
          body
        else
          "Unknown error"
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def auth_headers
        headers = {}
        headers["api-key"] = config.api_key if config.api_key && !config.api_key.empty?
        headers
      end

      # Generate a Qdrant point ID from string ID
      # Qdrant supports both integer and UUID point IDs
      # We use a hash to convert arbitrary strings to integers
      def generate_point_id(id)
        # If it's already a valid integer or UUID, use it
        return id.to_i if id.to_s.match?(/^\d+$/)
        return id if uuid?(id)

        # Otherwise, store original ID in payload and use hash
        id.to_s.hash.abs
      end

      def uuid?(str)
        str.to_s.match?(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
      end

      def extract_original_id(point_id)
        point_id.to_s
      end

      # Build Qdrant filter from Vectra filter and namespace
      def build_filter(filter, namespace)
        conditions = []

        # Add namespace filter
        if namespace
          conditions << {
            key: "_namespace",
            match: { value: namespace }
          }
        end

        # Add metadata filters
        if filter.is_a?(Hash)
          filter.each do |key, value|
            conditions << build_condition(key.to_s, value)
          end
        end

        return nil if conditions.empty?

        { must: conditions }
      end

      def build_condition(key, value)
        case value
        when Hash
          # Handle operators like { "$gt" => 5 }
          build_operator_condition(key, value)
        when Array
          # IN operator
          { key: key, match: { any: value } }
        else
          # Exact match
          { key: key, match: { value: value } }
        end
      end

      def build_operator_condition(key, operator_hash)
        operator, val = operator_hash.first

        case operator.to_s
        when "$ne"
          { key: key, match: { except: [val] } }
        when "$gt"
          { key: key, range: { gt: val } }
        when "$gte"
          { key: key, range: { gte: val } }
        when "$lt"
          { key: key, range: { lt: val } }
        when "$lte"
          { key: key, range: { lte: val } }
        when "$in"
          { key: key, match: { any: val } }
        when "$nin"
          { key: key, match: { except: val } }
        else # $eq or unknown operator - exact match
          { key: key, match: { value: val } }
        end
      end

      def transform_search_results(results)
        results.map do |result|
          {
            id: extract_original_id(result["id"]),
            score: result["score"],
            values: result["vector"],
            metadata: clean_payload(result["payload"])
          }
        end
      end

      # Remove internal fields from payload
      def clean_payload(payload)
        return {} unless payload

        payload.reject { |k, _| k.to_s.start_with?("_") }
      end

      # Convert Vectra metric to Qdrant distance
      def metric_to_distance(metric)
        case metric.to_s.downcase
        when "euclidean", "l2"
          "Euclid"
        when "dot_product", "dotproduct", "inner_product"
          "Dot"
        else # cosine or unknown - default to Cosine
          "Cosine"
        end
      end

      # Convert Qdrant distance to Vectra metric
      def distance_to_metric(distance)
        case distance.to_s
        when "Cosine"
          "cosine"
        when "Euclid"
          "euclidean"
        when "Dot"
          "dot_product"
        else
          distance.to_s.downcase
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
