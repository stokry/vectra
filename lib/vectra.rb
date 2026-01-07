# frozen_string_literal: true

require_relative "vectra/version"
require_relative "vectra/errors"
require_relative "vectra/configuration"
require_relative "vectra/vector"
require_relative "vectra/query_result"
require_relative "vectra/providers/base"
require_relative "vectra/providers/pinecone"
require_relative "vectra/providers/qdrant"
require_relative "vectra/providers/weaviate"
require_relative "vectra/providers/pgvector"
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
    # @param api_key [String] Qdrant API key
    # @param host [String] Qdrant host URL
    # @param options [Hash] additional options
    # @return [Client]
    def qdrant(api_key:, host:, **options)
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
  end
end
