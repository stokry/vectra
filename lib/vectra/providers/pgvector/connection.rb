# frozen_string_literal: true

module Vectra
  module Providers
    class Pgvector < Base
      # Connection management for pgvector provider
      module Connection
        include Vectra::Retry

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
            { conninfo: config.host }
          else
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
          if config.host&.include?("/")
            config.host.split("/").last
          else
            "postgres"
          end
        end

        # Extract username
        def extract_username
          ENV.fetch("PGUSER", "postgres")
        end

        # Execute SQL with parameters
        def execute(sql, params = [])
          log_debug("Executing SQL", { sql: sql, params: params })
          with_retry do
            connection.exec_params(sql, params)
          end
        rescue PG::Error => e
          handle_pg_error(e)
        end

        # Handle PostgreSQL errors
        def handle_pg_error(error)
          case error
          when PG::UndefinedTable
            raise NotFoundError, "not found"
          when PG::InvalidPassword
            raise AuthenticationError, "authentication failed"
          when PG::ConnectionBad
            raise ConnectionError, "connection failed"
          when PG::UniqueViolation, PG::CheckViolation
            raise ValidationError, error.message
          else
            raise ServerError.new(error.message, status_code: 500)
          end
        end
      end
    end
  end
end
