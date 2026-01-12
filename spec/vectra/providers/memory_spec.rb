# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::Providers::Memory do
  let(:config) do
    cfg = Vectra::Configuration.new
    cfg.instance_variable_set(:@provider, :memory)
    cfg
  end

  let(:provider) { described_class.new(config) }

  describe "#provider_name" do
    it "returns :memory" do
      expect(provider.provider_name).to eq(:memory)
    end
  end

  describe "#upsert" do
    let(:vectors) do
      [
        { id: "vec1", values: [0.1, 0.2, 0.3], metadata: { text: "Hello" } },
        { id: "vec2", values: [0.4, 0.5, 0.6], metadata: { text: "World" } }
      ]
    end

    it "upserts vectors and returns count" do
      result = provider.upsert(index: "test_index", vectors: vectors)

      expect(result[:upserted_count]).to eq(2)
    end

    it "stores vectors in memory" do
      provider.upsert(index: "test_index", vectors: vectors)

      fetched = provider.fetch(index: "test_index", ids: ["vec1", "vec2"])
      expect(fetched["vec1"]).to be_a(Vectra::Vector)
      expect(fetched["vec1"].values).to eq([0.1, 0.2, 0.3])
      expect(fetched["vec1"].metadata).to eq("text" => "Hello")
    end

    it "supports namespace" do
      provider.upsert(index: "test_index", vectors: vectors, namespace: "prod")
      provider.upsert(index: "test_index", vectors: [{ id: "vec3", values: [0.7, 0.8, 0.9] }], namespace: "staging")

      prod_vectors = provider.fetch(index: "test_index", ids: ["vec1", "vec2", "vec3"], namespace: "prod")
      expect(prod_vectors.size).to eq(2)
      expect(prod_vectors.key?("vec3")).to be false

      staging_vectors = provider.fetch(index: "test_index", ids: ["vec3"], namespace: "staging")
      expect(staging_vectors.size).to eq(1)
    end

    it "infers dimension from first vector" do
      provider.upsert(index: "test_index", vectors: vectors)

      info = provider.describe_index(index: "test_index")
      expect(info[:dimension]).to eq(3)
    end
  end

  describe "#query" do
    let(:vectors) do
      [
        { id: "vec1", values: [1.0, 0.0, 0.0], metadata: { category: "tech" } },
        { id: "vec2", values: [0.0, 1.0, 0.0], metadata: { category: "news" } },
        { id: "vec3", values: [0.0, 0.0, 1.0], metadata: { category: "tech" } }
      ]
    end

    before do
      provider.upsert(index: "test_index", vectors: vectors)
    end

    it "returns QueryResult with correct structure" do
      result = provider.query(index: "test_index", vector: [1.0, 0.0, 0.0], top_k: 2)

      expect(result).to be_a(Vectra::QueryResult)
      expect(result.size).to eq(2)
      expect(result.first.id).to eq("vec1") # Most similar
      expect(result.first.score).to be > 0.9
    end

    it "sorts results by similarity score (descending)" do
      result = provider.query(index: "test_index", vector: [1.0, 0.0, 0.0], top_k: 3)

      scores = result.scores
      expect(scores).to eq(scores.sort.reverse)
    end

    it "filters by metadata" do
      result = provider.query(
        index: "test_index",
        vector: [1.0, 0.0, 0.0],
        top_k: 10,
        filter: { category: "tech" }
      )

      expect(result.size).to eq(2)
      expect(result.all? { |m| m.metadata["category"] == "tech" }).to be true
    end

    it "supports namespace filtering" do
      provider.upsert(index: "test_index", vectors: vectors, namespace: "prod")
      provider.upsert(index: "test_index", vectors: [{ id: "vec4", values: [1.0, 0.0, 0.0] }], namespace: "staging")

      result = provider.query(index: "test_index", vector: [1.0, 0.0, 0.0], top_k: 10, namespace: "prod")

      expect(result.size).to eq(3)
      expect(result.ids).not_to include("vec4")
    end

    it "includes values when requested" do
      result = provider.query(
        index: "test_index",
        vector: [1.0, 0.0, 0.0],
        top_k: 1,
        include_values: true
      )

      expect(result.first.values).to eq([1.0, 0.0, 0.0])
    end

    it "includes metadata when requested" do
      result = provider.query(
        index: "test_index",
        vector: [1.0, 0.0, 0.0],
        top_k: 1,
        include_metadata: true
      )

      expect(result.first.metadata).to eq("category" => "tech")
    end

    it "calculates cosine similarity correctly" do
      # Identical vectors should have score close to 1.0
      result = provider.query(index: "test_index", vector: [1.0, 0.0, 0.0], top_k: 1)

      expect(result.first.score).to be_within(0.01).of(1.0)
    end
  end

  describe "#fetch" do
    let(:vectors) do
      [
        { id: "vec1", values: [0.1, 0.2, 0.3], metadata: { text: "Hello" } },
        { id: "vec2", values: [0.4, 0.5, 0.6], metadata: { text: "World" } }
      ]
    end

    before do
      provider.upsert(index: "test_index", vectors: vectors)
    end

    it "fetches vectors by IDs and returns Hash with Vector objects" do
      result = provider.fetch(index: "test_index", ids: ["vec1"])

      expect(result).to be_a(Hash)
      expect(result["vec1"]).to be_a(Vectra::Vector)
      expect(result["vec1"].values).to eq([0.1, 0.2, 0.3])
      expect(result["vec1"].metadata).to eq("text" => "Hello")
    end

    it "returns empty hash for non-existent IDs" do
      result = provider.fetch(index: "test_index", ids: ["nonexistent"])

      expect(result).to be_empty
    end

    it "respects namespace" do
      provider.upsert(index: "test_index", vectors: vectors, namespace: "prod")
      provider.upsert(index: "test_index", vectors: [{ id: "vec3", values: [0.7, 0.8, 0.9] }], namespace: "staging")

      result = provider.fetch(index: "test_index", ids: ["vec1", "vec3"], namespace: "prod")

      expect(result.size).to eq(1)
      expect(result.key?("vec1")).to be true
      expect(result.key?("vec3")).to be false
    end
  end

  describe "#update" do
    let(:vectors) do
      [{ id: "vec1", values: [0.1, 0.2, 0.3], metadata: { text: "Hello" } }]
    end

    before do
      provider.upsert(index: "test_index", vectors: vectors)
    end

    it "updates metadata and returns success" do
      result = provider.update(
        index: "test_index",
        id: "vec1",
        metadata: { updated: true }
      )

      expect(result[:updated]).to be true

      fetched = provider.fetch(index: "test_index", ids: ["vec1"])
      expect(fetched["vec1"].metadata).to include("text" => "Hello", "updated" => true)
    end

    it "merges metadata instead of replacing" do
      provider.update(index: "test_index", id: "vec1", metadata: { new_key: "new_value" })

      fetched = provider.fetch(index: "test_index", ids: ["vec1"])
      expect(fetched["vec1"].metadata).to include("text" => "Hello", "new_key" => "new_value")
    end

    it "raises NotFoundError for non-existent vector" do
      expect do
        provider.update(index: "test_index", id: "nonexistent", metadata: {})
      end.to raise_error(Vectra::NotFoundError)
    end

    it "respects namespace" do
      provider.upsert(index: "test_index", vectors: vectors, namespace: "prod")

      provider.update(index: "test_index", id: "vec1", metadata: { updated: true }, namespace: "prod")

      fetched = provider.fetch(index: "test_index", ids: ["vec1"], namespace: "prod")
      expect(fetched["vec1"].metadata).to include("updated" => true)
    end
  end

  describe "#delete" do
    let(:vectors) do
      [
        { id: "vec1", values: [0.1, 0.2, 0.3], metadata: { category: "tech" } },
        { id: "vec2", values: [0.4, 0.5, 0.6], metadata: { category: "news" } },
        { id: "vec3", values: [0.7, 0.8, 0.9], metadata: { category: "tech" } }
      ]
    end

    before do
      provider.upsert(index: "test_index", vectors: vectors)
    end

    it "deletes by IDs and returns success" do
      result = provider.delete(index: "test_index", ids: ["vec1", "vec2"])

      expect(result[:deleted]).to be true

      fetched = provider.fetch(index: "test_index", ids: ["vec1", "vec2", "vec3"])
      expect(fetched.size).to eq(1)
      expect(fetched.key?("vec3")).to be true
    end

    it "deletes all when delete_all is true" do
      provider.delete(index: "test_index", delete_all: true)

      fetched = provider.fetch(index: "test_index", ids: ["vec1", "vec2", "vec3"])
      expect(fetched).to be_empty
    end

    it "deletes by filter" do
      provider.delete(index: "test_index", filter: { category: "tech" })

      fetched = provider.fetch(index: "test_index", ids: ["vec1", "vec2", "vec3"])
      expect(fetched.size).to eq(1)
      expect(fetched.key?("vec2")).to be true
    end

    it "deletes by namespace" do
      provider.upsert(index: "test_index", vectors: vectors, namespace: "prod")
      provider.upsert(index: "test_index", vectors: [{ id: "vec4", values: [1.0, 1.0, 1.0] }], namespace: "staging")

      provider.delete(index: "test_index", namespace: "prod")

      prod_fetched = provider.fetch(index: "test_index", ids: ["vec1", "vec2", "vec3"], namespace: "prod")
      staging_fetched = provider.fetch(index: "test_index", ids: ["vec4"], namespace: "staging")

      expect(prod_fetched).to be_empty
      expect(staging_fetched.size).to eq(1)
    end

    it "raises ValidationError when no deletion criteria provided" do
      expect do
        provider.delete(index: "test_index")
      end.to raise_error(Vectra::ValidationError, /Must specify/)
    end
  end

  describe "#list_indexes" do
    before do
      provider.upsert(index: "index1", vectors: [{ id: "v1", values: [0.1, 0.2] }])
      provider.upsert(index: "index2", vectors: [{ id: "v2", values: [0.3, 0.4, 0.5] }])
    end

    it "returns array of indexes" do
      result = provider.list_indexes

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.map { |i| i[:name] }).to contain_exactly("index1", "index2")
    end

    it "includes index details" do
      result = provider.list_indexes

      index1 = result.find { |i| i[:name] == "index1" }
      expect(index1[:dimension]).to eq(2)
      expect(index1[:status]).to eq("ready")
    end
  end

  describe "#describe_index" do
    before do
      provider.upsert(index: "test_index", vectors: [{ id: "v1", values: [0.1, 0.2, 0.3] }])
    end

    it "returns index details" do
      result = provider.describe_index(index: "test_index")

      expect(result[:name]).to eq("test_index")
      expect(result[:dimension]).to eq(3)
      expect(result[:metric]).to eq("cosine")
      expect(result[:status]).to eq("ready")
    end

    it "raises NotFoundError for non-existent index" do
      expect do
        provider.describe_index(index: "nonexistent")
      end.to raise_error(Vectra::NotFoundError)
    end
  end

  describe "#stats" do
    before do
      provider.upsert(index: "test_index", vectors: [
                        { id: "v1", values: [0.1, 0.2] },
                        { id: "v2", values: [0.3, 0.4] }
                      ], namespace: "prod")

      provider.upsert(index: "test_index", vectors: [
                        { id: "v3", values: [0.5, 0.6] }
                      ], namespace: "staging")
    end

    it "returns statistics for all namespaces" do
      result = provider.stats(index: "test_index")

      expect(result[:total_vector_count]).to eq(3)
      expect(result[:dimension]).to eq(2)
      expect(result[:namespaces].keys).to contain_exactly("prod", "staging")
      expect(result[:namespaces]["prod"][:vector_count]).to eq(2)
      expect(result[:namespaces]["staging"][:vector_count]).to eq(1)
    end

    it "returns statistics for specific namespace" do
      result = provider.stats(index: "test_index", namespace: "prod")

      expect(result[:total_vector_count]).to eq(2)
      expect(result[:namespaces].keys).to eq(["prod"])
    end

    it "raises NotFoundError for non-existent index" do
      expect do
        provider.stats(index: "nonexistent")
      end.to raise_error(Vectra::NotFoundError)
    end
  end

  describe "#clear!" do
    it "clears all stored data" do
      provider.upsert(index: "test_index", vectors: [{ id: "v1", values: [0.1, 0.2] }])

      provider.clear!

      expect(provider.list_indexes).to be_empty
      expect(provider.fetch(index: "test_index", ids: ["v1"])).to be_empty
    end
  end

  describe "filter operators" do
    before do
      provider.upsert(index: "test_index", vectors: [
                        { id: "v1", values: [0.1, 0.2], metadata: { price: 10, status: "active" } },
                        { id: "v2", values: [0.3, 0.4], metadata: { price: 20, status: "inactive" } },
                        { id: "v3", values: [0.5, 0.6], metadata: { price: 30, status: "active" } }
                      ])
    end

    it "supports $gt operator" do
      result = provider.query(
        index: "test_index",
        vector: [0.1, 0.2],
        top_k: 10,
        filter: { price: { "$gt" => 15 } }
      )

      expect(result.ids).to contain_exactly("v2", "v3")
    end

    it "supports $gte operator" do
      result = provider.query(
        index: "test_index",
        vector: [0.1, 0.2],
        top_k: 10,
        filter: { price: { "$gte" => 20 } }
      )

      expect(result.ids).to contain_exactly("v2", "v3")
    end

    it "supports $lt operator" do
      result = provider.query(
        index: "test_index",
        vector: [0.1, 0.2],
        top_k: 10,
        filter: { price: { "$lt" => 25 } }
      )

      expect(result.ids).to contain_exactly("v1", "v2")
    end

    it "supports $lte operator" do
      result = provider.query(
        index: "test_index",
        vector: [0.1, 0.2],
        top_k: 10,
        filter: { price: { "$lte" => 20 } }
      )

      expect(result.ids).to contain_exactly("v1", "v2")
    end

    it "supports $in operator" do
      result = provider.query(
        index: "test_index",
        vector: [0.1, 0.2],
        top_k: 10,
        filter: { status: ["active", "pending"] }
      )

      expect(result.ids).to contain_exactly("v1", "v3")
    end
  end

  describe "configuration" do
    it "does not require host or API key" do
      minimal_config = Vectra::Configuration.new
      minimal_config.instance_variable_set(:@provider, :memory)

      expect { described_class.new(minimal_config) }.not_to raise_error
    end
  end
end
