# frozen_string_literal: true

module Vectra
  module Providers
    # Weaviate vector database provider
    #
    # Weaviate is an open-source vector search engine with semantic search
    # capabilities, accessed via a REST and GraphQL API.
    #
    # This implementation focuses on the core CRUD + query surface that matches
    # the Vectra client API. Each Vectra "index" maps to a Weaviate class.
    #
    # @example Basic usage
    #   Vectra.configure do |config|
    #     config.provider = :weaviate
    #     config.api_key  = ENV["WEAVIATE_API_KEY"]
    #     config.host     = "http://localhost:8080"
    #   end
    #
    #   client = Vectra::Client.new
    #   client.upsert(index: "Document", vectors: [...])
    #
    # rubocop:disable Metrics/ClassLength
    class Weaviate < Base
      API_BASE_PATH = "/v1"

      def provider_name
        :weaviate
      end

      def upsert(index:, vectors:, namespace: nil)
        normalized = normalize_vectors(vectors)

        objects = normalized.map do |vec|
          properties = (vec[:metadata] || {}).dup
          properties["_namespace"] = namespace if namespace

          {
            "class" => index,
            "id" => vec[:id],
            "vector" => vec[:values],
            "properties" => properties
          }
        end

        body = { "objects" => objects }

        response = with_error_handling do
          connection.post("#{API_BASE_PATH}/batch/objects", body)
        end

        if response.success?
          upserted = response.body["objects"]&.size || normalized.size
          log_debug("Upserted #{upserted} vectors to #{index}")
          { upserted_count: upserted }
        else
          handle_error(response)
        end
      end

      def query(index:, vector:, top_k: 10, namespace: nil, filter: nil,
                include_values: false, include_metadata: true)
        where_filter = build_where(filter, namespace)

        selection_fields = []
        selection_fields << "_additional { id distance }"
        selection_fields << "vector" if include_values
        selection_fields << "metadata" if include_metadata

        selection_block = selection_fields.join(" ")

        graphql = <<~GRAPHQL
          {
            Get {
              #{index}(
                limit: #{top_k}
                nearVector: { vector: [#{vector.map { |v| format('%.10f', v.to_f) }.join(', ')}] }
                #{"where: #{JSON.generate(where_filter)}" if where_filter}
              ) {
                #{selection_block}
              }
            }
          }
        GRAPHQL

        body = { "query" => graphql }

        response = with_error_handling do
          connection.post("#{API_BASE_PATH}/graphql", body)
        end

        if response.success?
          matches = extract_query_matches(response.body, index, include_values, include_metadata)
          log_debug("Query returned #{matches.size} results")

          QueryResult.from_response(
            matches: matches,
            namespace: namespace
          )
        else
          handle_error(response)
        end
      end

      # Hybrid search combining vector and BM25 text search
      #
      # Uses Weaviate's hybrid search API with alpha parameter
      #
      # @param index [String] class name
      # @param vector [Array<Float>] query vector
      # @param text [String] text query for BM25 search
      # @param alpha [Float] balance (0.0 = BM25, 1.0 = vector)
      # @param top_k [Integer] number of results
      # @param namespace [String, nil] optional namespace (not used in Weaviate)
      # @param filter [Hash, nil] metadata filter
      # @param include_values [Boolean] include vector values
      # @param include_metadata [Boolean] include metadata
      # @return [QueryResult] search results
      def hybrid_search(index:, vector:, text:, alpha:, top_k:, namespace: nil,
                        filter: nil, include_values: false, include_metadata: true)
        where_filter = build_where(filter, namespace)
        graphql = build_hybrid_search_graphql(
          index: index,
          vector: vector,
          text: text,
          alpha: alpha,
          top_k: top_k,
          where_filter: where_filter,
          include_values: include_values,
          include_metadata: include_metadata
        )
        body = { "query" => graphql }

        response = with_error_handling do
          connection.post("#{API_BASE_PATH}/graphql", body)
        end

        handle_hybrid_search_response(response, index, alpha, namespace,
                                      include_values, include_metadata)
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def fetch(index:, ids:, namespace: nil)
        body = {
          "class" => index,
          "ids" => ids,
          "include" => ["vector", "properties"]
        }

        # Namespace is stored as a property, so we filter client-side
        response = with_error_handling do
          connection.post("#{API_BASE_PATH}/objects/_mget", body)
        end

        if response.success?
          objects = response.body["objects"] || []
          vectors = {}

          objects.each do |obj|
            next unless obj["status"] == "SUCCESS"

            props = obj.dig("result", "properties") || {}
            obj_namespace = props["_namespace"]
            next if namespace && obj_namespace != namespace

            clean_metadata = props.reject { |k, _| k.to_s.start_with?("_") }

            vectors[obj.dig("result", "id")] = Vector.new(
              id: obj.dig("result", "id"),
              values: obj.dig("result", "vector") || [],
              metadata: clean_metadata
            )
          end

          vectors
        else
          handle_error(response)
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def update(index:, id:, metadata:, namespace: nil)
        body = {
          "class" => index,
          "id" => id
        }

        if metadata
          props = metadata.dup
          props["_namespace"] = namespace if namespace
          body["properties"] = props
        end

        response = with_error_handling do
          connection.patch("#{API_BASE_PATH}/objects/#{id}", body)
        end

        if response.success?
          log_debug("Updated metadata for vector #{id}")
          { updated: true }
        else
          handle_error(response)
        end
      end

      # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
      def delete(index:, ids: nil, namespace: nil, filter: nil, delete_all: false)
        if ids
          # Delete individual objects by ID
          ids.each do |id|
            with_error_handling do
              response = connection.delete("#{API_BASE_PATH}/objects/#{id}") do |req|
                req.params["class"] = index
              end
              handle_error(response) unless response.success?
            end
          end

          log_debug("Deleted #{ids.size} vectors from #{index}")
          { deleted: true }
        else
          # Delete by filter / namespace / delete_all
          where_filter = if delete_all && namespace.nil? && filter.nil?
                           nil
                         else
                           build_where(filter, namespace)
                         end

          body = {
            "class" => index
          }
          body["where"] = where_filter if where_filter

          response = with_error_handling do
            connection.post("#{API_BASE_PATH}/objects/delete", body)
          end

          if response.success?
            log_debug("Deleted vectors from #{index} with filter")
            { deleted: true }
          else
            handle_error(response)
          end
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity

      def list_indexes
        response = with_error_handling do
          connection.get("#{API_BASE_PATH}/schema")
        end

        if response.success?
          classes = response.body["classes"] || []
          classes.map do |cls|
            vector_cfg = cls["vectorIndexConfig"] || {}
            {
              name: cls["class"],
              dimension: vector_cfg["dimension"],
              metric: distance_to_metric(vector_cfg["distance"]),
              status: "ready"
            }
          end
        else
          handle_error(response)
        end
      end

      def describe_index(index:)
        response = with_error_handling do
          connection.get("#{API_BASE_PATH}/schema/#{index}")
        end

        if response.success?
          body = response.body
          vector_cfg = body["vectorIndexConfig"] || {}

          {
            name: body["class"] || index,
            dimension: vector_cfg["dimension"],
            metric: distance_to_metric(vector_cfg["distance"]),
            status: "ready"
          }
        else
          handle_error(response)
        end
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def stats(index:, namespace: nil)
        where_filter = namespace ? build_where({}, namespace) : nil

        where_clause = where_filter ? "where: #{JSON.generate(where_filter)}" : ""

        graphql = <<~GRAPHQL
          {
            Aggregate {
              #{index}(
                #{where_clause}
              ) {
                meta {
                  count
                }
              }
            }
          }
        GRAPHQL

        body = { "query" => graphql }

        response = with_error_handling do
          connection.post("#{API_BASE_PATH}/graphql", body)
        end

        if response.success?
          data = response.body["data"] || {}
          aggregate = data["Aggregate"] || {}
          class_stats = aggregate[index]&.first || {}
          meta = class_stats["meta"] || {}

          {
            total_vector_count: meta["count"] || 0,
            dimension: nil,
            namespaces: namespace ? { namespace => { vector_count: meta["count"] || 0 } } : {}
          }
        else
          handle_error(response)
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      def build_hybrid_search_graphql(index:, vector:, text:, alpha:, top_k:,
                                       where_filter:, include_values:, include_metadata:)
        selection_block = build_selection_fields(include_values, include_metadata).join(" ")
        build_graphql_query(index, top_k, text, alpha, vector, where_filter, selection_block)
      end

      def build_graphql_query(index, top_k, text, alpha, vector, where_filter, selection_block)
        <<~GRAPHQL
          {
            Get {
              #{index}(
                limit: #{top_k}
                hybrid: {
                  query: "#{text.gsub('"', '\\"')}"
                  alpha: #{alpha}
                }
                nearVector: { vector: [#{vector.map { |v| format('%.10f', v.to_f) }.join(', ')}] }
                #{"where: #{JSON.generate(where_filter)}" if where_filter}
              ) {
                #{selection_block}
              }
            }
          }
        GRAPHQL
      end

      def build_selection_fields(include_values, include_metadata)
        fields = ["_additional { id distance }"]
        fields << "vector" if include_values
        fields << "metadata" if include_metadata
        fields
      end

      def handle_hybrid_search_response(response, index, alpha, namespace,
                                        include_values, include_metadata)
        if response.success?
          matches = extract_query_matches(response.body, index, include_values, include_metadata)
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
        raise ConfigurationError, "Host must be configured for Weaviate" if config.host.nil? || config.host.empty?
      end

      def connection
        @connection ||= begin
          base_url = config.host
          base_url = "http://#{base_url}" unless base_url.start_with?("http://", "https://")

          build_connection(
            base_url,
            auth_headers
          )
        end
      end

      def auth_headers
        return {} unless config.api_key && !config.api_key.empty?

        { "Authorization" => "Bearer #{config.api_key}" }
      end

      # Wrap HTTP calls to handle Faraday::RetriableResponse
      def with_error_handling
        yield
      rescue Faraday::RetriableResponse => e
        handle_retriable_response(e)
      end

      # Build Weaviate "where" filter for GraphQL API from generic filter + namespace
      #
      # Weaviate expects a structure like:
      # {
      #   operator: "And",
      #   operands: [
      #     { path: ["category"], operator: "Equal", valueString: "tech" },
      #     ...
      #   ]
      # }
      def build_where(filter, namespace)
        operands = []

        if namespace
          operands << {
            "path" => ["_namespace"],
            "operator" => "Equal",
            "valueString" => namespace
          }
        end

        if filter.is_a?(Hash)
          filter.each do |key, value|
            operands << build_where_operand(key.to_s, value)
          end
        end

        return nil if operands.empty?

        {
          "operator" => "And",
          "operands" => operands
        }
      end

      def build_where_operand(key, value)
        case value
        when Hash
          build_operator_operand(key, value)
        when Array
          {
            "path" => [key],
            "operator" => "ContainsAny",
            "valueStringArray" => value.map(&:to_s)
          }
        else
          {
            "path" => [key],
            "operator" => "Equal",
            infer_value_key(value) => value
          }
        end
      end

      # rubocop:disable Metrics/MethodLength
      def build_operator_operand(key, operator_hash)
        op, val = operator_hash.first

        case op.to_s
        when "$gt"
          {
            "path" => [key],
            "operator" => "GreaterThan",
            infer_value_key(val) => val
          }
        when "$gte"
          {
            "path" => [key],
            "operator" => "GreaterThanEqual",
            infer_value_key(val) => val
          }
        when "$lt"
          {
            "path" => [key],
            "operator" => "LessThan",
            infer_value_key(val) => val
          }
        when "$lte"
          {
            "path" => [key],
            "operator" => "LessThanEqual",
            infer_value_key(val) => val
          }
        when "$ne"
          {
            "path" => [key],
            "operator" => "NotEqual",
            infer_value_key(val) => val
          }
        else
          {
            "path" => [key],
            "operator" => "Equal",
            infer_value_key(val) => val
          }
        end
      end
      # rubocop:enable Metrics/MethodLength

      # Choose the appropriate GraphQL value key based on Ruby type
      def infer_value_key(value)
        case value
        when Integer
          "valueInt"
        when Float
          "valueNumber"
        when TrueClass, FalseClass
          "valueBoolean"
        else
          "valueString"
        end
      end

      # Extract matches from GraphQL response
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def extract_query_matches(body, index, include_values, include_metadata)
        data = body["data"] || {}
        get_block = data["Get"] || {}
        raw_matches = get_block[index] || []

        raw_matches.map do |obj|
          additional = obj["_additional"] || {}
          distance = additional["distance"]
          certainty = additional["certainty"]

          score = if certainty
                    certainty.to_f
                  elsif distance
                    1.0 - distance.to_f
                  end

          metadata = if include_metadata
                       obj["metadata"] || {}
                     else
                       {}
                     end

          values = include_values ? obj["vector"] : nil

          {
            id: additional["id"] || obj["id"],
            score: score,
            values: values,
            metadata: metadata
          }
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Convert Weaviate distance name to Vectra metric
      def distance_to_metric(distance)
        case distance.to_s.downcase
        when "cosine"
          "cosine"
        when "l2-squared", "l2"
          "euclidean"
        when "dot"
          "dot_product"
        else
          distance.to_s.downcase
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
