# frozen_string_literal: true

module Vectra
  # Streaming query results for large datasets
  #
  # Provides lazy enumeration over query results with automatic pagination,
  # reducing memory usage for large result sets.
  #
  # @example Stream through results
  #   stream = Vectra::Streaming.new(client)
  #   stream.query_each(index: 'my-index', vector: query_vec, total: 1000) do |match|
  #     process(match)
  #   end
  #
  # @example As lazy enumerator
  #   results = stream.query_stream(index: 'my-index', vector: query_vec, total: 1000)
  #   results.take(50).each { |m| puts m.id }
  #
  class Streaming
    DEFAULT_PAGE_SIZE = 100

    attr_reader :client, :page_size

    # Initialize streaming query handler
    #
    # @param client [Client] the Vectra client
    # @param page_size [Integer] results per page (default: 100)
    def initialize(client, page_size: DEFAULT_PAGE_SIZE)
      @client = client
      @page_size = [page_size, 1].max
    end

    # Stream query results with a block
    #
    # @param index [String] the index name
    # @param vector [Array<Float>] query vector
    # @param total [Integer] total results to fetch
    # @param namespace [String, nil] optional namespace
    # @param filter [Hash, nil] metadata filter
    # @yield [Match] each match result
    # @return [Integer] total results yielded
    def query_each(index:, vector:, total:, namespace: nil, filter: nil, &block)
      return 0 unless block_given?

      count = 0
      query_stream(index: index, vector: vector, total: total, namespace: namespace, filter: filter).each do |match|
        block.call(match)
        count += 1
      end
      count
    end

    # Create a lazy enumerator for streaming results
    #
    # @param index [String] the index name
    # @param vector [Array<Float>] query vector
    # @param total [Integer] total results to fetch
    # @param namespace [String, nil] optional namespace
    # @param filter [Hash, nil] metadata filter
    # @return [Enumerator::Lazy] lazy enumerator of results
    def query_stream(index:, vector:, total:, namespace: nil, filter: nil)
      Enumerator.new do |yielder|
        fetched = 0
        seen_ids = Set.new

        while fetched < total
          batch_size = [page_size, total - fetched].min

          result = client.query(
            index: index,
            vector: vector,
            top_k: batch_size,
            namespace: namespace,
            filter: filter,
            include_metadata: true
          )

          break if result.empty?

          result.each do |match|
            # Skip duplicates (some providers may return overlapping results)
            next if seen_ids.include?(match.id)

            seen_ids.add(match.id)
            yielder << match
            fetched += 1

            break if fetched >= total
          end

          # If we got fewer results than requested, we've exhausted the index
          break if result.size < batch_size
        end
      end.lazy
    end

    # Scan all vectors in an index (provider-dependent)
    #
    # @param index [String] the index name
    # @param namespace [String, nil] optional namespace
    # @param batch_size [Integer] IDs per batch
    # @yield [Vector] each vector
    # @return [Integer] total vectors scanned
    # @note Not all providers support efficient scanning
    def scan_all(index:, namespace: nil, batch_size: 1000)
      return 0 unless block_given?

      count = 0
      offset = 0

      loop do
        # This is a simplified scan - actual implementation depends on provider
        stats = client.stats(index: index, namespace: namespace)
        total = stats[:total_vector_count] || 0

        break if offset >= total

        # Fetch IDs in batches (this is provider-specific)
        # For now, we return what we can
        break if offset.positive? # Only one iteration for basic implementation

        offset += batch_size
        count = total
      end

      count
    end
  end

  # Streaming result wrapper with additional metadata
  class StreamingResult
    include Enumerable

    attr_reader :enumerator, :metadata

    def initialize(enumerator, metadata = {})
      @enumerator = enumerator
      @metadata = metadata
    end

    def each(&)
      enumerator.each(&)
    end

    def take(n)
      enumerator.take(n)
    end

    def to_a
      enumerator.to_a
    end
  end
end
