# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe Vectra::Providers::Weaviate do
  let(:config) do
    cfg = Vectra::Configuration.new
    cfg.instance_variable_set(:@provider, :weaviate)
    cfg.api_key = "test-api-key"
    cfg.host = "http://localhost:8080"
    cfg
  end

  let(:provider) { described_class.new(config) }
  let(:base_url) { "http://localhost:8080" }

  before do
    WebMock.disable_net_connect!
  end

  after do
    WebMock.reset!
  end

  describe "#provider_name" do
    it "returns :weaviate" do
      expect(provider.provider_name).to eq(:weaviate)
    end
  end

  describe "#upsert" do
    let(:vectors) do
      [
        { id: "doc-1", values: [0.1, 0.2, 0.3], metadata: { category: "news" } },
        { id: "doc-2", values: [0.4, 0.5, 0.6], metadata: { category: "blog" } }
      ]
    end

    before do
      stub_request(:post, "#{base_url}/v1/batch/objects")
        .to_return(
          status: 200,
          body: { objects: [{}, {}] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "upserts vectors and returns count" do
      result = provider.upsert(index: "Document", vectors: vectors)

      expect(result[:upserted_count]).to eq(2)
      expect(WebMock).to have_requested(:post, "#{base_url}/v1/batch/objects")
    end

    it "sends correct request body structure including namespace" do
      provider.upsert(index: "Document", vectors: vectors, namespace: "production")

      expect(WebMock).to have_requested(:post, "#{base_url}/v1/batch/objects")
        .with { |req|
          body = JSON.parse(req.body)
          objs = body["objects"]
          objs.length == 2 &&
            objs[0]["class"] == "Document" &&
            objs[0]["id"] == "doc-1" &&
            objs[0]["vector"] == [0.1, 0.2, 0.3] &&
            objs[0]["properties"]["category"] == "news" &&
            objs[0]["properties"]["_namespace"] == "production"
        }
    end
  end

  describe "#query" do
    let(:query_vector) { [0.1, 0.2, 0.3] }
    let(:graphql_response) do
      {
        "data" => {
          "Get" => {
            "Document" => [
              {
                "_additional" => {
                  "id" => "doc-1",
                  "distance" => 0.1
                },
                "metadata" => { "category" => "news" },
                "vector" => [0.1, 0.2, 0.3]
              }
            ]
          }
        }
      }
    end

    before do
      stub_request(:post, "#{base_url}/v1/graphql")
        .to_return(
          status: 200,
          body: graphql_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns QueryResult with correct structure" do
      result = provider.query(index: "Document", vector: query_vector, top_k: 5)

      expect(result).to be_a(Vectra::QueryResult)
      expect(result.size).to eq(1)
      expect(result.first.id).to eq("doc-1")
      expect(result.first.score).to be_within(1e-6).of(0.9) # 1 - distance
    end

    it "includes metadata and values when requested" do
      result = provider.query(
        index: "Document",
        vector: query_vector,
        include_values: true,
        include_metadata: true
      )

      expect(result.first.metadata).to eq("category" => "news")
      expect(result.first.values).to eq([0.1, 0.2, 0.3])
    end

    it "builds GraphQL query with where filter and namespace" do
      provider.query(
        index: "Document",
        vector: query_vector,
        filter: { category: "news" },
        namespace: "prod"
      )

      expect(WebMock).to have_requested(:post, "#{base_url}/v1/graphql")
        .with { |req|
          body = JSON.parse(req.body)
          q = body["query"]
          q.include?("Get") &&
            q.include?("Document") &&
            q.include?("nearVector") &&
            q.include?("\"_namespace\"") &&
            q.include?("\"category\"")
        }
    end
  end

  describe "#fetch" do
    let(:response_body) do
      {
        "objects" => [
          {
            "status" => "SUCCESS",
            "result" => {
              "id" => "doc-1",
              "vector" => [0.1, 0.2, 0.3],
              "properties" => {
                "title" => "Hello",
                "category" => "news",
                "_namespace" => "prod"
              }
            }
          }
        ]
      }
    end

    before do
      stub_request(:post, "#{base_url}/v1/objects/_mget")
        .to_return(
          status: 200,
          body: response_body.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "fetches vectors by IDs and returns Hash with Vector objects" do
      result = provider.fetch(index: "Document", ids: ["doc-1"])

      expect(result).to be_a(Hash)
      expect(result["doc-1"]).to be_a(Vectra::Vector)
      expect(result["doc-1"].values).to eq([0.1, 0.2, 0.3])
      expect(result["doc-1"].metadata).to eq(
        "title" => "Hello",
        "category" => "news"
      )
    end

    it "filters by namespace when provided" do
      result = provider.fetch(index: "Document", ids: ["doc-1"], namespace: "prod")
      expect(result.keys).to eq(["doc-1"])

      result2 = provider.fetch(index: "Document", ids: ["doc-1"], namespace: "other")
      expect(result2).to eq({})
    end
  end

  describe "#update" do
    before do
      stub_request(:patch, "#{base_url}/v1/objects/doc-1")
        .to_return(
          status: 200,
          body: { "result" => "updated" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "updates metadata and returns success" do
      result = provider.update(
        index: "Document",
        id: "doc-1",
        metadata: { category: "updated" }
      )

      expect(result[:updated]).to be true
      expect(WebMock).to have_requested(:patch, "#{base_url}/v1/objects/doc-1")
        .with { |req|
          body = JSON.parse(req.body)
          body["class"] == "Document" &&
            body["properties"]["category"] == "updated"
        }
    end

    it "includes namespace in properties when provided" do
      provider.update(
        index: "Document",
        id: "doc-1",
        metadata: { category: "updated" },
        namespace: "prod"
      )

      expect(WebMock).to have_requested(:patch, "#{base_url}/v1/objects/doc-1")
        .with { |req|
          body = JSON.parse(req.body)
          body["properties"]["_namespace"] == "prod"
        }
    end
  end

  describe "#delete" do
    before do
      stub_request(:delete, "#{base_url}/v1/objects/doc-1")
        .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })

      stub_request(:post, "#{base_url}/v1/objects/delete")
        .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "deletes by IDs and returns success" do
      result = provider.delete(index: "Document", ids: ["doc-1"])

      expect(result[:deleted]).to be true
      expect(WebMock).to have_requested(:delete, "#{base_url}/v1/objects/doc-1")
        .with(query: hash_including("class" => "Document"))
    end

    it "deletes all when delete_all is true" do
      result = provider.delete(index: "Document", delete_all: true)

      expect(result[:deleted]).to be true
      expect(WebMock).to have_requested(:post, "#{base_url}/v1/objects/delete")
        .with { |req|
          body = JSON.parse(req.body)
          body["class"] == "Document" && !body.key?("where")
        }
    end

    it "deletes by filter and namespace" do
      provider.delete(
        index: "Document",
        filter: { category: "old" },
        namespace: "prod"
      )

      expect(WebMock).to have_requested(:post, "#{base_url}/v1/objects/delete")
        .with { |req|
          body = JSON.parse(req.body)
          where = body["where"]
          where &&
            where["operator"] == "And" &&
            where["operands"].any? { |op| op["path"] == ["_namespace"] } &&
            where["operands"].any? { |op| op["path"] == ["category"] }
        }
    end
  end

  describe "#list_indexes" do
    let(:schema_response) do
      {
        "classes" => [
          {
            "class" => "Document",
            "vectorIndexConfig" => {
              "distance" => "cosine",
              "dimension" => 384
            }
          }
        ]
      }
    end

    before do
      stub_request(:get, "#{base_url}/v1/schema")
        .to_return(
          status: 200,
          body: schema_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns array of classes" do
      result = provider.list_indexes

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:name]).to eq("Document")
      expect(result.first[:dimension]).to eq(384)
      expect(result.first[:metric]).to eq("cosine")
    end
  end

  describe "#describe_index" do
    let(:class_response) do
      {
        "class" => "Document",
        "vectorIndexConfig" => {
          "distance" => "l2-squared",
          "dimension" => 768
        }
      }
    end

    before do
      stub_request(:get, "#{base_url}/v1/schema/Document")
        .to_return(
          status: 200,
          body: class_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns class details" do
      result = provider.describe_index(index: "Document")

      expect(result[:name]).to eq("Document")
      expect(result[:dimension]).to eq(768)
      expect(result[:metric]).to eq("euclidean")
    end
  end

  describe "#stats" do
    let(:aggregate_response) do
      {
        "data" => {
          "Aggregate" => {
            "Document" => [
              {
                "meta" => { "count" => 123 }
              }
            ]
          }
        }
      }
    end

    before do
      stub_request(:post, "#{base_url}/v1/graphql")
        .to_return(
          status: 200,
          body: aggregate_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns statistics" do
      result = provider.stats(index: "Document")

      expect(result[:total_vector_count]).to eq(123)
    end

    it "includes namespace breakdown when provided" do
      result = provider.stats(index: "Document", namespace: "prod")

      expect(result[:namespaces]["prod"][:vector_count]).to eq(123)
    end
  end

  describe "configuration validation" do
    it "raises ConfigurationError when host is not configured" do
      bad_config = Vectra::Configuration.new
      bad_config.instance_variable_set(:@provider, :weaviate)
      bad_config.api_key = "test-key"
      bad_config.host = nil

      expect do
        described_class.new(bad_config)
      end.to raise_error(Vectra::ConfigurationError, /host/i)
    end
  end
end

