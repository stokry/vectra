# frozen_string_literal: true

RSpec.describe "Qdrant Integration" do
  # Skip integration tests when Qdrant is not available
  # rubocop:disable RSpec/BeforeAfterAll
  before(:all) do
    skip "Qdrant connection not configured" unless ENV["QDRANT_HOST"]
  end
  # rubocop:enable RSpec/BeforeAfterAll

  let(:qdrant_host) { ENV.fetch("QDRANT_HOST", nil) }
  let(:qdrant_api_key) { ENV.fetch("QDRANT_API_KEY", "") }
  let(:collection_name) { "vectra_test_#{Time.now.to_i}" }

  let(:client) do
    Vectra.configure do |config|
      config.provider = :qdrant
      config.host = qdrant_host
      config.api_key = qdrant_api_key
    end
    Vectra::Client.new
  end

  after do
    # Clean up test collection
    client.provider.delete_index(name: collection_name)
  rescue Vectra::Error
    # Ignore cleanup errors
  end

  describe "basic operations" do
    let(:test_vectors) do
      [
        { id: "test-1", values: Array.new(384) { rand }, metadata: { text: "First document", category: "tech" } },
        { id: "test-2", values: Array.new(384) { rand }, metadata: { text: "Second document", category: "science" } },
        { id: "test-3", values: Array.new(384) { rand }, metadata: { text: "Third document", category: "tech" } }
      ]
    end

    context "when performing collection operations" do
      it "creates a collection" do
        result = client.provider.create_index(
          name: collection_name,
          dimension: 384,
          metric: "cosine"
        )

        expect(result[:name]).to eq(collection_name)
        expect(result[:dimension]).to eq(384)
      end

      it "lists collections" do
        client.provider.create_index(name: collection_name, dimension: 384)
        collections = client.list_indexes

        expect(collections).to be_an(Array)
        expect(collections.map { |c| c[:name] }).to include(collection_name)
      end

      it "describes a collection" do
        client.provider.create_index(name: collection_name, dimension: 384)
        info = client.describe_index(index: collection_name)

        expect(info[:name]).to eq(collection_name)
        expect(info[:dimension]).to eq(384)
      end

      it "gets collection stats" do
        client.provider.create_index(name: collection_name, dimension: 384)
        client.upsert(index: collection_name, vectors: test_vectors)

        # Wait for indexing
        sleep(1)

        stats = client.stats(index: collection_name)

        expect(stats[:total_vector_count]).to eq(3)
        expect(stats[:dimension]).to eq(384)
      end

      it "deletes a collection" do
        client.provider.create_index(name: collection_name, dimension: 384)
        result = client.provider.delete_index(name: collection_name)

        expect(result[:deleted]).to be true
      end
    end

    context "when performing CRUD operations" do
      before do
        client.provider.create_index(name: collection_name, dimension: 384, metric: "cosine")
      end

      it "upserts vectors" do
        result = client.upsert(index: collection_name, vectors: test_vectors)

        expect(result[:upserted_count]).to eq(3)
      end

      it "queries vectors by similarity" do
        client.upsert(index: collection_name, vectors: test_vectors)

        # Wait for indexing
        sleep(1)

        # Query with the first vector
        results = client.query(
          index: collection_name,
          vector: test_vectors[0][:values],
          top_k: 3
        )

        expect(results).to be_a(Vectra::QueryResult)
        expect(results.size).to be >= 1
        expect(results.first.score).to be > 0.9 # Should be very similar to itself
      end

      it "fetches vectors by ID" do
        client.upsert(index: collection_name, vectors: test_vectors)

        # Wait for indexing
        sleep(1)

        # Note: Qdrant uses hashed IDs, so we fetch by the hashed ID
        result = client.query(
          index: collection_name,
          vector: test_vectors[0][:values],
          top_k: 1
        )

        fetched_id = result.first.id
        vectors = client.fetch(index: collection_name, ids: [fetched_id])

        expect(vectors).to be_a(Hash)
        expect(vectors.keys.length).to eq(1)
      end

      it "updates vector metadata" do
        client.upsert(index: collection_name, vectors: test_vectors)

        # Wait for indexing
        sleep(1)

        # Get the ID from query
        result = client.query(
          index: collection_name,
          vector: test_vectors[0][:values],
          top_k: 1
        )

        point_id = result.first.id
        update_result = client.update(
          index: collection_name,
          id: point_id,
          metadata: { updated: true, new_field: "value" }
        )

        expect(update_result[:updated]).to be true
      end

      it "deletes vectors by ID" do
        client.upsert(index: collection_name, vectors: test_vectors)

        # Wait for indexing
        sleep(1)

        # Get an ID to delete
        result = client.query(
          index: collection_name,
          vector: test_vectors[0][:values],
          top_k: 1
        )

        point_id = result.first.id
        delete_result = client.delete(index: collection_name, ids: [point_id])

        expect(delete_result[:deleted]).to be true
      end
    end

    context "when using filters" do
      before do
        client.provider.create_index(name: collection_name, dimension: 384, metric: "cosine")
        client.upsert(index: collection_name, vectors: test_vectors)
        sleep(1) # Wait for indexing
      end

      it "queries with metadata filter" do
        results = client.query(
          index: collection_name,
          vector: test_vectors[0][:values],
          top_k: 10,
          filter: { category: "tech" }
        )

        expect(results).to be_a(Vectra::QueryResult)
        results.each do |match|
          expect(match.metadata["category"]).to eq("tech")
        end
      end

      it "deletes with filter" do
        client.delete(index: collection_name, filter: { category: "science" })

        # Wait for deletion
        sleep(1)

        # Verify only tech items remain
        stats = client.stats(index: collection_name)
        expect(stats[:total_vector_count]).to eq(2)
      end
    end

    context "when using namespaces" do
      before do
        client.provider.create_index(name: collection_name, dimension: 384, metric: "cosine")
      end

      let(:namespace_vectors) do
        [
          { id: "ns-1", values: Array.new(384) { rand }, metadata: { text: "Namespace doc 1" } },
          { id: "ns-2", values: Array.new(384) { rand }, metadata: { text: "Namespace doc 2" } }
        ]
      end

      it "upserts vectors with namespace" do
        result = client.upsert(
          index: collection_name,
          vectors: namespace_vectors,
          namespace: "production"
        )

        expect(result[:upserted_count]).to eq(2)
      end

      it "queries vectors within namespace" do
        client.upsert(index: collection_name, vectors: namespace_vectors, namespace: "production")
        client.upsert(index: collection_name, vectors: test_vectors, namespace: "staging")

        sleep(1)

        results = client.query(
          index: collection_name,
          vector: namespace_vectors[0][:values],
          top_k: 10,
          namespace: "production"
        )

        expect(results.size).to eq(2)
      end
    end

    context "when using different metrics" do
      it "supports cosine similarity" do
        client.provider.create_index(name: collection_name, dimension: 384, metric: "cosine")
        info = client.describe_index(index: collection_name)

        expect(info[:metric]).to eq("cosine")
      end

      it "supports euclidean distance" do
        collection_euclidean = "#{collection_name}_euclidean"
        client.provider.create_index(name: collection_euclidean, dimension: 384, metric: "euclidean")

        begin
          info = client.describe_index(index: collection_euclidean)
          expect(info[:metric]).to eq("euclidean")
        ensure
          client.provider.delete_index(name: collection_euclidean)
        end
      end

      it "supports dot product" do
        collection_dot = "#{collection_name}_dot"
        client.provider.create_index(name: collection_dot, dimension: 384, metric: "dot_product")

        begin
          info = client.describe_index(index: collection_dot)
          expect(info[:metric]).to eq("dot_product")
        ensure
          client.provider.delete_index(name: collection_dot)
        end
      end
    end
  end

  describe "error handling" do
    it "raises NotFoundError for missing collection" do
      expect do
        client.describe_index(index: "nonexistent_collection_xyz")
      end.to raise_error(Vectra::NotFoundError)
    end

    it "raises ValidationError for invalid dimension" do
      expect do
        client.provider.create_index(name: collection_name, dimension: 0)
      end.to raise_error(Vectra::Error)
    end
  end
end
