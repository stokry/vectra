# frozen_string_literal: true

RSpec.describe "Pgvector Integration" do
  # Skip integration tests when PostgreSQL is not available
  # rubocop:disable RSpec/BeforeAfterAll
  before(:all) do
    skip "PostgreSQL connection not configured" unless ENV["PGVECTOR_TEST_URL"]
  end
  # rubocop:enable RSpec/BeforeAfterAll

  let(:connection_url) { ENV.fetch("PGVECTOR_TEST_URL") }
  let(:index_name) { "vectra_test_#{Time.now.to_i}" }

  let(:client) do
    Vectra.pgvector(connection_url: connection_url)
  end

  after do
    # Clean up test table
    client.provider.delete_index(name: index_name)
  rescue Vectra::Error
    # Ignore cleanup errors
  end

  describe "basic operations" do
    let(:test_vectors) do
      [
        { id: "test-1", values: Array.new(384) { rand }, metadata: { text: "First document" } },
        { id: "test-2", values: Array.new(384) { rand }, metadata: { text: "Second document" } },
        { id: "test-3", values: Array.new(384) { rand }, metadata: { text: "Third document" } }
      ]
    end

    context "when index operations" do
      it "creates an index" do
        result = client.provider.create_index(
          name: index_name,
          dimension: 384,
          metric: "cosine"
        )

        expect(result[:name]).to eq(index_name)
        expect(result[:dimension]).to eq(384)
      end

      it "lists indexes" do
        client.provider.create_index(name: index_name, dimension: 384)
        indexes = client.list_indexes

        expect(indexes).to be_an(Array)
        expect(indexes.map { |i| i[:name] }).to include(index_name)
      end

      it "describes an index" do
        client.provider.create_index(name: index_name, dimension: 384)
        info = client.describe_index(index: index_name)

        expect(info[:name]).to eq(index_name)
        expect(info[:dimension]).to eq(384)
        expect(info[:status]).to eq("ready")
      end

      it "gets index stats" do
        client.provider.create_index(name: index_name, dimension: 384)
        client.upsert(index: index_name, vectors: test_vectors)

        stats = client.stats(index: index_name)

        expect(stats[:total_vector_count]).to eq(3)
        expect(stats[:dimension]).to eq(384)
      end

      it "deletes an index" do
        client.provider.create_index(name: index_name, dimension: 384)
        result = client.provider.delete_index(name: index_name)

        expect(result[:deleted]).to be true
      end
    end

    context "when vector operations" do
      before do
        client.provider.create_index(name: index_name, dimension: 384)
      end

      it "upserts vectors" do
        result = client.upsert(index: index_name, vectors: test_vectors)

        expect(result[:upserted_count]).to eq(3)
      end

      it "queries vectors" do
        client.upsert(index: index_name, vectors: test_vectors)
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

      it "fetches vectors by ID" do
        client.upsert(index: index_name, vectors: test_vectors)

        vectors = client.fetch(index: index_name, ids: ["test-1", "test-2"])

        expect(vectors).to be_a(Hash)
        expect(vectors["test-1"]).to be_a(Vectra::Vector)
        expect(vectors["test-1"].values.size).to eq(384)
      end

      it "updates vector metadata" do
        client.upsert(index: index_name, vectors: test_vectors)

        result = client.update(
          index: index_name,
          id: "test-1",
          metadata: { text: "Updated first document", updated: true }
        )

        expect(result[:updated]).to be true

        # Verify update
        vectors = client.fetch(index: index_name, ids: ["test-1"])
        expect(vectors["test-1"].metadata["updated"]).to be true
      end

      it "deletes vectors" do
        client.upsert(index: index_name, vectors: test_vectors)

        result = client.delete(index: index_name, ids: ["test-1", "test-2"])

        expect(result[:deleted]).to be true

        # Verify deletion
        stats = client.stats(index: index_name)
        expect(stats[:total_vector_count]).to eq(1)
      end
    end

    context "when using namespaces" do
      before do
        client.provider.create_index(name: index_name, dimension: 384)
      end

      it "upserts to namespace" do
        result = client.upsert(
          index: index_name,
          vectors: [test_vectors.first],
          namespace: "test-namespace"
        )

        expect(result[:upserted_count]).to eq(1)
      end

      it "queries from namespace" do
        client.upsert(index: index_name, vectors: test_vectors, namespace: "ns1")
        client.upsert(index: index_name, vectors: [test_vectors.first.merge(id: "other")], namespace: "ns2")

        results = client.query(
          index: index_name,
          vector: test_vectors.first[:values],
          top_k: 10,
          namespace: "ns1"
        )

        expect(results.ids).not_to include("other")
      end

      it "tracks namespace stats" do
        client.upsert(index: index_name, vectors: test_vectors, namespace: "production")
        client.upsert(index: index_name, vectors: [test_vectors.first.merge(id: "dev-1")], namespace: "development")

        stats = client.stats(index: index_name)

        expect(stats[:namespaces]["production"][:vector_count]).to eq(3)
        expect(stats[:namespaces]["development"][:vector_count]).to eq(1)
      end
    end

    context "when using filters" do
      before do
        client.provider.create_index(name: index_name, dimension: 384)
        client.upsert(
          index: index_name,
          vectors: [
            { id: "cat-1", values: Array.new(384) { rand }, metadata: { category: "animals", type: "cat" } },
            { id: "dog-1", values: Array.new(384) { rand }, metadata: { category: "animals", type: "dog" } },
            { id: "car-1", values: Array.new(384) { rand }, metadata: { category: "vehicles", type: "car" } }
          ]
        )
      end

      it "queries with metadata filter" do
        query_vector = Array.new(384) { rand }

        results = client.query(
          index: index_name,
          vector: query_vector,
          top_k: 10,
          filter: { category: "animals" }
        )

        expect(results.ids).to include("cat-1", "dog-1")
        expect(results.ids).not_to include("car-1")
      end

      it "deletes with filter" do
        client.delete(index: index_name, filter: { category: "vehicles" })

        stats = client.stats(index: index_name)
        expect(stats[:total_vector_count]).to eq(2)
      end
    end

    context "when using different metrics" do
      it "supports cosine similarity" do
        idx = "#{index_name}_cosine"
        client.provider.create_index(name: idx, dimension: 3, metric: "cosine")

        client.upsert(index: idx, vectors: [{ id: "v1", values: [1, 0, 0] }])
        results = client.query(index: idx, vector: [1, 0, 0], top_k: 1)

        expect(results.first.score).to be_within(0.01).of(1.0)
        client.provider.delete_index(name: idx)
      end

      it "supports euclidean distance" do
        idx = "#{index_name}_euclidean"
        client.provider.create_index(name: idx, dimension: 3, metric: "euclidean")

        client.upsert(index: idx, vectors: [{ id: "v1", values: [0, 0, 0] }])
        results = client.query(index: idx, vector: [0, 0, 0], top_k: 1)

        # Euclidean distance of 0 converted to similarity
        expect(results.first.score).to eq(1.0)
        client.provider.delete_index(name: idx)
      end
    end
  end

  describe "error handling" do
    it "raises NotFoundError for missing index" do
      expect { client.describe_index(index: "nonexistent_table_xyz") }
        .to raise_error(Vectra::NotFoundError)
    end

    it "raises ValidationError for invalid metric" do
      expect { client.provider.create_index(name: index_name, dimension: 384, metric: "invalid") }
        .to raise_error(Vectra::ValidationError)
    end
  end
end
