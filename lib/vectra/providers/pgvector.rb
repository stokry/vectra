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

        if delete_all
          delete_all_vectors(index, namespace)
        elsif ids
          delete_by_ids(index, ids, namespace)
        elsif filter
          sql, params = build_filter_delete_sql(index, filter, namespace)
          execute(sql, params)
        elsif namespace
          # Delete all vectors in the specified namespace when only namespace provided
          delete_all_vectors(index, namespace)
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

        # Prefer any returned type info; fall back to cached table info if available
        type_info = result.first["data_type"] || result.first["udt_name"]
        dimension = extract_dimension_from_type(type_info) if type_info

        if dimension.nil? && @table_cache[index].is_a?(Hash)
          dimension = @table_cache[index][:dimension]
        end

        # Try information_schema as a last resort
        if dimension.nil?
          alt_sql = <<~SQL
            SELECT udt_name FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = $1 AND column_name = 'embedding'
          SQL
          alt_result = execute(alt_sql, [index])
          udt = alt_result.first && (alt_result.first["udt_name"] || alt_result.first["data_type"])
          dimension = extract_dimension_from_type(udt) if udt
        end

        { name: index, dimension: dimension, metric: table_metric(index), status: "ready" }
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
