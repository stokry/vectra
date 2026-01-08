# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::Cache do
  let(:cache) { described_class.new(ttl: 1, max_size: 5) }

  describe "#initialize" do
    it "sets ttl" do
      expect(cache.ttl).to eq(1)
    end

    it "sets max_size" do
      expect(cache.max_size).to eq(5)
    end
  end

  describe "#set and #get" do
    it "stores and retrieves values" do
      cache.set("key", "value")
      expect(cache.get("key")).to eq("value")
    end

    it "returns nil for missing keys" do
      expect(cache.get("missing")).to be_nil
    end

    it "expires entries after TTL" do
      cache.set("key", "value")
      sleep(1.1)
      expect(cache.get("key")).to be_nil
    end
  end

  describe "#fetch" do
    it "returns cached value if present" do
      cache.set("key", "cached")
      result = cache.fetch("key") { "computed_value" }
      expect(result).to eq("cached")
    end

    it "computes and caches value if missing" do
      computed = false
      result = cache.fetch("key") do
        computed = true
        "computed_value"
      end
      expect(result).to eq("computed_value")
      expect(computed).to be true
      expect(cache.get("key")).to eq("computed_value")
    end
  end

  describe "#delete" do
    it "removes entry from cache" do
      cache.set("key", "value")
      cache.delete("key")
      expect(cache.get("key")).to be_nil
    end
  end

  describe "#clear" do
    it "removes all entries" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.clear
      expect(cache.stats[:size]).to eq(0)
    end
  end

  describe "#exist?" do
    it "returns true for existing keys" do
      cache.set("key", "value")
      expect(cache.exist?("key")).to be true
    end

    it "returns false for missing keys" do
      expect(cache.exist?("missing")).to be false
    end

    it "returns false for expired keys" do
      cache.set("key", "value")
      sleep(1.1)
      expect(cache.exist?("key")).to be false
    end
  end

  describe "#stats" do
    it "returns cache statistics" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")

      stats = cache.stats
      expect(stats[:size]).to eq(2)
      expect(stats[:max_size]).to eq(5)
      expect(stats[:ttl]).to eq(1)
    end
  end

  describe "eviction" do
    let(:large_cache) { described_class.new(ttl: 300, max_size: 3) }

    it "evicts oldest entries when max_size exceeded" do
      # Add entries with small delays to ensure different timestamps
      4.times do |i|
        large_cache.set("key#{i}", "value#{i}")
      end

      stats = large_cache.stats
      expect(stats[:size]).to be <= 3
    end
  end
end

RSpec.describe Vectra::CachedClient do
  let(:mock_client) { instance_double(Vectra::Client) }
  let(:cache) { Vectra::Cache.new(ttl: 300, max_size: 100) }
  let(:cached_client) { described_class.new(mock_client, cache: cache) }

  let(:mock_result) do
    instance_double(Vectra::QueryResult)
  end

  let(:mock_vector) do
    instance_double(Vectra::Vector, id: "vec1", values: [0.1])
  end

  describe "#query" do
    before do
      allow(mock_client).to receive(:query).and_return(mock_result)
    end

    it "caches query results" do
      # First call hits the client
      result1 = cached_client.query(index: "test", vector: [0.1, 0.2], top_k: 10)

      # Second call returns cached
      result2 = cached_client.query(index: "test", vector: [0.1, 0.2], top_k: 10)

      expect(mock_client).to have_received(:query).once
      expect(result1).to eq(result2)
    end

    it "uses different cache keys for different parameters" do
      cached_client.query(index: "test", vector: [0.1, 0.2], top_k: 10)
      cached_client.query(index: "test", vector: [0.1, 0.2], top_k: 20)

      expect(mock_client).to have_received(:query).twice
    end
  end

  describe "#fetch" do
    before do
      allow(mock_client).to receive(:fetch).and_return({ "vec1" => mock_vector })
    end

    it "caches individual vectors" do
      # First call hits the client
      cached_client.fetch(index: "test", ids: ["vec1"])

      # Second call returns cached
      cached_client.fetch(index: "test", ids: ["vec1"])

      expect(mock_client).to have_received(:fetch).once
    end

    it "fetches only uncached ids" do
      # First call caches vec1
      cached_client.fetch(index: "test", ids: ["vec1"])

      # Second call only fetches vec2
      allow(mock_client).to receive(:fetch)
        .with(index: "test", ids: ["vec2"], namespace: nil)
        .and_return({ "vec2" => mock_vector })

      cached_client.fetch(index: "test", ids: ["vec1", "vec2"])

      expect(mock_client).to have_received(:fetch).twice
    end
  end

  describe "#invalidate_index" do
    before do
      allow(mock_client).to receive(:query).and_return(mock_result)
    end

    it "clears cache entries for the index" do
      cached_client.query(index: "test", vector: [0.1], top_k: 10)
      cached_client.invalidate_index("test")

      # Should hit client again after invalidation
      cached_client.query(index: "test", vector: [0.1], top_k: 10)

      expect(mock_client).to have_received(:query).twice
    end
  end

  describe "#clear_cache" do
    before do
      allow(mock_client).to receive(:query).and_return(mock_result)
    end

    it "clears all cache entries" do
      cached_client.query(index: "test", vector: [0.1], top_k: 10)
      cached_client.clear_cache

      expect(cache.stats[:size]).to eq(0)
    end
  end

  describe "method delegation" do
    it "delegates unknown methods to client" do
      allow(mock_client).to receive(:list_indexes).and_return([])
      cached_client.list_indexes
      expect(mock_client).to have_received(:list_indexes)
    end

    it "responds to client methods" do
      allow(mock_client).to receive(:respond_to?).with(:list_indexes, anything).and_return(true)
      expect(cached_client).to respond_to(:list_indexes)
    end
  end
end
