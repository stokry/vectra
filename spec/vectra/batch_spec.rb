# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::Batch do
  let(:config) do
    cfg = Vectra::Configuration.new
    cfg.instance_variable_set(:@provider, :pinecone)
    cfg.api_key = "test-key"
    cfg.host = "https://test.pinecone.io"
    cfg
  end

  let(:mock_provider) { instance_double(Vectra::Providers::Pinecone) }
  let(:client) { instance_double(Vectra::Client, provider: mock_provider, config: config) }
  let(:batch) { described_class.new(client, concurrency: 2) }

  describe "#initialize" do
    it "sets concurrency" do
      expect(batch.concurrency).to eq(2)
    end

    it "defaults to minimum of 1 concurrency" do
      batch = described_class.new(client, concurrency: 0)
      expect(batch.concurrency).to eq(1)
    end
  end

  describe "#upsert_async" do
    let(:vectors) do
      10.times.map do |i|
        { id: "vec_#{i}", values: [0.1, 0.2, 0.3], metadata: { index: i } }
      end
    end

    before do
      allow(client).to receive(:upsert).and_return({ upserted_count: 3 })
    end

    it "splits vectors into chunks and processes concurrently" do
      result = batch.upsert_async(index: "test", vectors: vectors, chunk_size: 3)

      expect(result[:upserted_count]).to be_positive
      expect(result[:chunks]).to eq(4) # 10 vectors / 3 chunk_size = 4 chunks
    end

    it "returns empty result for empty vectors" do
      result = batch.upsert_async(index: "test", vectors: [], chunk_size: 3)

      expect(result[:upserted_count]).to eq(0)
      expect(result[:chunks]).to eq(0)
    end

    it "handles errors gracefully" do
      call_count = 0
      allow(client).to receive(:upsert) do
        call_count += 1

        raise StandardError, "Test error" if call_count == 2

        { upserted_count: 3 }
      end

      result = batch.upsert_async(index: "test", vectors: vectors, chunk_size: 3)

      expect(result[:errors]).not_to be_empty
      expect(result[:successful_chunks]).to be < result[:chunks]
    end

    it "calls on_progress callback after each chunk completes" do
      progress_calls = []
      progress_callback = proc do |stats|
        progress_calls << stats
      end

      batch.upsert_async(
        index: "test",
        vectors: vectors,
        chunk_size: 3,
        on_progress: progress_callback
      )

      expect(progress_calls.size).to eq(4) # 4 chunks
      expect(progress_calls.first).to include(:processed, :total, :percentage, :current_chunk, :total_chunks, :success_count, :failed_count)
      expect(progress_calls.first[:total_chunks]).to eq(4)
      expect(progress_calls.first[:total]).to eq(10)
      expect(progress_calls.last[:percentage]).to be >= 90.0
    end

    it "tracks success and failed counts in progress callback" do
      call_count = 0
      allow(client).to receive(:upsert) do
        call_count += 1
        raise StandardError, "Test error" if call_count == 2

        { upserted_count: 3 }
      end

      progress_calls = []
      progress_callback = proc do |stats|
        progress_calls << stats
      end

      batch.upsert_async(
        index: "test",
        vectors: vectors,
        chunk_size: 3,
        on_progress: progress_callback
      )

      # Last progress call should reflect final state
      final_stats = progress_calls.last
      expect(final_stats[:success_count]).to be > 0
      expect(final_stats[:failed_count]).to eq(1)
    end
  end

  describe "#delete_async" do
    let(:ids) { 10.times.map { |i| "id_#{i}" } }

    before do
      allow(client).to receive(:delete).and_return({ deleted: true })
    end

    it "splits ids into chunks and processes concurrently" do
      result = batch.delete_async(index: "test", ids: ids, chunk_size: 3)

      expect(result[:chunks]).to eq(4)
      expect(result[:successful_chunks]).to be_positive
    end

    it "returns empty result for empty ids" do
      result = batch.delete_async(index: "test", ids: [], chunk_size: 3)

      expect(result[:chunks]).to eq(0)
    end

    it "calls on_progress callback for delete operations" do
      progress_calls = []
      progress_callback = proc { |stats| progress_calls << stats }

      batch.delete_async(
        index: "test",
        ids: ids,
        chunk_size: 3,
        on_progress: progress_callback
      )

      expect(progress_calls.size).to eq(4) # 4 chunks
      expect(progress_calls.first[:total_chunks]).to eq(4)
    end
  end

  describe "#fetch_async" do
    let(:ids) { 6.times.map { |i| "id_#{i}" } }
    let(:mock_vector) { instance_double(Vectra::Vector, id: "test") }

    before do
      allow(client).to receive(:fetch).and_return(
        ids.to_h { |id| [id, mock_vector] }
      )
    end

    it "merges results from concurrent fetches" do
      result = batch.fetch_async(index: "test", ids: ids, chunk_size: 2)

      expect(result.keys.size).to eq(6)
    end

    it "returns empty hash for empty ids" do
      result = batch.fetch_async(index: "test", ids: [], chunk_size: 2)

      expect(result).to eq({})
    end

    it "calls on_progress callback for fetch operations" do
      progress_calls = []
      progress_callback = proc { |stats| progress_calls << stats }

      batch.fetch_async(
        index: "test",
        ids: ids,
        chunk_size: 2,
        on_progress: progress_callback
      )

      expect(progress_calls.size).to eq(3) # 6 ids / 2 chunk_size = 3 chunks
      expect(progress_calls.first[:total_chunks]).to eq(3)
    end
  end

  describe "#query_async" do
    let(:query_vectors) do
      5.times.map { |i| [0.1 * i, 0.2 * i, 0.3 * i] }
    end

    let(:mock_query_result) do
      matches = [
        double(id: "vec-1", score: 0.95),
        double(id: "vec-2", score: 0.85)
      ]
      instance_double(Vectra::QueryResult, matches: matches, empty?: false)
    end

    before do
      allow(client).to receive(:query).and_return(mock_query_result)
    end

    it "queries multiple vectors concurrently" do
      results = batch.query_async(
        index: "test",
        vectors: query_vectors,
        top_k: 5,
        chunk_size: 2
      )

      expect(results.size).to eq(5)
      expect(client).to have_received(:query).exactly(5).times
    end

    it "returns empty array for empty vectors" do
      results = batch.query_async(index: "test", vectors: [], chunk_size: 2)

      expect(results).to eq([])
      expect(client).not_to have_received(:query)
    end

    it "calls progress callback" do
      progress_calls = []
      progress_callback = ->(stats) { progress_calls << stats }

      batch.query_async(
        index: "test",
        vectors: query_vectors,
        chunk_size: 2,
        on_progress: progress_callback
      )

      expect(progress_calls.size).to be_positive
      expect(progress_calls.first).to include(:processed, :total, :percentage)
    end

    it "handles errors gracefully" do
      allow(client).to receive(:query).and_raise(StandardError.new("Query failed"))

      results = batch.query_async(
        index: "test",
        vectors: query_vectors,
        chunk_size: 2
      )

      # Should return empty QueryResults for failed queries
      expect(results.size).to eq(5)
      expect(results).to all(be_a(Vectra::QueryResult))
    end
  end
end
