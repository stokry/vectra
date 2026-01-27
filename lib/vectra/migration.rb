# frozen_string_literal: true

require_relative "batch"
require_relative "streaming"
require_relative "providers/memory"

module Vectra
  # Bulk migration tool for copying vectors between providers
  #
  # Provides utilities for migrating vectors from one provider to another,
  # using existing scan_all streaming and upsert_async batch operations.
  #
  # @example Migrate from Memory to Qdrant
  #   source_client = Vectra::Client.new(provider: :memory)
  #   target_client = Vectra::Client.new(provider: :qdrant, host: "http://localhost:6333")
  #
  #   migration = Vectra::Migration.new(source_client, target_client)
  #   result = migration.migrate(
  #     source_index: 'old-index',
  #     target_index: 'new-index',
  #     source_namespace: 'ns1',
  #     target_namespace: 'ns2'
  #   )
  #   puts "Migrated #{result[:migrated_count]} vectors"
  #
  # @example With progress tracking
  #   migration.migrate(
  #     source_index: 'products',
  #     target_index: 'products',
  #     on_progress: ->(stats) {
  #       puts "Progress: #{stats[:percentage]}% (#{stats[:migrated]}/#{stats[:total]})"
  #     }
  #   )
  #
  # @example Migrate with batch size control
  #   migration.migrate(
  #     source_index: 'large-index',
  #     target_index: 'large-index',
  #     batch_size: 500,
  #     chunk_size: 100
  #   )
  #
  class Migration
    DEFAULT_BATCH_SIZE = 1000
    DEFAULT_CHUNK_SIZE = 100

    attr_reader :source_client, :target_client

    # Initialize a migration tool
    #
    # @param source_client [Client] Source provider client
    # @param target_client [Client] Target provider client
    def initialize(source_client, target_client)
      @source_client = source_client
      @target_client = target_client
      validate_clients!
    end

    # Migrate vectors from source to target
    #
    # @param source_index [String] Source index name
    # @param target_index [String] Target index name
    # @param source_namespace [String, nil] Source namespace (optional)
    # @param target_namespace [String, nil] Target namespace (optional)
    # @param batch_size [Integer] Vectors per batch for fetching (default: 1000)
    # @param chunk_size [Integer] Vectors per chunk for upsert (default: 100)
    # @param on_progress [Proc, nil] Progress callback
    #   Receives hash with: migrated, total, percentage, batches_processed, total_batches
    # @return [Hash] Migration result with :migrated_count, :batches, :errors
    #
    # @raise [ArgumentError] If source or target client is invalid
    def migrate(source_index:, target_index:, source_namespace: nil, target_namespace: nil,
                batch_size: DEFAULT_BATCH_SIZE, chunk_size: DEFAULT_CHUNK_SIZE, on_progress: nil)
      migrated_count = 0
      batches_processed = 0
      errors = []
      total_vectors = estimate_total(source_index, source_namespace)

      # Use streaming to fetch all vectors in batches
      fetch_all_vectors(
        index: source_index,
        namespace: source_namespace,
        batch_size: batch_size
      ) do |vectors_batch|
        begin
          # Upsert batch to target using Batch.upsert_async
          batch = Batch.new(@target_client)
          result = batch.upsert_async(
            index: target_index,
            vectors: vectors_batch,
            namespace: target_namespace,
            chunk_size: chunk_size
          )

          migrated_count += result[:upserted_count]
          batches_processed += 1

          # Report progress
          if on_progress
            percentage = total_vectors.positive? ? (migrated_count.to_f / total_vectors * 100).round(2) : 0
            on_progress.call(
              migrated: migrated_count,
              total: total_vectors,
              percentage: percentage,
              batches_processed: batches_processed,
              total_batches: (total_vectors.to_f / batch_size).ceil
            )
          end

          # Collect errors
          errors.concat(result[:errors]) if result[:errors]&.any?
        rescue StandardError => e
          errors << e
          # Continue with next batch
        end
      end

      {
        migrated_count: migrated_count,
        total_vectors: total_vectors,
        batches: batches_processed,
        errors: errors
      }
    end

    # Verify migration by comparing vector counts
    #
    # @param source_index [String] Source index name
    # @param target_index [String] Target index name
    # @param source_namespace [String, nil] Source namespace
    # @param target_namespace [String, nil] Target namespace
    # @return [Hash] Verification result with :source_count, :target_count, :match
    def verify(source_index:, target_index:, source_namespace: nil, target_namespace: nil)
      source_stats = @source_client.stats(index: source_index, namespace: source_namespace)
      target_stats = @target_client.stats(index: target_index, namespace: target_namespace)

      source_count = source_stats[:total_vector_count] || 0
      target_count = target_stats[:total_vector_count] || 0

      {
        source_count: source_count,
        target_count: target_count,
        match: source_count == target_count
      }
    end

    private

    def validate_clients!
      raise ArgumentError, "Source client cannot be nil" if @source_client.nil?
      raise ArgumentError, "Target client cannot be nil" if @target_client.nil?
    end

    def estimate_total(index, namespace)
      stats = @source_client.stats(index: index, namespace: namespace)
      stats[:total_vector_count] || 0
    rescue StandardError
      # If stats fail, we'll still migrate but won't have accurate progress
      0
    end

    def fetch_all_vectors(index:, namespace: nil, batch_size: DEFAULT_BATCH_SIZE)
      return unless block_given?

      # Strategy 1: Try to get all IDs using provider-specific methods
      all_ids = fetch_all_ids(index: index, namespace: namespace)

      if all_ids.any?
        # Fetch in batches using IDs
        all_ids.each_slice(batch_size) do |id_batch|
          vectors = fetch_vectors_batch(index: index, ids: id_batch, namespace: namespace)
          yield vectors if vectors.any?
        end
      else
        # Strategy 2: Use query with large top_k to get all vectors
        # This works for most providers but may be inefficient for very large indexes
        stream_vectors_via_query(index: index, namespace: namespace, batch_size: batch_size) do |vectors|
          yield vectors if vectors.any?
        end
      end
    end

    def fetch_all_ids(index:, namespace: nil)
      # Try provider-specific methods to get all IDs
      provider = @source_client.instance_variable_get(:@provider)

      # Memory provider: access storage directly
      if provider.is_a?(Providers::Memory)
        ns = namespace || ""
        storage = provider.instance_variable_get(:@storage)
        return storage[index][ns].keys if storage[index] && storage[index][ns]
      end

      # For other providers, we'd need provider-specific scan methods
      # For now, return empty array to fall back to query-based approach
      []
    rescue StandardError
      []
    end

    def fetch_vectors_batch(index:, ids:, namespace: nil)
      result = @source_client.fetch(index: index, ids: ids, namespace: namespace)
      # Convert fetch result (Hash) to array of vector hashes
      result.map do |id, vector|
        {
          id: id,
          values: vector.values,
          metadata: vector.metadata
        }
      end
    rescue StandardError
      []
    end

    def stream_vectors_via_query(index:, namespace: nil, batch_size: DEFAULT_BATCH_SIZE)
      # Use query with a dummy vector to get all results
      # This is a workaround for providers that don't support efficient scanning
      begin
        stats = @source_client.stats(index: index, namespace: namespace)
        total = stats[:total_vector_count] || 0
      rescue Vectra::NotFoundError
        # Index doesn't exist, return empty
        return
      end

      return if total.zero?

      # Get index dimension for dummy query vector
      begin
        index_info = @source_client.describe_index(index: index)
        dimension = index_info[:dimension] || 1536
      rescue Vectra::NotFoundError
        # Index doesn't exist, return empty
        return
      end

      # Create a dummy query vector (all zeros)
      dummy_vector = Array.new(dimension, 0.0)

      # Query with large top_k to get all vectors
      # Note: Some providers may limit top_k, so we may need multiple queries
      max_top_k = [total, 10_000].min # Reasonable limit
      result = @source_client.query(
        index: index,
        vector: dummy_vector,
        top_k: max_top_k,
        namespace: namespace,
        include_values: true,
        include_metadata: true
      )

      # Convert query results to vector format
      vectors = result.map do |match|
        {
          id: match.id,
          values: match.values || [],
          metadata: match.metadata || {}
        }
      end

      yield vectors if vectors.any?
    end
  end
end
