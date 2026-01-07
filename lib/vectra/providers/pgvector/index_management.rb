# frozen_string_literal: true

module Vectra
  module Providers
    class Pgvector < Base
      # Index management methods for pgvector provider
      module IndexManagement
        INDEX_OPS = {
          "cosine" => "vector_cosine_ops",
          "euclidean" => "vector_l2_ops",
          "inner_product" => "vector_ip_ops"
        }.freeze

        # Create a new index (table with vector column)
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
        def delete_index(name:)
          execute("DROP TABLE IF EXISTS #{quote_ident(name)} CASCADE")
          @table_cache.delete(name)
          log_debug("Deleted index #{name}")
          { deleted: true }
        end

        private

        # Validate metric type
        def validate_metric!(metric)
          return if DISTANCE_FUNCTIONS.key?(metric)

          raise ValidationError, "Invalid metric '#{metric}'. Supported: #{DISTANCE_FUNCTIONS.keys.join(', ')}"
        end

        # Extract dimension from vector type string
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
          log_debug("Index creation deferred: #{e.message}")
        end

        # Store metric in table comment
        def store_metric_comment(name, metric)
          execute("COMMENT ON TABLE #{quote_ident(name)} IS #{escape_literal("vectra:metric=#{metric}")}")
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

          sql = "SELECT obj_description($1::regclass, 'pg_class') as comment"
          result = execute(sql, [index])
          comment = result.first&.fetch("comment", nil)

          metric = comment&.include?("vectra:metric=") ? comment.match(/vectra:metric=(\w+)/)&.captures&.first : nil
          metric || DEFAULT_METRIC
        end
      end
    end
  end
end
