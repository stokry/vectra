# frozen_string_literal: true

require_relative "vectra/version"
require_relative "vectra/errors"
require_relative "vectra/configuration"
require_relative "vectra/vector"
require_relative "vectra/query_result"
require_relative "vectra/instrumentation"
require_relative "vectra/retry"
require_relative "vectra/batch"
require_relative "vectra/streaming"
require_relative "vectra/cache"
require_relative "vectra/pool"
require_relative "vectra/circuit_breaker"
require_relative "vectra/rate_limiter"
require_relative "vectra/logging"
require_relative "vectra/health_check"
require_relative "vectra/credential_rotation"
require_relative "vectra/audit_log"
require_relative "vectra/active_record"
require_relative "vectra/middleware/request"
require_relative "vectra/middleware/response"
require_relative "vectra/middleware/base"
require_relative "vectra/middleware/stack"
require_relative "vectra/middleware/logging"
require_relative "vectra/middleware/retry"
require_relative "vectra/middleware/instrumentation"
require_relative "vectra/middleware/pii_redaction"
require_relative "vectra/middleware/cost_tracker"
require_relative "vectra/middleware/request_id"
require_relative "vectra/middleware/dry_run"
require_relative "vectra/migration"
require_relative "vectra/providers/base"
require_relative "vectra/providers/pinecone"
require_relative "vectra/providers/qdrant"
require_relative "vectra/providers/weaviate"
require_relative "vectra/providers/pgvector"
require_relative "vectra/providers/memory"
require_relative "vectra/client"

# Vectra - Unified Ruby client for vector databases
#
# Vectra provides a simple, unified interface to work with multiple
# vector database providers including Pinecone, Qdrant, and Weaviate.
#
# @example Basic usage
#   # Configure globally
#   Vectra.configure do |config|
#     config.provider = :pinecone
#     config.api_key = ENV['PINECONE_API_KEY']
#     config.environment = 'us-east-1'
#   end
#
#   # Create a client
#   client = Vectra::Client.new
#
#   # Upsert vectors
#   client.upsert(
#     index: 'my-index',
#     vectors: [
#       { id: 'vec1', values: [0.1, 0.2, 0.3], metadata: { text: 'Hello' } }
#     ]
#   )
#
#   # Query vectors
#   results = client.query(
#     index: 'my-index',
#     vector: [0.1, 0.2, 0.3],
#     top_k: 5
#   )
#
#   # Process results
#   results.each do |match|
#     puts "ID: #{match.id}, Score: #{match.score}"
#   end
#
# @see Vectra::Client
# @see Vectra::Configuration
#
module Vectra
  class << self
    # Register an instrumentation handler
    #
    # @yield [event] The instrumentation event
    # @see Instrumentation.on_operation
    def on_operation(&)
      Instrumentation.on_operation(&)
    end

    # Create a new client with the given options
    #
    # @param options [Hash] client options
    # @return [Client]
    def client(**options)
      Client.new(**options)
    end

    # Shortcut to create a Pinecone client
    #
    # @param api_key [String] Pinecone API key
    # @param environment [String] Pinecone environment
    # @param options [Hash] additional options
    # @return [Client]
    def pinecone(api_key:, environment: nil, host: nil, **options)
      Client.new(
        provider: :pinecone,
        api_key: api_key,
        environment: environment,
        host: host,
        **options
      )
    end

    # Shortcut to create a Qdrant client
    #
    # @param host [String] Qdrant host URL
    # @param api_key [String, nil] Qdrant API key (optional for local instances)
    # @param options [Hash] additional options
    # @return [Client]
    #
    # @example Local Qdrant (no API key)
    #   Vectra.qdrant(host: "http://localhost:6333")
    #
    # @example Qdrant Cloud
    #   Vectra.qdrant(host: "https://your-cluster.qdrant.io", api_key: ENV["QDRANT_API_KEY"])
    #
    def qdrant(host:, api_key: nil, **options)
      Client.new(
        provider: :qdrant,
        api_key: api_key,
        host: host,
        **options
      )
    end

    # Shortcut to create a Weaviate client
    #
    # @param api_key [String] Weaviate API key
    # @param host [String] Weaviate host URL
    # @param options [Hash] additional options
    # @return [Client]
    def weaviate(api_key:, host:, **options)
      Client.new(
        provider: :weaviate,
        api_key: api_key,
        host: host,
        **options
      )
    end

    # Shortcut to create a pgvector client
    #
    # @param connection_url [String] PostgreSQL connection URL (postgres://user:pass@host/db)
    # @param host [String] PostgreSQL host (alternative to connection_url)
    # @param password [String] PostgreSQL password (used with host)
    # @param options [Hash] additional options
    # @return [Client]
    #
    # @example With connection URL
    #   Vectra.pgvector(connection_url: "postgres://user:pass@localhost/mydb")
    #
    # @example With host and password
    #   Vectra.pgvector(host: "localhost", password: "secret")
    #
    def pgvector(connection_url: nil, host: nil, password: nil, **options)
      Client.new(
        provider: :pgvector,
        api_key: password,
        host: connection_url || host,
        **options
      )
    end

    # Shortcut to create a Memory client (for testing)
    #
    # @param options [Hash] additional options
    # @return [Client]
    #
    # @example In test environment
    #   Vectra.configure do |config|
    #     config.provider = :memory if Rails.env.test?
    #   end
    #
    #   client = Vectra::Client.new
    #
    def memory(**options)
      Client.new(
        provider: :memory,
        **options
      )
    end
  end
end
