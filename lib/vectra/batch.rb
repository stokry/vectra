# frozen_string_literal: true

require "concurrent"

module Vectra
  # Batch operations with concurrent processing
  #
  # Provides async batch upsert capabilities with configurable concurrency
  # and automatic chunking of large vector sets.
  #
  # @example Async batch upsert
  #   batch = Vectra::Batch.new(client, concurrency: 4)
  #   result = batch.upsert_async(
  #     index: 'my-index',
  #     vectors: large_vector_array,
  #     chunk_size: 100
  #   )
  #   puts "Upserted: #{result[:upserted_count]}"
  #
  # @example With progress tracking
  #   batch.upsert_async(
  #     index: 'docs',
  #     vectors: large_array,
  #     on_progress: ->(stats) {
  #       puts "Progress: #{stats[:percentage]}% (#{stats[:processed]}/#{stats[:total]})"
  #       puts "  Chunk #{stats[:current_chunk] + 1}/#{stats[:total_chunks]}"
  #       puts "  Success: #{stats[:success_count]}, Failed: #{stats[:failed_count]}"
  #     }
  #   )
  #
  class Batch
    DEFAULT_CONCURRENCY = 4
    DEFAULT_CHUNK_SIZE = 100

    attr_reader :client, :concurrency

    # Initialize a new Batch processor
    #
    # @param client [Client] the Vectra client
    # @param concurrency [Integer] max concurrent requests (default: 4)
    def initialize(client, concurrency: DEFAULT_CONCURRENCY)
      @client = client
      @concurrency = [concurrency, 1].max
    end

    # Perform async batch upsert with concurrent requests
    #
    # @param index [String] the index name
    # @param vectors [Array<Hash>] vectors to upsert
    # @param namespace [String, nil] optional namespace
    # @param chunk_size [Integer] vectors per chunk (default: 100)
    # @param on_progress [Proc, nil] optional callback called after each chunk completes
    #   Callback receives hash with: processed, total, percentage, current_chunk, total_chunks, success_count, failed_count
    # @return [Hash] aggregated result with :upserted_count, :chunks, :errors
    #
    # @example With progress callback
    #   batch.upsert_async(
    #     index: 'docs',
    #     vectors: large_array,
    #     on_progress: ->(stats) {
    #       puts "Progress: #{stats[:percentage]}% (#{stats[:processed]}/#{stats[:total]})"
    #     }
    #   )
    def upsert_async(index:, vectors:, namespace: nil, chunk_size: DEFAULT_CHUNK_SIZE, on_progress: nil)
      chunks = vectors.each_slice(chunk_size).to_a
      return { upserted_count: 0, chunks: 0, errors: [] } if chunks.empty?

      results = process_chunks_concurrently(chunks, total_items: vectors.size, on_progress: on_progress) do |chunk|
        client.upsert(index: index, vectors: chunk, namespace: namespace)
      end

      aggregate_results(results, vectors.size)
    end

    # Perform async batch delete with concurrent requests
    #
    # @param index [String] the index name
    # @param ids [Array<String>] IDs to delete
    # @param namespace [String, nil] optional namespace
    # @param chunk_size [Integer] IDs per chunk (default: 100)
    # @param on_progress [Proc, nil] optional callback called after each chunk completes
    #   Callback receives hash with: processed, total, percentage, current_chunk, total_chunks, success_count, failed_count
    # @return [Hash] aggregated result
    def delete_async(index:, ids:, namespace: nil, chunk_size: DEFAULT_CHUNK_SIZE, on_progress: nil)
      chunks = ids.each_slice(chunk_size).to_a
      return { deleted_count: 0, chunks: 0, errors: [] } if chunks.empty?

      results = process_chunks_concurrently(chunks, total_items: ids.size, on_progress: on_progress) do |chunk|
        client.delete(index: index, ids: chunk, namespace: namespace)
      end

      aggregate_delete_results(results, ids.size)
    end

    # Perform async batch fetch with concurrent requests
    #
    # @param index [String] the index name
    # @param ids [Array<String>] IDs to fetch
    # @param namespace [String, nil] optional namespace
    # @param chunk_size [Integer] IDs per chunk (default: 100)
    # @param on_progress [Proc, nil] optional callback called after each chunk completes
    #   Callback receives hash with: processed, total, percentage, current_chunk, total_chunks, success_count, failed_count
    # @return [Hash<String, Vector>] merged results
    def fetch_async(index:, ids:, namespace: nil, chunk_size: DEFAULT_CHUNK_SIZE, on_progress: nil)
      chunks = ids.each_slice(chunk_size).to_a
      return {} if chunks.empty?

      results = process_chunks_concurrently(chunks, total_items: ids.size, on_progress: on_progress) do |chunk|
        client.fetch(index: index, ids: chunk, namespace: namespace)
      end

      merge_fetch_results(results)
    end

    private

    def process_chunks_concurrently(chunks, total_items: nil, on_progress: nil)
      pool = Concurrent::FixedThreadPool.new(concurrency)
      futures = []
      progress_mutex = Mutex.new
      completed_count = Concurrent::AtomicFixnum.new(0)
      success_count = Concurrent::AtomicFixnum.new(0)
      failed_count = Concurrent::AtomicFixnum.new(0)

      chunks.each_with_index do |chunk, index|
        futures << Concurrent::Future.execute(executor: pool) do
          result = yield(chunk)
          success_count.increment
          { index: index, result: result, error: nil }
        rescue StandardError => e
          failed_count.increment
          { index: index, result: nil, error: e }
        ensure
          # Call progress callback when chunk completes
          if on_progress
            completed = completed_count.increment
            processed = [completed * (chunks.first.size), total_items || chunks.size * chunks.first.size].min
            percentage = total_items ? (processed.to_f / total_items * 100).round(2) : (completed.to_f / chunks.size * 100).round(2)

            progress_mutex.synchronize do
              on_progress.call(
                processed: processed,
                total: total_items || chunks.size * chunks.first.size,
                percentage: percentage,
                current_chunk: completed - 1,
                total_chunks: chunks.size,
                success_count: success_count.value,
                failed_count: failed_count.value
              )
            end
          end
        end
      end

      # Wait for all futures and collect results
      results = futures.map(&:value)
      pool.shutdown
      pool.wait_for_termination(30)

      results.sort_by { |r| r[:index] }
    end

    def aggregate_results(results, total_vectors)
      errors = results.select { |r| r[:error] }.map { |r| r[:error] }
      successful = results.reject { |r| r[:error] }
      upserted = successful.sum { |r| r.dig(:result, :upserted_count) || 0 }

      {
        upserted_count: upserted,
        total_vectors: total_vectors,
        chunks: results.size,
        successful_chunks: successful.size,
        errors: errors
      }
    end

    def aggregate_delete_results(results, total_ids)
      errors = results.select { |r| r[:error] }.map { |r| r[:error] }
      successful = results.reject { |r| r[:error] }

      {
        deleted_count: total_ids - (errors.size * (total_ids / results.size.to_f).ceil),
        total_ids: total_ids,
        chunks: results.size,
        successful_chunks: successful.size,
        errors: errors
      }
    end

    def merge_fetch_results(results)
      merged = {}
      results.each do |r|
        next if r[:error] || r[:result].nil?

        merged.merge!(r[:result])
      end
      merged
    end
  end
end
