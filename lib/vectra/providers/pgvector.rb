# frozen_string_literal: true

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
        matches = result.map do |row|
          build_match_from_row(row, include_values, include_metadata)
        end

        log_debug("Query returned #{matches.size} results")
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

        updates = []
        params = []
        param_idx = 1

        if metadata
          updates << "metadata = metadata || $#{param_idx}::jsonb"
          params << metadata.to_json
          param_idx += 1
        end

        if values
          updates << "embedding = $#{param_idx}::vector"
          params << format_vector(values)
          param_idx += 1
        end

        return { updated: false } if updates.empty?

        sql = "UPDATE #{quote_ident(index)} SET #{updates.join(', ')} WHERE id = $#{param_idx}"
        params << id
        param_idx += 1

        if namespace
          sql += " AND namespace = $#{param_idx}"
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
          sql = "DELETE FROM #{quote_ident(index)}"
          sql += " WHERE namespace = $1" if namespace
          execute(sql, namespace ? [namespace] : [])
        elsif ids
          placeholders = ids.map.with_index { |_, i| "$#{i + 1}" }.join(", ")
          sql = "DELETE FROM #{quote_ident(index)} WHERE id IN (#{placeholders})"
          params = ids.dup

          if namespace
            sql += " AND namespace = $#{ids.size + 1}"
            params << namespace
          end

          execute(sql, params)
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
        SQL

        result = execute(sql)
        result.map do |row|
          info = describe_index(index: row["table_name"])
          info
        end
      end

      # @see Base#describe_index
      def describe_index(index:)
        # Get dimension from the vector column
        sql = <<~SQL
          SELECT
            a.attname as column_name,
            format_type(a.atttypid, a.atttypmod) as data_type
          FROM pg_attribute a
          JOIN pg_class c ON a.attrelid = c.oid
          WHERE c.relname = $1
            AND a.attname = 'embedding'
            AND a.attnum > 0
        SQL

        result = execute(sql, [index])

        if result.empty?
          raise NotFoundError, "Index '#{index}' not found"
        end

        # Parse dimension from type like "vector(384)"
        type_info = result.first["data_type"]
        dimension = extract_dimension_from_type(type_info)

        {
          name: index,
          dimension: dimension,
          metric: table_metric(index),
          status: "ready"
        }
      end

      # @see Base#stats
      def stats(index:, namespace: nil)
        ensure_table_exists!(index)

        count_sql = "SELECT COUNT(*) as count FROM #{quote_ident(index)}"
        count_sql += " WHERE namespace = $1" if namespace

        count_result = execute(count_sql, namespace ? [namespace] : [])
        total_count = count_result.first["count"].to_i

        # Get namespace breakdown
        ns_sql = <<~SQL
          SELECT namespace, COUNT(*) as count
          FROM #{quote_ident(index)}
          GROUP BY namespace
        SQL

        ns_result = execute(ns_sql)
        namespaces = ns_result.each_with_object({}) do |row, hash|
          hash[row["namespace"] || ""] = { vector_count: row["count"].to_i }
        end

        info = describe_index(index: index)

        {
          total_vector_count: total_count,
          dimension: info[:dimension],
          namespaces: namespaces
        }
      end

      INDEX_OPS = {
        "cosine" => "vector_cosine_ops",
        "euclidean" => "vector_l2_ops",
        "inner_product" => "vector_ip_ops"
      }.freeze

      # Create a new index (table with vector column)
      #
      # @param name [String] table name
      # @param dimension [Integer] vector dimension
      # @param metric [String] similarity metric (cosine, euclidean, inner_product)
      # @return [Hash] created index info
      def create_index(name:, dimension:, metric: DEFAULT_METRIC)
        validate_metric!(metric)
        create_table_with_vector(name, dimension)
        create_ivfflat_index(name, metric)
        store_metric_comment(name, metric)

        @table_cache[name] = { dimension: dimension, metric: metric }
        log_debug("Created index #{name}")
        describe_index(index: name)
      end

      # Delete an index (drop table)
      #
      # @param name [String] table name
      # @return [Hash] deletion result
      def delete_index(name:)
        execute("DROP TABLE IF EXISTS #{quote_ident(name)} CASCADE")
        @table_cache.delete(name)
        log_debug("Deleted index #{name}")
        { deleted: true }
      end

      private

      # Get or create database connection
      def connection
        @connection ||= begin
          require "pg"

          conn_params = parse_connection_params
          PG.connect(conn_params)
        end
      end

      # Parse connection parameters from config
      def parse_connection_params
        if config.host&.start_with?("postgres://", "postgresql://")
          # Connection URL format
          { conninfo: config.host }
        else
          # Individual parameters
          {
            host: config.host || "localhost",
            port: config.environment&.to_i || 5432,
            dbname: extract_database_name,
            user: extract_username,
            password: config.api_key
          }.compact
        end
      end

      # Extract database name from host or use default
      def extract_database_name
        # Allow setting via host like "localhost/mydb"
        if config.host&.include?("/")
          config.host.split("/").last
        else
          "postgres"
        end
      end

      # Extract username - pgvector uses api_key field for password
      def extract_username
        # Could be extended to support user in host string
        ENV.fetch("PGUSER", "postgres")
      end

      # Execute SQL with parameters
      def execute(sql, params = [])
        log_debug("Executing SQL", { sql: sql, params: params })
        connection.exec_params(sql, params)
      rescue PG::Error => e
        handle_pg_error(e)
      end

      # Handle PostgreSQL errors
      def handle_pg_error(error)
        case error
        when PG::UndefinedTable
          raise NotFoundError, error.message
        when PG::InvalidPassword, PG::ConnectionBad
          raise AuthenticationError, error.message
        when PG::UniqueViolation, PG::CheckViolation
          raise ValidationError, error.message
        else
          raise ServerError.new(error.message, status_code: 500)
        end
      end

      # Quote identifier to prevent SQL injection
      def quote_ident(name)
        connection.quote_ident(name)
      end

      # Escape literal string
      def escape_literal(str)
        connection.escape_literal(str)
      end

      # Format vector for PostgreSQL
      def format_vector(values)
        "[#{values.map(&:to_f).join(',')}]"
      end

      # Parse vector from PostgreSQL string format
      def parse_vector(str)
        return nil unless str

        str.gsub(/[\[\]]/, "").split(",").map(&:to_f)
      end

      # Parse JSON from PostgreSQL
      def parse_json(str)
        return {} unless str

        case str
        when String
          JSON.parse(str)
        when Hash
          str
        else
          {}
        end
      rescue JSON::ParserError
        {}
      end

      # Ensure table exists
      def ensure_table_exists!(index)
        return if @table_cache.key?(index)

        sql = <<~SQL
          SELECT EXISTS (
            SELECT FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = $1
          )
        SQL

        result = execute(sql, [index])
        exists_value = result.first["exists"]
        exists = [true, "t"].include?(exists_value)

        raise NotFoundError, "Index '#{index}' not found" unless exists

        @table_cache[index] = true
      end

      # Get metric for a table from stored comment
      def table_metric(index)
        return @table_cache.dig(index, :metric) if @table_cache[index].is_a?(Hash)

        sql = <<~SQL
          SELECT obj_description($1::regclass, 'pg_class') as comment
        SQL

        result = execute(sql, [index])
        comment = result.first&.fetch("comment", nil)

        metric = if comment&.include?("vectra:metric=")
                   comment.match(/vectra:metric=(\w+)/)&.captures&.first
                 end

        metric || DEFAULT_METRIC
      end

      # Validate metric type
      def validate_metric!(metric)
        return if DISTANCE_FUNCTIONS.key?(metric)

        raise ValidationError, "Invalid metric '#{metric}'. Supported: #{DISTANCE_FUNCTIONS.keys.join(', ')}"
      end

      # Extract dimension from vector type string like "vector(384)"
      def extract_dimension_from_type(type_info)
        match = type_info.match(/vector\((\d+)\)/)
        return nil unless match

        match.captures.first.to_i
      end

      # Create table with vector column
      def create_table_with_vector(name, dimension)
        execute("CREATE EXTENSION IF NOT EXISTS vector")

        sql = <<~SQL
          CREATE TABLE IF NOT EXISTS #{quote_ident(name)} (
            id TEXT PRIMARY KEY,
            embedding vector(#{dimension.to_i}),
            metadata JSONB DEFAULT '{}',
            namespace TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        SQL
        execute(sql)
      end

      # Create IVFFlat index for similarity search
      def create_ivfflat_index(name, metric)
        index_op = INDEX_OPS[metric]
        idx_name = "#{name}_embedding_idx"
        idx_sql = <<~SQL
          CREATE INDEX IF NOT EXISTS #{quote_ident(idx_name)}
          ON #{quote_ident(name)}
          USING ivfflat (embedding #{index_op})
          WITH (lists = 100)
        SQL

        execute(idx_sql)
      rescue PG::Error => e
        # IVFFlat requires data; will be created on first insert
        log_debug("Index creation deferred: #{e.message}")
      end

      # Store metric in table comment
      def store_metric_comment(name, metric)
        execute("COMMENT ON TABLE #{quote_ident(name)} IS #{escape_literal("vectra:metric=#{metric}")}")
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

        params = [
          vec[:id],
          format_vector(vec[:values]),
          (vec[:metadata] || {}).to_json,
          namespace
        ]
        execute(sql, params)
      end

      # Build SQL for vector similarity query
      def build_query_sql(index:, vector_literal:, distance_op:, top_k:,
                          namespace:, filter:, include_values:, include_metadata:)
        select_cols = ["id"]
        select_cols << "1 - (embedding #{distance_op} '#{vector_literal}'::vector) as score"
        select_cols << "embedding" if include_values
        select_cols << "metadata" if include_metadata

        sql = "SELECT #{select_cols.join(', ')} FROM #{quote_ident(index)}"

        where_clauses = []
        where_clauses << "namespace = #{escape_literal(namespace)}" if namespace

        filter&.each do |key, value|
          json_path = "metadata->>#{escape_literal(key.to_s)}"
          where_clauses << "#{json_path} = #{escape_literal(value.to_s)}"
        end

        sql += " WHERE #{where_clauses.join(' AND ')}" if where_clauses.any?
        sql += " ORDER BY embedding #{distance_op} '#{vector_literal}'::vector"
        sql += " LIMIT #{top_k.to_i}"

        sql
      end

      # Build match hash from database row
      def build_match_from_row(row, include_values, include_metadata)
        match = {
          id: row["id"],
          score: row["score"].to_f
        }
        match[:values] = parse_vector(row["embedding"]) if include_values && row["embedding"]
        match[:metadata] = parse_json(row["metadata"]) if include_metadata && row["metadata"]
        match
      end

      # Build SQL for filter-based delete
      def build_filter_delete_sql(index, filter, namespace)
        sql = "DELETE FROM #{quote_ident(index)} WHERE "
        clauses = []
        params = []
        param_idx = 1

        filter.each do |key, value|
          clauses << "metadata->>$#{param_idx} = $#{param_idx + 1}"
          params << key.to_s
          params << value.to_s
          param_idx += 2
        end

        if namespace
          clauses << "namespace = $#{param_idx}"
          params << namespace
        end

        sql += clauses.join(" AND ")
        [sql, params]
      end

      # Override validate_config! for pgvector-specific validation
      def validate_config!
        raise ConfigurationError, "Provider must be configured" if config.provider.nil?

        # pgvector doesn't require api_key if using local connection
        return if config.host

        raise ConfigurationError, "Host (connection URL or hostname) must be configured for pgvector"
      end
    end
  end
end
