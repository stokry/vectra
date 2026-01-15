# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

# rubocop:disable Lint/AmbiguousBlockAssociation, Style/MultilineBlockChain
RSpec.describe Vectra::Providers::Qdrant do
  let(:config) do
    cfg = Vectra::Configuration.new
    cfg.instance_variable_set(:@provider, :qdrant)
    cfg.api_key = "test-api-key"
    cfg.host = "https://test-cluster.qdrant.io"
    cfg
  end

  let(:provider) { described_class.new(config) }
  let(:base_url) { "https://test-cluster.qdrant.io" }

  before do
    WebMock.disable_net_connect!
  end

  after do
    WebMock.reset!
  end

  describe "#provider_name" do
    it "returns :qdrant" do
      expect(provider.provider_name).to eq(:qdrant)
    end
  end

  describe "#upsert" do
    let(:vectors) do
      [
        { id: "vec1", values: [0.1, 0.2, 0.3], metadata: { text: "Hello" } },
        { id: "vec2", values: [0.4, 0.5, 0.6], metadata: { text: "World" } }
      ]
    end

    before do
      stub_request(:put, "#{base_url}/collections/test_collection/points")
        .to_return(
          status: 200,
          body: { result: { status: "completed" } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "upserts vectors and returns count" do
      result = provider.upsert(index: "test_collection", vectors: vectors)

      expect(result[:upserted_count]).to eq(2)
    end

    it "sends correct request body structure" do
      provider.upsert(index: "test_collection", vectors: vectors)

      expect(WebMock).to have_requested(:put, "#{base_url}/collections/test_collection/points")
        .with { |req|
          body = JSON.parse(req.body)
          body["points"].length == 2 &&
            body["points"][0]["vector"] == [0.1, 0.2, 0.3] &&
            body["points"][0]["payload"]["text"] == "Hello"
        }
    end

    it "includes namespace in payload when provided" do
      provider.upsert(index: "test_collection", vectors: vectors, namespace: "production")

      expect(WebMock).to have_requested(:put, "#{base_url}/collections/test_collection/points")
        .with { |req|
          body = JSON.parse(req.body)
          body["points"][0]["payload"]["_namespace"] == "production"
        }
    end

    it "includes api-key header" do
      provider.upsert(index: "test_collection", vectors: vectors)

      expect(WebMock).to have_requested(:put, "#{base_url}/collections/test_collection/points")
        .with(headers: { "api-key" => "test-api-key" })
    end
  end

  describe "#query" do
    let(:query_vector) { [0.1, 0.2, 0.3] }
    let(:search_results) do
      [
        { "id" => 123_456, "score" => 0.95, "payload" => { "text" => "Hello" }, "vector" => [0.1, 0.2, 0.3] },
        { "id" => 789_012, "score" => 0.85, "payload" => { "text" => "World" }, "vector" => [0.4, 0.5, 0.6] }
      ]
    end

    before do
      stub_request(:post, "#{base_url}/collections/test_collection/points/search")
        .to_return(
          status: 200,
          body: { result: search_results }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns QueryResult with correct structure" do
      result = provider.query(index: "test_collection", vector: query_vector, top_k: 5)

      expect(result).to be_a(Vectra::QueryResult)
      expect(result.size).to eq(2)
      expect(result.first.score).to eq(0.95)
    end

    it "parses metadata from payload" do
      result = provider.query(index: "test_collection", vector: query_vector)

      expect(result.first.metadata).to eq("text" => "Hello")
    end

    it "sends correct query parameters" do
      provider.query(index: "test_collection", vector: query_vector, top_k: 5)

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/search")
        .with { |req|
          body = JSON.parse(req.body)
          body["vector"] == [0.1, 0.2, 0.3] &&
            body["limit"] == 5 &&
            body["with_payload"] == true
        }
    end

    it "includes filter when provided" do
      provider.query(index: "test_collection", vector: query_vector, filter: { category: "tech" })

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/search")
        .with { |req|
          body = JSON.parse(req.body)
          !body["filter"].nil? && !body["filter"].empty?
        }
    end

    it "includes namespace in filter when provided" do
      provider.query(index: "test_collection", vector: query_vector, namespace: "prod")

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/search")
        .with { |req|
          body = JSON.parse(req.body)
          filter = body["filter"]
          filter && filter["must"]&.any? { |c| c["key"] == "_namespace" }
        }
    end

    it "requests vectors when include_values is true" do
      provider.query(index: "test_collection", vector: query_vector, include_values: true)

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/search")
        .with { |req|
          body = JSON.parse(req.body)
          body["with_vector"] == true
        }
    end
  end

  describe "#hybrid_search" do
    let(:query_vector) { [0.1, 0.2, 0.3] }
    let(:query_text) { "ruby programming" }
    let(:hybrid_results) do
      [
        { "id" => 123_456, "score" => 0.92, "payload" => { "text" => "Ruby guide" }, "vector" => [0.1, 0.2, 0.3] },
        { "id" => 789_012, "score" => 0.88, "payload" => { "text" => "Programming tips" }, "vector" => [0.4, 0.5, 0.6] }
      ]
    end

    before do
      stub_request(:post, "#{base_url}/collections/test_collection/points/query")
        .to_return(
          status: 200,
          body: { result: hybrid_results }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "performs hybrid search with prefetch and rescore" do
      result = provider.hybrid_search(
        index: "test_collection",
        vector: query_vector,
        text: query_text,
        alpha: 0.7,
        top_k: 5
      )

      expect(result).to be_a(Vectra::QueryResult)
      expect(result.size).to eq(2)
      expect(result.first.score).to eq(0.92)
    end

    it "includes alpha parameter in request" do
      provider.hybrid_search(
        index: "test_collection",
        vector: query_vector,
        text: query_text,
        alpha: 0.5,
        top_k: 10
      )

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/query")
        .with(body: hash_including(
          "params" => hash_including("alpha" => 0.5)
        ))
    end

    it "includes prefetch with text query" do
      provider.hybrid_search(
        index: "test_collection",
        vector: query_vector,
        text: query_text,
        alpha: 0.7,
        top_k: 5
      )

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/query")
        .with(body: hash_including(
          "prefetch" => hash_including("query" => hash_including("text" => query_text))
        ))
    end

    it "includes filter in hybrid search" do
      stub_request(:post, "#{base_url}/collections/test_collection/points/query")
        .to_return(
          status: 200,
          body: { result: hybrid_results }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      provider.hybrid_search(
        index: "test_collection",
        vector: query_vector,
        text: query_text,
        alpha: 0.7,
        top_k: 5,
        filter: { category: "tech" }
      )

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/query")
        .with { |req|
          body = JSON.parse(req.body)
          !body["prefetch"]["filter"].nil? && !body["prefetch"]["filter"].empty?
        }
    end

    it "includes namespace in hybrid search filter" do
      stub_request(:post, "#{base_url}/collections/test_collection/points/query")
        .to_return(
          status: 200,
          body: { result: hybrid_results }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      provider.hybrid_search(
        index: "test_collection",
        vector: query_vector,
        text: query_text,
        alpha: 0.7,
        top_k: 5,
        namespace: "prod"
      )

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/query")
        .with { |req|
          body = JSON.parse(req.body)
          filter = body["prefetch"]["filter"]
          filter && filter["must"]&.any? { |c| c["key"] == "_namespace" }
        }
    end

    it "includes vectors when include_values is true in hybrid search" do
      stub_request(:post, "#{base_url}/collections/test_collection/points/query")
        .to_return(
          status: 200,
          body: { result: hybrid_results }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      provider.hybrid_search(
        index: "test_collection",
        vector: query_vector,
        text: query_text,
        alpha: 0.7,
        top_k: 5,
        include_values: true
      )

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/query")
        .with { |req|
          body = JSON.parse(req.body)
          body["with_vector"] == true
        }
    end
  end

  describe "#text_search" do
    let(:query_text) { "ruby programming" }
    let(:text_results) do
      [
        { "id" => 123_456, "score" => 0.95, "payload" => { "text" => "Ruby guide" }, "vector" => [0.1, 0.2, 0.3] },
        { "id" => 789_012, "score" => 0.90, "payload" => { "text" => "Programming tips" }, "vector" => [0.4, 0.5, 0.6] }
      ]
    end

    before do
      stub_request(:post, "#{base_url}/collections/test_collection/points/query")
        .to_return(
          status: 200,
          body: { result: text_results }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "performs text search using BM25" do
      result = provider.text_search(
        index: "test_collection",
        text: query_text,
        top_k: 5
      )

      expect(result).to be_a(Vectra::QueryResult)
      expect(result.size).to eq(2)
      expect(result.first.score).to eq(0.95)
    end

    it "includes text query in request" do
      provider.text_search(
        index: "test_collection",
        text: query_text,
        top_k: 10
      )

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/query")
        .with(body: hash_including(
          "query" => hash_including("text" => query_text)
        ))
    end

    it "includes filter in text search" do
      stub_request(:post, "#{base_url}/collections/test_collection/points/query")
        .to_return(
          status: 200,
          body: { result: text_results }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      provider.text_search(
        index: "test_collection",
        text: query_text,
        top_k: 5,
        filter: { category: "tech" }
      )

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/query")
        .with { |req|
          body = JSON.parse(req.body)
          !body["filter"].nil? && !body["filter"].empty?
        }
    end
  end

  describe "#fetch" do
    let(:fetch_results) do
      [
        { "id" => 123_456, "vector" => [0.1, 0.2, 0.3], "payload" => { "text" => "Hello" } }
      ]
    end

    before do
      stub_request(:post, "#{base_url}/collections/test_collection/points")
        .to_return(
          status: 200,
          body: { result: fetch_results }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "fetches vectors by IDs and returns Hash with Vector objects" do
      result = provider.fetch(index: "test_collection", ids: ["vec1"])

      expect(result).to be_a(Hash)
      expect(result.values.first).to be_a(Vectra::Vector)
      expect(result.values.first.values).to eq([0.1, 0.2, 0.3])
    end

    it "parses metadata correctly" do
      result = provider.fetch(index: "test_collection", ids: ["vec1"])

      expect(result.values.first.metadata).to eq("text" => "Hello")
    end

    it "sends correct request with point IDs" do
      provider.fetch(index: "test_collection", ids: %w[vec1 vec2])

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points")
        .with { |req|
          body = JSON.parse(req.body)
          !body["ids"].nil? && !body["ids"].empty? &&
            body["with_vector"] == true &&
            body["with_payload"] == true
        }
    end
  end

  describe "#update" do
    before do
      stub_request(:post, "#{base_url}/collections/test_collection/points/payload")
        .to_return(
          status: 200,
          body: { result: { status: "completed" } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      stub_request(:put, "#{base_url}/collections/test_collection/points")
        .to_return(
          status: 200,
          body: { result: { status: "completed" } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "updates metadata and returns success" do
      result = provider.update(
        index: "test_collection",
        id: "vec1",
        metadata: { updated: true }
      )

      expect(result[:updated]).to be true
    end

    it "sends payload update request" do
      provider.update(index: "test_collection", id: "vec1", metadata: { key: "value" })

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/payload")
        .with { |req|
          body = JSON.parse(req.body)
          body["payload"]["key"] == "value"
        }
    end

    it "sends vector update request when values provided" do
      provider.update(index: "test_collection", id: "vec1", values: [0.1, 0.2, 0.3])

      expect(WebMock).to have_requested(:put, "#{base_url}/collections/test_collection/points")
        .with { |req|
          body = JSON.parse(req.body)
          body["points"][0]["vector"] == [0.1, 0.2, 0.3]
        }
    end

    it "includes namespace in payload when provided" do
      provider.update(index: "test_collection", id: "vec1", metadata: { key: "value" }, namespace: "prod")

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/payload")
        .with { |req|
          body = JSON.parse(req.body)
          body["payload"]["_namespace"] == "prod"
        }
    end
  end

  describe "#delete" do
    before do
      stub_request(:post, "#{base_url}/collections/test_collection/points/delete")
        .to_return(
          status: 200,
          body: { result: { status: "completed" } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "deletes by IDs and returns success" do
      result = provider.delete(index: "test_collection", ids: %w[vec1 vec2])

      expect(result[:deleted]).to be true
    end

    it "sends delete request with point IDs" do
      provider.delete(index: "test_collection", ids: %w[vec1 vec2])

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/delete")
        .with { |req|
          body = JSON.parse(req.body)
          !body["points"].nil? && !body["points"].empty?
        }
    end

    it "deletes all when delete_all is true" do
      provider.delete(index: "test_collection", delete_all: true)

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/delete")
        .with { |req|
          body = JSON.parse(req.body)
          body["filter"] == {}
        }
    end

    it "deletes by filter" do
      provider.delete(index: "test_collection", filter: { category: "old" })

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/delete")
        .with { |req|
          body = JSON.parse(req.body)
          !body["filter"].nil? && !body["filter"].empty?
        }
    end

    it "deletes by namespace" do
      provider.delete(index: "test_collection", namespace: "staging")

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/delete")
        .with { |req|
          body = JSON.parse(req.body)
          body["filter"]["must"]&.any? { |c| c["key"] == "_namespace" }
        }
    end

    it "raises ValidationError when no deletion criteria provided" do
      expect do
        provider.delete(index: "test_collection")
      end.to raise_error(Vectra::ValidationError, /Must specify/)
    end
  end

  describe "#list_indexes" do
    let(:collections_response) do
      {
        result: {
          collections: [
            { "name" => "collection1" },
            { "name" => "collection2" }
          ]
        }
      }
    end

    let(:collection_info_response) do
      {
        result: {
          status: "green",
          vectors_count: 1000,
          points_count: 1000,
          config: {
            params: {
              vectors: {
                size: 384,
                distance: "Cosine"
              }
            }
          }
        }
      }
    end

    before do
      stub_request(:get, "#{base_url}/collections")
        .to_return(
          status: 200,
          body: collections_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      stub_request(:get, %r{#{base_url}/collections/collection\d+})
        .to_return(
          status: 200,
          body: collection_info_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns array of collections" do
      result = provider.list_indexes

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
    end

    it "includes collection details" do
      result = provider.list_indexes

      expect(result.first[:dimension]).to eq(384)
      expect(result.first[:metric]).to eq("cosine")
    end
  end

  describe "#describe_index" do
    let(:collection_info) do
      {
        result: {
          status: "green",
          vectors_count: 1000,
          points_count: 1000,
          config: {
            params: {
              vectors: {
                size: 768,
                distance: "Euclid"
              }
            }
          }
        }
      }
    end

    before do
      stub_request(:get, "#{base_url}/collections/test_collection")
        .to_return(
          status: 200,
          body: collection_info.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns collection details" do
      result = provider.describe_index(index: "test_collection")

      expect(result[:name]).to eq("test_collection")
      expect(result[:dimension]).to eq(768)
      expect(result[:metric]).to eq("euclidean")
      expect(result[:status]).to eq("green")
    end

    context "when collection does not exist" do
      before do
        stub_request(:get, "#{base_url}/collections/missing")
          .to_return(
            status: 404,
            body: { status: { error: "Collection not found" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises NotFoundError" do
        expect do
          provider.describe_index(index: "missing")
        end.to raise_error(Vectra::NotFoundError)
      end
    end
  end

  describe "#stats" do
    before do
      stub_request(:get, "#{base_url}/collections/test_collection")
        .to_return(
          status: 200,
          body: {
            result: {
              status: "green",
              vectors_count: 1500,
              points_count: 1500,
              config: { params: { vectors: { size: 512, distance: "Cosine" } } }
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns statistics" do
      result = provider.stats(index: "test_collection")

      expect(result[:total_vector_count]).to eq(1500)
      expect(result[:dimension]).to eq(512)
    end
  end

  describe "#create_index" do
    before do
      stub_request(:put, "#{base_url}/collections/new_collection")
        .to_return(
          status: 200,
          body: { result: true }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      stub_request(:get, "#{base_url}/collections/new_collection")
        .to_return(
          status: 200,
          body: {
            result: {
              status: "green",
              config: { params: { vectors: { size: 384, distance: "Cosine" } } }
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "creates collection with correct configuration" do
      provider.create_index(name: "new_collection", dimension: 384)

      expect(WebMock).to have_requested(:put, "#{base_url}/collections/new_collection")
        .with { |req|
          body = JSON.parse(req.body)
          body["vectors"]["size"] == 384 &&
            body["vectors"]["distance"] == "Cosine"
        }
    end

    it "supports different metrics" do
      provider.create_index(name: "new_collection", dimension: 384, metric: "euclidean")

      expect(WebMock).to have_requested(:put, "#{base_url}/collections/new_collection")
        .with { |req|
          body = JSON.parse(req.body)
          body["vectors"]["distance"] == "Euclid"
        }
    end

    it "returns collection info after creation" do
      result = provider.create_index(name: "new_collection", dimension: 384)

      expect(result[:name]).to eq("new_collection")
      expect(result[:dimension]).to eq(384)
    end
  end

  describe "#delete_index" do
    before do
      stub_request(:delete, "#{base_url}/collections/old_collection")
        .to_return(
          status: 200,
          body: { result: true }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "deletes the collection" do
      result = provider.delete_index(name: "old_collection")

      expect(result[:deleted]).to be true
      expect(WebMock).to have_requested(:delete, "#{base_url}/collections/old_collection")
    end
  end

  describe "error handling" do
    context "with 401 unauthorized" do
      before do
        stub_request(:get, "#{base_url}/collections")
          .to_return(
            status: 401,
            body: { status: { error: "Unauthorized" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises AuthenticationError" do
        expect do
          provider.list_indexes
        end.to raise_error(Vectra::AuthenticationError)
      end
    end

    context "with 429 rate limit" do
      before do
        stub_request(:get, "#{base_url}/collections")
          .to_return(
            status: 429,
            body: { status: { error: "Rate limit exceeded" } }.to_json,
            headers: { "Content-Type" => "application/json", "Retry-After" => "60" }
          )
      end

      it "raises RateLimitError with retry_after" do
        expect do
          provider.list_indexes
        end.to raise_error(Vectra::RateLimitError) do |error|
          expect(error.retry_after).to eq(60)
        end
      end
    end

    context "with 500 server error" do
      before do
        stub_request(:get, "#{base_url}/collections")
          .to_return(
            status: 500,
            body: { status: { error: "Internal server error" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises ServerError" do
        expect do
          provider.list_indexes
        end.to raise_error(Vectra::ServerError)
      end
    end

    context "with detailed error messages" do
      before do
        stub_request(:put, "#{base_url}/collections/test/points")
          .to_return(
            status: 400,
            body: {
              status: {
                error: "Validation failed",
                details: "Vector dimension mismatch",
                errors: [
                  { field: "vectors", message: "Dimension must be 128" },
                  { field: "ids", message: "IDs must be unique" }
                ]
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "includes error details in message" do
        expect do
          provider.upsert(
            index: "test",
            vectors: [{ id: "v1", values: [0.1] * 128 }]
          )
        end.to raise_error(Vectra::ValidationError) do |error|
          expect(error.message).to include("Validation failed")
          expect(error.message).to include("Vector dimension mismatch")
          expect(error.message).to include("Fields:")
        end
      end
    end
  end

  describe "configuration validation" do
    it "raises ConfigurationError when host is not configured" do
      bad_config = Vectra::Configuration.new
      bad_config.instance_variable_set(:@provider, :qdrant)
      bad_config.api_key = "test-key"
      bad_config.host = nil

      expect do
        described_class.new(bad_config)
      end.to raise_error(Vectra::ConfigurationError, /host/i)
    end

    it "works without api_key for local Qdrant instances" do
      local_config = Vectra::Configuration.new
      local_config.instance_variable_set(:@provider, :qdrant)
      local_config.api_key = nil
      local_config.host = base_url

      stub_request(:get, "#{base_url}/collections")
        .to_return(
          status: 200,
          body: { result: { collections: [] } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      local_provider = described_class.new(local_config)
      expect { local_provider.list_indexes }.not_to raise_error
    end
  end

  describe "filter building" do
    before do
      stub_request(:post, "#{base_url}/collections/test_collection/points/search")
        .to_return(
          status: 200,
          body: { result: [] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "handles simple equality filter" do
      provider.query(index: "test_collection", vector: [0.1], filter: { category: "tech" })

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/search")
        .with { |req|
          body = JSON.parse(req.body)
          condition = body.dig("filter", "must", 0)
          condition["key"] == "category" && condition.dig("match", "value") == "tech"
        }
    end

    it "handles array filter (IN operator)" do
      provider.query(index: "test_collection", vector: [0.1], filter: { status: %w[active pending] })

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/search")
        .with { |req|
          body = JSON.parse(req.body)
          condition = body.dig("filter", "must", 0)
          condition["key"] == "status" && condition.dig("match", "any") == %w[active pending]
        }
    end

    it "handles range filters" do
      provider.query(index: "test_collection", vector: [0.1], filter: { price: { "$gt" => 100 } })

      expect(WebMock).to have_requested(:post, "#{base_url}/collections/test_collection/points/search")
        .with { |req|
          body = JSON.parse(req.body)
          condition = body.dig("filter", "must", 0)
          condition["key"] == "price" && condition.dig("range", "gt") == 100
        }
    end
  end

  describe "metric conversion" do
    before do
      stub_request(:put, %r{#{base_url}/collections/.*})
        .to_return(
          status: 200,
          body: { result: true }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      stub_request(:get, %r{#{base_url}/collections/.*})
        .to_return(
          status: 200,
          body: {
            result: { config: { params: { vectors: { size: 384, distance: "Cosine" } } } }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "converts cosine to Cosine" do
      provider.create_index(name: "test", dimension: 384, metric: "cosine")

      expect(WebMock).to have_requested(:put, "#{base_url}/collections/test")
        .with { |req| JSON.parse(req.body).dig("vectors", "distance") == "Cosine" }
    end

    it "converts euclidean to Euclid" do
      provider.create_index(name: "test", dimension: 384, metric: "euclidean")

      expect(WebMock).to have_requested(:put, "#{base_url}/collections/test")
        .with { |req| JSON.parse(req.body).dig("vectors", "distance") == "Euclid" }
    end

    it "converts dot_product to Dot" do
      provider.create_index(name: "test", dimension: 384, metric: "dot_product")

      expect(WebMock).to have_requested(:put, "#{base_url}/collections/test")
        .with { |req| JSON.parse(req.body).dig("vectors", "distance") == "Dot" }
    end
  end
end
# rubocop:enable Lint/AmbiguousBlockAssociation, Style/MultilineBlockChain
