# frozen_string_literal: true

RSpec.describe "Pinecone Integration", :vcr do
  # Skip integration tests in CI when credentials are not available
  # rubocop:disable RSpec/BeforeAfterAll
  before(:all) do
    skip "Pinecone API key not configured" unless ENV["PINECONE_API_KEY"]
  end
  # rubocop:enable RSpec/BeforeAfterAll

  let(:api_key) { ENV.fetch("PINECONE_API_KEY") }
  let(:environment) { ENV.fetch("PINECONE_ENVIRONMENT", "us-east-1") }
  let(:index_name) { "vectra-test-index" }

  let(:client) do
    Vectra.pinecone(
      api_key: api_key,
      environment: environment
    )
  end

  describe "basic operations" do
    let(:test_vectors) do
      [
        { id: "test-1", values: Array.new(384) { rand }, metadata: { text: "Test 1" } },
        { id: "test-2", values: Array.new(384) { rand }, metadata: { text: "Test 2" } },
        { id: "test-3", values: Array.new(384) { rand }, metadata: { text: "Test 3" } }
      ]
    end

    context "when index operations" do
      it "lists indexes", vcr: { cassette_name: "pinecone/list_indexes" } do
        indexes = client.list_indexes

        expect(indexes).to be_an(Array)
      end

      it "describes an index", vcr: { cassette_name: "pinecone/describe_index" } do
        info = client.describe_index(index: index_name)

        expect(info).to be_a(Hash)
        expect(info[:name]).to eq(index_name)
        expect(info[:dimension]).to be_a(Integer)
      end

      it "gets index stats", vcr: { cassette_name: "pinecone/index_stats" } do
        stats = client.stats(index: index_name)

        expect(stats).to be_a(Hash)
        expect(stats).to have_key(:total_vector_count)
      end
    end

    context "when vector operations" do
      it "upserts vectors", vcr: { cassette_name: "pinecone/upsert" } do
        result = client.upsert(index: index_name, vectors: test_vectors)

        expect(result[:upserted_count]).to eq(3)
      end

      it "queries vectors", vcr: { cassette_name: "pinecone/query" } do
        query_vector = test_vectors.first[:values]

        results = client.query(
          index: index_name,
          vector: query_vector,
          top_k: 3,
          include_metadata: true
        )

        expect(results).to be_a(Vectra::QueryResult)
        expect(results.size).to be <= 3
        expect(results.first).to be_a(Vectra::Match) if results.any?
      end

      it "fetches vectors by ID", vcr: { cassette_name: "pinecone/fetch" } do
        vectors = client.fetch(index: index_name, ids: ["test-1", "test-2"])

        expect(vectors).to be_a(Hash)
        expect(vectors["test-1"]).to be_a(Vectra::Vector) if vectors.key?("test-1")
      end

      it "updates vector metadata", vcr: { cassette_name: "pinecone/update" } do
        result = client.update(
          index: index_name,
          id: "test-1",
          metadata: { text: "Updated Test 1", updated: true }
        )

        expect(result[:updated]).to be true
      end

      it "deletes vectors", vcr: { cassette_name: "pinecone/delete" } do
        result = client.delete(index: index_name, ids: ["test-1", "test-2", "test-3"])

        expect(result[:deleted]).to be true
      end
    end

    context "when using filters" do
      it "queries with metadata filter", vcr: { cassette_name: "pinecone/query_with_filter" } do
        query_vector = Array.new(384) { rand }

        results = client.query(
          index: index_name,
          vector: query_vector,
          top_k: 5,
          filter: { text: "Test 1" }
        )

        expect(results).to be_a(Vectra::QueryResult)
      end
    end

    context "when using namespaces" do
      it "upserts to namespace", vcr: { cassette_name: "pinecone/upsert_namespace" } do
        result = client.upsert(
          index: index_name,
          vectors: [test_vectors.first],
          namespace: "test-namespace"
        )

        expect(result[:upserted_count]).to eq(1)
      end

      it "queries from namespace", vcr: { cassette_name: "pinecone/query_namespace" } do
        query_vector = test_vectors.first[:values]

        results = client.query(
          index: index_name,
          vector: query_vector,
          top_k: 3,
          namespace: "test-namespace"
        )

        expect(results).to be_a(Vectra::QueryResult)
      end
    end
  end

  describe "error handling" do
    it "handles authentication errors", vcr: { cassette_name: "pinecone/auth_error" } do
      bad_client = Vectra.pinecone(api_key: "invalid-key", environment: environment)

      expect { bad_client.list_indexes }
        .to raise_error(Vectra::AuthenticationError)
    end

    it "handles not found errors", vcr: { cassette_name: "pinecone/not_found" } do
      expect { client.describe_index(index: "non-existent-index") }
        .to raise_error(Vectra::NotFoundError)
    end
  end
end
