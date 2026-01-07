# frozen_string_literal: true

module Vectra
  module Providers
    class Pgvector < Base
      # SQL helper methods for pgvector provider
      module SqlHelpers
        private

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

        # Build SQL for vector similarity query
        def build_query_sql(index:, vector_literal:, distance_op:, top_k:,
                            namespace:, filter:, include_values:, include_metadata:)
          select_cols = build_select_columns(vector_literal, distance_op, include_values, include_metadata)
          where_clauses = build_where_clauses(namespace, filter)

          sql = "SELECT #{select_cols.join(', ')} FROM #{quote_ident(index)}"
          sql += " WHERE #{where_clauses.join(' AND ')}" if where_clauses.any?
          sql += " ORDER BY embedding #{distance_op} '#{vector_literal}'::vector"
          sql += " LIMIT #{top_k.to_i}"
          sql
        end

        # Build SELECT columns for query
        def build_select_columns(vector_literal, distance_op, include_values, include_metadata)
          cols = ["id", "1 - (embedding #{distance_op} '#{vector_literal}'::vector) as score"]
          cols << "embedding" if include_values
          cols << "metadata" if include_metadata
          cols
        end

        # Build WHERE clauses for query
        def build_where_clauses(namespace, filter)
          clauses = []
          clauses << "namespace = #{escape_literal(namespace)}" if namespace

          filter&.each do |key, value|
            json_path = "metadata->>#{escape_literal(key.to_s)}"
            clauses << "#{json_path} = #{escape_literal(value.to_s)}"
          end

          clauses
        end

        # Build match hash from database row
        def build_match_from_row(row, include_values, include_metadata)
          match = { id: row["id"], score: row["score"].to_f }
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
      end
    end
  end
end
