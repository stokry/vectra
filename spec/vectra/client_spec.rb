# frozen_string_literal: true

RSpec.describe Vectra::Client do
  include_context "with pinecone configuration"

  let(:client) { described_class.new }
  let(:provider) { instance_double(Vectra::Providers::Pinecone) }

  before do
    allow(Vectra::Providers::Pinecone).to receive(:new).and_return(provider)
    allow(provider).to receive(:provider_name).and_return(:pinecone)
  end

  describe "#initialize" do
    it "creates client with global configuration" do
      expect(client).to be_a(described_class)
      expect(client.config.provider).to eq(:pinecone)
    end

    it "creates client with instance configuration" do
      client = described_class.new(
        provider: :qdrant,
        api_key: "test-key",
        host: "https://test.qdrant.io"
      )

      expect(client.config.provider).to eq(:qdrant)
      expect(client.config.api_key).to eq("test-key")
    end

    it "validates configuration on initialize" do
      Vectra.reset_configuration!
      expect do
        described_class.new(provider: :pinecone, api_key: nil)
      end.to raise_error(Vectra::ConfigurationError)
    end

    it "builds the appropriate provider" do
      client # trigger lazy evaluation
      expect(Vectra::Providers::Pinecone).to have_received(:new)
    end
  end

  describe "#upsert" do
    let(:vectors) { [sample_vector(id: "vec1"), sample_vector(id: "vec2")] }

    before do
      allow(provider).to receive(:upsert).and_return(upserted_count: 2)
    end

    it "upserts vectors through provider" do
      result = client.upsert(index: index_name, vectors: vectors)

      expect(provider).to have_received(:upsert).with(
        index: index_name,
        vectors: vectors,
        namespace: nil
      )
      expect(result[:upserted_count]).to eq(2)
    end

    it "supports namespace parameter" do
      client.upsert(index: index_name, vectors: vectors, namespace: "prod")

      expect(provider).to have_received(:upsert).with(
        index: index_name,
        vectors: vectors,
        namespace: "prod"
      )
    end

    context "with validation" do
      it "validates index name" do
        expect { client.upsert(index: nil, vectors: vectors) }
          .to raise_error(Vectra::ValidationError, /Index name cannot be nil/)
      end

      it "validates index is a string" do
        expect { client.upsert(index: 123, vectors: vectors) }
          .to raise_error(Vectra::ValidationError, /Index name must be a string/)
      end

      it "validates index is not empty" do
        expect { client.upsert(index: "", vectors: vectors) }
          .to raise_error(Vectra::ValidationError, /Index name cannot be empty/)
      end

      it "validates vectors are provided" do
        expect { client.upsert(index: index_name, vectors: nil) }
          .to raise_error(Vectra::ValidationError, /Vectors cannot be nil/)
      end

      it "validates vectors is an array" do
        expect { client.upsert(index: index_name, vectors: "not an array") }
          .to raise_error(Vectra::ValidationError, /Vectors must be an array/)
      end

      it "validates vectors array is not empty" do
        expect { client.upsert(index: index_name, vectors: []) }
          .to raise_error(Vectra::ValidationError, /Vectors cannot be empty/)
      end

      it "validates dimension consistency across vectors" do
        vectors = [
          { id: "vec1", values: [0.1, 0.2, 0.3] }, # 3 dimensions
          { id: "vec2", values: [0.4, 0.5] }        # 2 dimensions - inconsistent!
        ]

        expect { client.upsert(index: index_name, vectors: vectors) }
          .to raise_error(Vectra::ValidationError, /Inconsistent vector dimensions/)
      end

      it "validates dimension consistency with Vector objects" do
        vectors = [
          Vectra::Vector.new(id: "vec1", values: [0.1, 0.2, 0.3]),
          Vectra::Vector.new(id: "vec2", values: [0.4, 0.5]) # Different dimension
        ]

        expect { client.upsert(index: index_name, vectors: vectors) }
          .to raise_error(Vectra::ValidationError, /Inconsistent vector dimensions/)
      end

      it "allows vectors with same dimensions" do
        vectors = [
          { id: "vec1", values: [0.1, 0.2, 0.3] },
          { id: "vec2", values: [0.4, 0.5, 0.6] } # Same dimension - OK
        ]

        expect { client.upsert(index: index_name, vectors: vectors) }.not_to raise_error
      end
    end
  end

  describe "#query" do
    let(:query_vector) { [0.1, 0.2, 0.3] }
    let(:query_result) { Vectra::QueryResult.new(matches: [sample_match]) }

    before do
      allow(provider).to receive(:query).and_return(query_result)
    end

    it "queries vectors through provider" do
      result = client.query(index: index_name, vector: query_vector, top_k: 5)

      expect(provider).to have_received(:query).with(
        index: index_name,
        vector: query_vector,
        top_k: 5,
        namespace: nil,
        filter: nil,
        include_values: false,
        include_metadata: true
      )
      expect(result).to eq(query_result)
    end

    it "supports all optional parameters" do
      client.query(
        index: index_name,
        vector: query_vector,
        top_k: 10,
        namespace: "prod",
        filter: { category: "test" },
        include_values: true,
        include_metadata: false
      )

      expect(provider).to have_received(:query).with(
        index: index_name,
        vector: query_vector,
        top_k: 10,
        namespace: "prod",
        filter: { category: "test" },
        include_values: true,
        include_metadata: false
      )
    end

    context "with validation" do
      it "validates index name" do
        expect { client.query(index: nil, vector: query_vector) }
          .to raise_error(Vectra::ValidationError, /Index name cannot be nil/)
      end

      it "validates query vector" do
        expect { client.query(index: index_name, vector: nil) }
          .to raise_error(Vectra::ValidationError, /Query vector cannot be nil/)
      end

      it "validates query vector is an array" do
        expect { client.query(index: index_name, vector: "invalid") }
          .to raise_error(Vectra::ValidationError, /Query vector must be an array/)
      end

      it "validates query vector is not empty" do
        expect { client.query(index: index_name, vector: []) }
          .to raise_error(Vectra::ValidationError, /Query vector cannot be empty/)
      end
    end

    describe "query builder" do
      it "returns a QueryBuilder when called with index string only" do
        builder = client.query(index_name)

        expect(builder).to be_a(Vectra::Client::QueryBuilder)
        expect(builder.index).to eq(index_name)
      end

      it "builds and executes query via chainable API" do
        result = client
          .query(index_name)
          .vector(query_vector)
          .top_k(10)
          .namespace("prod")
          .filter(category: "ruby")
          .with_values
          .without_metadata
          .execute

        expect(result).to eq(query_result)
        expect(provider).to have_received(:query).with(
          index: index_name,
          vector: query_vector,
          top_k: 10,
          namespace: "prod",
          filter: { category: "ruby" },
          include_values: true,
          include_metadata: false
        )
      end

      it "supports filter(value) and filter(category: ...)" do
        client.query(index_name)
          .vector(query_vector)
          .filter(category: "ruby")
          .execute

        expect(provider).to have_received(:query).with(
          index: index_name,
          vector: query_vector,
          top_k: 10,
          namespace: nil,
          filter: { category: "ruby" },
          include_values: false,
          include_metadata: true
        )
      end
    end
  end

  describe "#fetch" do
    let(:ids) { ["vec1", "vec2"] }
    let(:fetched_vectors) do
      {
        "vec1" => Vectra::Vector.new(id: "vec1", values: [0.1]),
        "vec2" => Vectra::Vector.new(id: "vec2", values: [0.2])
      }
    end

    before do
      allow(provider).to receive(:fetch).and_return(fetched_vectors)
    end

    it "fetches vectors through provider" do
      result = client.fetch(index: index_name, ids: ids)

      expect(provider).to have_received(:fetch).with(
        index: index_name,
        ids: ids,
        namespace: nil
      )
      expect(result).to eq(fetched_vectors)
    end

    context "with validation" do
      it "validates ids are provided" do
        expect { client.fetch(index: index_name, ids: nil) }
          .to raise_error(Vectra::ValidationError, /IDs cannot be nil/)
      end

      it "validates ids is an array" do
        expect { client.fetch(index: index_name, ids: "not-array") }
          .to raise_error(Vectra::ValidationError, /IDs must be an array/)
      end

      it "validates ids array is not empty" do
        expect { client.fetch(index: index_name, ids: []) }
          .to raise_error(Vectra::ValidationError, /IDs cannot be empty/)
      end
    end
  end

  describe "#update" do
    before do
      allow(provider).to receive(:update).and_return(updated: true)
    end

    it "updates vector metadata through provider" do
      client.update(index: index_name, id: "vec1", metadata: { new: "data" })

      expect(provider).to have_received(:update).with(
        index: index_name,
        id: "vec1",
        metadata: { new: "data" },
        values: nil,
        namespace: nil
      )
    end

    it "updates vector values through provider" do
      client.update(index: index_name, id: "vec1", values: [0.1, 0.2])

      expect(provider).to have_received(:update).with(
        index: index_name,
        id: "vec1",
        metadata: nil,
        values: [0.1, 0.2],
        namespace: nil
      )
    end

    context "with validation" do
      it "validates id is provided" do
        expect { client.update(index: index_name, id: nil, metadata: {}) }
          .to raise_error(Vectra::ValidationError, /ID cannot be nil/)
      end

      it "validates id is a string" do
        expect { client.update(index: index_name, id: 123, metadata: {}) }
          .to raise_error(Vectra::ValidationError, /ID must be a string/)
      end

      it "requires either metadata or values" do
        expect { client.update(index: index_name, id: "vec1") }
          .to raise_error(Vectra::ValidationError, /Must provide metadata or values/)
      end
    end
  end

  describe "#delete" do
    before do
      allow(provider).to receive(:delete).and_return(deleted: true)
    end

    it "deletes vectors by IDs" do
      client.delete(index: index_name, ids: ["vec1", "vec2"])

      expect(provider).to have_received(:delete).with(
        index: index_name,
        ids: ["vec1", "vec2"],
        namespace: nil,
        filter: nil,
        delete_all: false
      )
    end

    it "deletes vectors by filter" do
      client.delete(index: index_name, filter: { category: "old" })

      expect(provider).to have_received(:delete).with(
        index: index_name,
        ids: nil,
        namespace: nil,
        filter: { category: "old" },
        delete_all: false
      )
    end

    it "deletes all vectors when specified" do
      client.delete(index: index_name, delete_all: true)

      expect(provider).to have_received(:delete).with(
        index: index_name,
        ids: nil,
        namespace: nil,
        filter: nil,
        delete_all: true
      )
    end

    context "with validation" do
      it "requires ids, filter, or delete_all" do
        expect { client.delete(index: index_name) }
          .to raise_error(Vectra::ValidationError, /Must provide ids, filter, or delete_all/)
      end
    end
  end

  describe "#list_indexes" do
    let(:indexes) { [{ name: "index1" }, { name: "index2" }] }

    before do
      allow(provider).to receive(:list_indexes).and_return(indexes)
    end

    it "lists indexes through provider" do
      result = client.list_indexes

      expect(provider).to have_received(:list_indexes)
      expect(result).to eq(indexes)
    end
  end

  describe "#describe_index" do
    let(:index_info) { { name: index_name, dimension: 384 } }

    before do
      allow(provider).to receive(:describe_index).and_return(index_info)
    end

    it "describes index through provider" do
      result = client.describe_index(index: index_name)

      expect(provider).to have_received(:describe_index).with(index: index_name)
      expect(result).to eq(index_info)
    end
  end

  describe "#stats" do
    let(:stats) { { total_vector_count: 1000 } }

    before do
      allow(provider).to receive(:stats).and_return(stats)
    end

    it "gets stats through provider" do
      result = client.stats(index: index_name)

      expect(provider).to have_received(:stats).with(index: index_name, namespace: nil)
      expect(result).to eq(stats)
    end
  end

  describe "#provider_name" do
    it "returns provider name" do
      expect(client.provider_name).to eq(:pinecone)
    end
  end

  describe "#healthy?" do
    before do
      allow(provider).to receive(:list_indexes).and_return([])
    end

    it "returns true when provider is healthy" do
      expect(client.healthy?).to be true
    end

    it "returns false when provider raises error" do
      allow(provider).to receive(:list_indexes).and_raise(StandardError.new("Connection failed"))

      expect(client.healthy?).to be false
    end

    it "logs errors when health check fails" do
      allow(provider).to receive(:list_indexes).and_raise(StandardError.new("Connection failed"))
      allow(client.config).to receive(:logger).and_return(double(debug: nil, error: nil))

      client.healthy?

      expect(client.config.logger).to have_received(:error).at_least(:once)
    end
  end

  describe "#ping" do
    before do
      allow(provider).to receive(:list_indexes).and_return([])
    end

    it "returns health status with latency" do
      result = client.ping

      expect(result).to include(:healthy, :provider, :latency_ms)
      expect(result[:healthy]).to be true
      expect(result[:provider]).to eq(:pinecone)
      expect(result[:latency_ms]).to be_a(Numeric)
      expect(result[:latency_ms]).to be >= 0
    end

    it "includes error info when unhealthy" do
      allow(provider).to receive(:list_indexes).and_raise(StandardError.new("Connection failed"))

      result = client.ping

      expect(result[:healthy]).to be false
      expect(result).to include(:error, :error_message)
      expect(result[:error]).to eq("StandardError")
    end

    it "measures latency correctly" do
      allow(provider).to receive(:list_indexes) do
        sleep(0.01) # 10ms delay
        []
      end

      result = client.ping

      expect(result[:latency_ms]).to be >= 10
      expect(result[:latency_ms]).to be < 100 # Should be fast
    end
  end

  describe "convenience methods" do
    describe "Vectra.client" do
      it "creates a new client" do
        client = Vectra.client(provider: :qdrant, api_key: "key", host: "host")
        expect(client).to be_a(described_class)
      end
    end

    describe "Vectra.pinecone" do
      it "creates a Pinecone client" do
        client = Vectra.pinecone(api_key: "key", environment: "us-east-1")
        expect(client.config.provider).to eq(:pinecone)
      end
    end

    describe "Vectra.qdrant" do
      it "creates a Qdrant client" do
        client = Vectra.qdrant(api_key: "key", host: "https://test.qdrant.io")
        expect(client.config.provider).to eq(:qdrant)
      end
    end

    describe "Vectra.weaviate" do
      it "creates a Weaviate client" do
        client = Vectra.weaviate(api_key: "key", host: "https://test.weaviate.io")
        expect(client.config.provider).to eq(:weaviate)
      end
    end

    describe "Vectra.pgvector" do
      it "creates a pgvector client with connection URL" do
        client = Vectra.pgvector(connection_url: "postgres://user:pass@localhost/db")
        expect(client.config.provider).to eq(:pgvector)
        expect(client.config.host).to eq("postgres://user:pass@localhost/db")
      end

      it "creates a pgvector client with host and password" do
        client = Vectra.pgvector(host: "localhost", password: "secret")
        expect(client.config.provider).to eq(:pgvector)
        expect(client.config.api_key).to eq("secret")
      end
    end
  end
end
