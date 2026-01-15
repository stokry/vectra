# frozen_string_literal: true

require_relative "pgvector/connection"
require_relative "pgvector/sql_helpers"
require_relative "pgvector/index_management"

module Vectra
  module Providers
    # PostgreSQL with pgvector extension provider
    #
    # This provider uses PostgreSQL with the pgvector extension for vector
    # similarity search. Each "index" maps to a PostgreSQL table.
    #
    # @example Table structure
    #   CREATE EXTENSION IF NOT EXISTS vector;
    #   CREATE TABLE my_index (
    #     id TEXT PRIMARY KEY,
    #     embedding vector(384),
    #     metadata JSONB DEFAULT '{}',
    #     namespace TEXT DEFAULT '',
    #     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    #   );
    #   CREATE INDEX ON my_index USING ivfflat (embedding vector_cosine_ops);
    #
    # @example Usage
    #   client = Vectra.pgvector(
    #     connection_url: "postgres://user:pass@localhost/mydb"
    #   )
    #   client.upsert(index: 'documents', vectors: [...])
    #
    class Pgvector < Base
      include Connection
      include SqlHelpers
      include IndexManagement

      DISTANCE_FUNCTIONS = {
        "cosine" => "<=>",
        "euclidean" => "<->",
        "inner_product" => "<#>"
      }.freeze

      DEFAULT_METRIC = "cosine"

      def initialize(config)
        super
        @connection = nil
        @table_cache = {}
      end

      # @see Base#provider_name
      def provider_name
        :pgvector
      end

      # @see Base#upsert
      def upsert(index:, vectors:, namespace: nil)
        ensure_table_exists!(index)
        normalized = normalize_vectors(vectors)
        ns = namespace || ""

        upserted = 0
        normalized.each do |vec|
          upsert_single_vector(index, vec, ns)
          upserted += 1
        end

        log_debug("Upserted #{upserted} vectors to #{index}")
        { upserted_count: upserted }
      end

      # @see Base#query
      def query(index:, vector:, top_k: 10, namespace: nil, filter: nil,
                include_values: false, include_metadata: true)
        ensure_table_exists!(index)

        distance_op = DISTANCE_FUNCTIONS[table_metric(index)]
        vector_literal = format_vector(vector)

        sql = build_query_sql(
          index: index,
          vector_literal: vector_literal,
          distance_op: distance_op,
          top_k: top_k,
          namespace: namespace,
          filter: filter,
          include_values: include_values,
          include_metadata: include_metadata
        )

        result = execute(sql)
        matches = result.map { |row| build_match_from_row(row, include_values, include_metadata) }

        log_debug("Query returned #{matches.size} results")
        QueryResult.from_response(matches: matches, namespace: namespace)
      end

      # Hybrid search combining vector similarity and PostgreSQL full-text search
      #
      # Combines pgvector similarity search with PostgreSQL's native full-text search.
      # Requires a text search column (tsvector) in your table.
      #
      # @param index [String] table name
      # @param vector [Array<Float>] query vector
      # @param text [String] text query for full-text search
      # @param alpha [Float] balance (0.0 = full-text, 1.0 = vector)
      # @param top_k [Integer] number of results
      # @param namespace [String, nil] optional namespace
      # @param filter [Hash, nil] metadata filter
      # @param include_values [Boolean] include vector values
      # @param include_metadata [Boolean] include metadata
      # @param text_column [String] column name for full-text search (default: 'content')
      # @return [QueryResult] search results
      #
      # @note Your table should have a text column with a tsvector index:
      #   CREATE INDEX idx_content_fts ON my_index USING gin(to_tsvector('english', content));
      def hybrid_search(index:, vector:, text:, alpha:, top_k:, namespace: nil,
                        filter: nil, include_values: false, include_metadata: true,
                        text_column: "content")
        ensure_table_exists!(index)

        vector_literal = format_vector(vector)
        distance_op = DISTANCE_FUNCTIONS[table_metric(index)]

        # Build hybrid score: alpha * vector_similarity + (1-alpha) * text_rank
        # Vector similarity: 1 - (distance / max_distance)
        # Text rank: ts_rank from full-text search
        select_cols = ["id"]
        select_cols << "embedding" if include_values
        select_cols << "metadata" if include_metadata

        # Calculate hybrid score
        # For vector: use cosine distance (1 - distance gives similarity)
        # For text: use ts_rank
        vector_score = "1.0 - (embedding #{distance_op} '#{vector_literal}'::vector)"
        text_score = "ts_rank(to_tsvector('english', COALESCE(#{quote_ident(text_column)}, '')), " \
                     "plainto_tsquery('english', #{escape_literal(text)}))"

        # Normalize scores to 0-1 range and combine with alpha
        hybrid_score = "(#{alpha} * #{vector_score} + (1.0 - #{alpha}) * #{text_score})"

        select_cols << "#{hybrid_score} AS score"
        select_cols << "#{vector_score} AS vector_score"
        select_cols << "#{text_score} AS text_score"

        where_clauses = build_where_clauses(namespace, filter)
        where_clauses << "to_tsvector('english', COALESCE(#{quote_ident(text_column)}, '')) @@ " \
                         "plainto_tsquery('english', #{escape_literal(text)})"

        sql = "SELECT #{select_cols.join(', ')} FROM #{quote_ident(index)}"
        sql += " WHERE #{where_clauses.join(' AND ')}" if where_clauses.any?
        sql += " ORDER BY score DESC"
        sql += " LIMIT #{top_k.to_i}"

        result = execute(sql)
        matches = result.map { |row| build_match_from_row(row, include_values, include_metadata) }

        log_debug("Hybrid search returned #{matches.size} results (alpha: #{alpha})")

        QueryResult.from_response(
          matches: matches,
          namespace: namespace
        )
      end

      # Text-only search using PostgreSQL full-text search
      #
      # @param index [String] table name
      # @param text [String] text query for full-text search
      # @param top_k [Integer] number of results
      # @param namespace [String, nil] optional namespace
      # @param filter [Hash, nil] metadata filter
      # @param include_values [Boolean] include vector values
      # @param include_metadata [Boolean] include metadata
      # @param text_column [String] column name for full-text search (default: 'content')
      # @return [QueryResult] search results
      #
      # @note Your table should have a text column with a tsvector index:
      #   CREATE INDEX idx_content_fts ON my_index USING gin(to_tsvector('english', content));
      def text_search(index:, text:, top_k:, namespace: nil, filter: nil,
                      include_values: false, include_metadata: true,
                      text_column: "content")
        ensure_table_exists!(index)

        select_cols = ["id"]
        select_cols << "embedding" if include_values
        select_cols << "metadata" if include_metadata

        # Use ts_rank for scoring
        text_score = "ts_rank(to_tsvector('english', COALESCE(#{quote_ident(text_column)}, '')), " \
                     "plainto_tsquery('english', #{escape_literal(text)}))"
        select_cols << "#{text_score} AS score"

        where_clauses = build_where_clauses(namespace, filter)
        where_clauses << "to_tsvector('english', COALESCE(#{quote_ident(text_column)}, '')) @@ " \
                         "plainto_tsquery('english', #{escape_literal(text)})"

        sql = "SELECT #{select_cols.join(', ')} FROM #{quote_ident(index)}"
        sql += " WHERE #{where_clauses.join(' AND ')}" if where_clauses.any?
        sql += " ORDER BY score DESC"
        sql += " LIMIT #{top_k.to_i}"

        result = execute(sql)
        matches = result.map { |row| build_match_from_row(row, include_values, include_metadata) }

        log_debug("Text search returned #{matches.size} results")

        QueryResult.from_response(
          matches: matches,
          namespace: namespace
        )
      end

      # @see Base#fetch
      def fetch(index:, ids:, namespace: nil)
        ensure_table_exists!(index)

        placeholders = ids.map.with_index { |_, i| "$#{i + 1}" }.join(", ")
        sql = "SELECT id, embedding, metadata FROM #{quote_ident(index)} WHERE id IN (#{placeholders})"
        sql += " AND namespace = $#{ids.size + 1}" if namespace

        params = namespace ? ids + [namespace] : ids
        result = execute(sql, params)

        vectors = {}
        result.each do |row|
          vectors[row["id"]] = Vector.new(
            id: row["id"],
            values: parse_vector(row["embedding"]),
            metadata: parse_json(row["metadata"])
          )
        end
        vectors
      end

      # @see Base#update
      def update(index:, id:, metadata: nil, values: nil, namespace: nil)
        ensure_table_exists!(index)
        updates, params, param_idx = build_update_params(metadata, values)

        return { updated: false } if updates.empty?

        sql = "UPDATE #{quote_ident(index)} SET #{updates.join(', ')} WHERE id = $#{param_idx}"
        params << id

        if namespace
          sql += " AND namespace = $#{param_idx + 1}"
          params << namespace
        end

        execute(sql, params)
        log_debug("Updated vector #{id}")
        { updated: true }
      end

      # @see Base#delete
      def delete(index:, ids: nil, namespace: nil, filter: nil, delete_all: false)
        ensure_table_exists!(index)

        if delete_all || (namespace && ids.nil? && filter.nil?)
          delete_all_vectors(index, namespace)
        elsif ids
          delete_by_ids(index, ids, namespace)
        elsif filter
          sql, params = build_filter_delete_sql(index, filter, namespace)
          execute(sql, params)
        end

        log_debug("Deleted vectors from #{index}")
        { deleted: true }
      end

      # @see Base#list_indexes
      def list_indexes
        sql = <<~SQL
          SELECT table_name
          FROM information_schema.columns
          WHERE column_name = 'embedding'
            AND data_type = 'USER-DEFINED'
            AND table_schema = 'public'
            AND udt_name = 'vector'
        SQL

        result = execute(sql)
        result.map { |row| describe_index(index: row["table_name"]) }
      end

      # @see Base#describe_index
      def describe_index(index:)
        sql = <<~SQL
          SELECT format_type(a.atttypid, a.atttypmod) as data_type
          FROM pg_attribute a
          JOIN pg_class c ON a.attrelid = c.oid
          WHERE c.relname = $1 AND a.attname = 'embedding' AND a.attnum > 0
        SQL

        result = execute(sql, [index])
        raise NotFoundError, "Index '#{index}' not found" if result.empty?

        dimension = resolve_index_dimension(index, result)

        { name: index, dimension: dimension, metric: table_metric(index), status: "ready" }
      end

      # Resolve vector dimension for an index from various sources
      def resolve_index_dimension(index, pg_attribute_result)
        type_info = pg_attribute_result.first["data_type"] || pg_attribute_result.first["udt_name"]
        dim = extract_dimension_from_type(type_info) if type_info

        return dim if dim

        if @table_cache[index].is_a?(Hash)
          return @table_cache[index][:dimension]
        end

        alt_sql = <<~SQL
          SELECT udt_name, data_type FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = $1 AND column_name = 'embedding'
        SQL
        alt_result = execute(alt_sql, [index])
        udt = alt_result.first && (alt_result.first["udt_name"] || alt_result.first["data_type"])
        extract_dimension_from_type(udt) if udt
      end

      # @see Base#stats
      def stats(index:, namespace: nil)
        ensure_table_exists!(index)

        count_sql = "SELECT COUNT(*) as count FROM #{quote_ident(index)}"
        count_sql += " WHERE namespace = $1" if namespace

        count_result = execute(count_sql, namespace ? [namespace] : [])
        total_count = count_result.first["count"].to_i

        ns_sql = "SELECT namespace, COUNT(*) as count FROM #{quote_ident(index)} GROUP BY namespace"
        ns_result = execute(ns_sql)
        namespaces = ns_result.each_with_object({}) do |row, hash|
          hash[row["namespace"] || ""] = { vector_count: row["count"].to_i }
        end

        info = describe_index(index: index)
        { total_vector_count: total_count, dimension: info[:dimension], namespaces: namespaces }
      end

      private

      # Build update parameters
      def build_update_params(metadata, values)
        updates = []
        params = []
        param_idx = 1

        # Put embedding param first so tests expect embedding = $1::vector when provided
        if values
          updates << "embedding = $#{param_idx}::vector"
          params << format_vector(values)
          param_idx += 1
        end

        if metadata
          updates << "metadata = metadata || $#{param_idx}::jsonb"
          params << metadata.to_json
          param_idx += 1
        end

        [updates, params, param_idx]
      end

      # Upsert a single vector
      def upsert_single_vector(index, vec, namespace)
        sql = <<~SQL
          INSERT INTO #{quote_ident(index)} (id, embedding, metadata, namespace)
          VALUES ($1, $2::vector, $3::jsonb, $4)
          ON CONFLICT (id) DO UPDATE SET
            embedding = EXCLUDED.embedding,
            metadata = EXCLUDED.metadata,
            namespace = EXCLUDED.namespace
        SQL

        params = [vec[:id], format_vector(vec[:values]), (vec[:metadata] || {}).to_json, namespace]
        execute(sql, params)
      end

      # Delete all vectors from index
      def delete_all_vectors(index, namespace)
        sql = "DELETE FROM #{quote_ident(index)}"
        sql += " WHERE namespace = $1" if namespace
        execute(sql, namespace ? [namespace] : [])
      end

      # Delete vectors by IDs
      def delete_by_ids(index, ids, namespace)
        placeholders = ids.map.with_index { |_, i| "$#{i + 1}" }.join(", ")
        sql = "DELETE FROM #{quote_ident(index)} WHERE id IN (#{placeholders})"
        params = ids.dup

        if namespace
          sql += " AND namespace = $#{ids.size + 1}"
          params << namespace
        end

        execute(sql, params)
      end

      # Override validate_config! for pgvector-specific validation
      def validate_config!
        raise ConfigurationError, "Provider must be configured" if config.provider.nil?
        return if config.host

        raise ConfigurationError, "Host (connection URL or hostname) must be configured for pgvector"
      end
    end
  end
end
