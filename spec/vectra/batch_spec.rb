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
  end
end
