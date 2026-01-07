# frozen_string_literal: true

RSpec.describe Vectra::Providers::Pgvector do
  let(:config) do
    cfg = Vectra::Configuration.new
    cfg.instance_variable_set(:@provider, :pgvector)
    cfg.host = "postgres://user:pass@localhost/testdb"
    cfg
  end

  let(:provider) { described_class.new(config) }

  let(:mock_connection) do
    instance_double(PG::Connection).tap do |conn|
      allow(conn).to receive(:quote_ident) { |name| "\"#{name}\"" }
      allow(conn).to receive(:escape_literal) { |str| "'#{str}'" }
    end
  end

  before do
    allow(PG).to receive(:connect).and_return(mock_connection)
  end

  describe "#provider_name" do
    it "returns :pgvector" do
      expect(provider.provider_name).to eq(:pgvector)
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
      # Mock table existence check
      allow(mock_connection).to receive(:exec_params)
        .with(/SELECT EXISTS/, ["test_index"])
        .and_return([{ "exists" => true }])

      # Mock upsert
      allow(mock_connection).to receive(:exec_params)
        .with(/INSERT INTO/, anything)
        .and_return([])
    end

    it "upserts vectors and returns count" do
      result = provider.upsert(index: "test_index", vectors: vectors)

      expect(result[:upserted_count]).to eq(2)
    end

    it "includes namespace when provided" do
      allow(mock_connection).to receive(:exec_params)
        .with(/INSERT INTO/, array_including("my-namespace"))
        .and_return([])

      provider.upsert(index: "test_index", vectors: vectors, namespace: "my-namespace")

      expect(mock_connection).to have_received(:exec_params)
        .with(/INSERT INTO/, array_including("my-namespace"))
        .twice
    end
  end

  describe "#query" do
    let(:query_vector) { [0.1, 0.2, 0.3] }
    let(:mock_results) do
      [
        { "id" => "vec1", "score" => "0.95", "metadata" => '{"text": "Hello"}' },
        { "id" => "vec2", "score" => "0.85", "metadata" => '{"text": "World"}' }
      ]
    end

    before do
      # Mock table existence check
      allow(mock_connection).to receive(:exec_params)
        .with(/SELECT EXISTS/, ["test_index"])
        .and_return([{ "exists" => true }])

      # Mock metric lookup
      allow(mock_connection).to receive(:exec_params)
        .with(/obj_description/, ["test_index"])
        .and_return([{ "comment" => "vectra:metric=cosine" }])

      # Mock query
      allow(mock_connection).to receive(:exec_params)
        .with(/SELECT.*FROM.*ORDER BY/, [])
        .and_return(mock_results)
    end

    it "returns QueryResult" do
      result = provider.query(index: "test_index", vector: query_vector, top_k: 5)

      expect(result).to be_a(Vectra::QueryResult)
      expect(result.size).to eq(2)
    end

    it "includes metadata by default" do
      result = provider.query(index: "test_index", vector: query_vector)

      expect(result.first.metadata).to eq("text" => "Hello")
    end

    it "filters by namespace" do
      allow(mock_connection).to receive(:exec_params)
        .with(/WHERE.*namespace = 'prod'/, [])
        .and_return(mock_results)

      provider.query(index: "test_index", vector: query_vector, namespace: "prod")

      expect(mock_connection).to have_received(:exec_params)
        .with(/WHERE.*namespace = 'prod'/, [])
    end

    it "applies metadata filter" do
      allow(mock_connection).to receive(:exec_params)
        .with(/metadata->>'category' = 'test'/, [])
        .and_return(mock_results)

      provider.query(index: "test_index", vector: query_vector, filter: { category: "test" })

      expect(mock_connection).to have_received(:exec_params)
        .with(/metadata->>'category' = 'test'/, [])
    end
  end

  describe "#fetch" do
    let(:mock_results) do
      [
        { "id" => "vec1", "embedding" => "[0.1,0.2,0.3]", "metadata" => '{"text": "Hello"}' }
      ]
    end

    before do
      allow(mock_connection).to receive(:exec_params)
        .with(/SELECT EXISTS/, ["test_index"])
        .and_return([{ "exists" => true }])

      allow(mock_connection).to receive(:exec_params)
        .with(/SELECT id, embedding, metadata FROM/, anything)
        .and_return(mock_results)
    end

    it "fetches vectors by IDs" do
      result = provider.fetch(index: "test_index", ids: ["vec1"])

      expect(result).to be_a(Hash)
      expect(result["vec1"]).to be_a(Vectra::Vector)
      expect(result["vec1"].values).to eq([0.1, 0.2, 0.3])
    end
  end

  describe "#update" do
    before do
      allow(mock_connection).to receive(:exec_params)
        .with(/SELECT EXISTS/, ["test_index"])
        .and_return([{ "exists" => true }])

      allow(mock_connection).to receive(:exec_params)
        .with(/UPDATE/, anything)
        .and_return([])
    end

    it "updates metadata" do
      result = provider.update(
        index: "test_index",
        id: "vec1",
        metadata: { updated: true }
      )

      expect(result[:updated]).to be true
    end

    it "updates values" do
      allow(mock_connection).to receive(:exec_params)
        .with(/embedding = \$1::vector/, anything)
        .and_return([])

      provider.update(index: "test_index", id: "vec1", values: [0.1, 0.2])

      expect(mock_connection).to have_received(:exec_params)
        .with(/embedding = \$1::vector/, anything)
    end
  end

  describe "#delete" do
    before do
      allow(mock_connection).to receive(:exec_params)
        .with(/SELECT EXISTS/, ["test_index"])
        .and_return([{ "exists" => true }])

      allow(mock_connection).to receive(:exec_params)
        .with(/DELETE FROM/, anything)
        .and_return([])
    end

    it "deletes by IDs" do
      result = provider.delete(index: "test_index", ids: ["vec1", "vec2"])

      expect(result[:deleted]).to be true
    end

    it "deletes all when specified" do
      allow(mock_connection).to receive(:exec_params)
        .with(/DELETE FROM "test_index"$/, [])
        .and_return([])

      provider.delete(index: "test_index", delete_all: true)

      expect(mock_connection).to have_received(:exec_params)
        .with(/DELETE FROM "test_index"$/, [])
    end

    it "deletes by filter" do
      allow(mock_connection).to receive(:exec_params)
        .with(/metadata->>\$1 = \$2/, ["category", "old"])
        .and_return([])

      provider.delete(index: "test_index", filter: { category: "old" })

      expect(mock_connection).to have_received(:exec_params)
        .with(/metadata->>\$1 = \$2/, ["category", "old"])
    end
  end

  describe "#list_indexes" do
    before do
      allow(mock_connection).to receive(:exec_params)
        .with(/information_schema\.columns/, [])
        .and_return([{ "table_name" => "documents" }])

      allow(mock_connection).to receive(:exec_params)
        .with(/pg_attribute/, ["documents"])
        .and_return([{ "data_type" => "vector(384)" }])

      allow(mock_connection).to receive(:exec_params)
        .with(/obj_description/, ["documents"])
        .and_return([{ "comment" => "vectra:metric=cosine" }])
    end

    it "returns list of indexes" do
      result = provider.list_indexes

      expect(result).to be_an(Array)
      expect(result.first[:name]).to eq("documents")
    end
  end

  describe "#describe_index" do
    before do
      allow(mock_connection).to receive(:exec_params)
        .with(/pg_attribute/, ["test_index"])
        .and_return([{ "data_type" => "vector(384)" }])

      allow(mock_connection).to receive(:exec_params)
        .with(/obj_description/, ["test_index"])
        .and_return([{ "comment" => "vectra:metric=cosine" }])
    end

    it "returns index details" do
      result = provider.describe_index(index: "test_index")

      expect(result[:name]).to eq("test_index")
      expect(result[:dimension]).to eq(384)
      expect(result[:metric]).to eq("cosine")
      expect(result[:status]).to eq("ready")
    end

    it "raises NotFoundError for missing index" do
      allow(mock_connection).to receive(:exec_params)
        .with(/pg_attribute/, ["missing"])
        .and_return([])

      expect { provider.describe_index(index: "missing") }
        .to raise_error(Vectra::NotFoundError)
    end
  end

  describe "#stats" do
    before do
      allow(mock_connection).to receive(:exec_params)
        .with(/SELECT EXISTS/, ["test_index"])
        .and_return([{ "exists" => true }])

      allow(mock_connection).to receive(:exec_params)
        .with(/SELECT COUNT/, anything)
        .and_return([{ "count" => "1000" }])

      allow(mock_connection).to receive(:exec_params)
        .with(/GROUP BY namespace/, [])
        .and_return([{ "namespace" => "", "count" => "800" }, { "namespace" => "prod", "count" => "200" }])

      allow(mock_connection).to receive(:exec_params)
        .with(/pg_attribute/, ["test_index"])
        .and_return([{ "data_type" => "vector(384)" }])

      allow(mock_connection).to receive(:exec_params)
        .with(/obj_description/, ["test_index"])
        .and_return([{ "comment" => nil }])
    end

    it "returns statistics" do
      result = provider.stats(index: "test_index")

      expect(result[:total_vector_count]).to eq(1000)
      expect(result[:dimension]).to eq(384)
      expect(result[:namespaces]).to include("" => { vector_count: 800 })
    end
  end

  describe "#create_index" do
    before do
      allow(mock_connection).to receive(:exec_params).and_return([])

      allow(mock_connection).to receive(:exec_params)
        .with(/pg_attribute/, ["new_index"])
        .and_return([{ "data_type" => "vector(384)" }])

      allow(mock_connection).to receive(:exec_params)
        .with(/obj_description/, ["new_index"])
        .and_return([{ "comment" => "vectra:metric=cosine" }])
    end

    it "creates table with vector column" do
      allow(mock_connection).to receive(:exec_params)
        .with(/CREATE TABLE IF NOT EXISTS.*vector\(384\)/, [])
        .and_return([])

      provider.create_index(name: "new_index", dimension: 384)

      expect(mock_connection).to have_received(:exec_params)
        .with(/CREATE TABLE IF NOT EXISTS.*vector\(384\)/, [])
    end

    it "creates IVFFlat index" do
      allow(mock_connection).to receive(:exec_params)
        .with(/CREATE INDEX.*USING ivfflat/, [])
        .and_return([])

      provider.create_index(name: "new_index", dimension: 384)

      expect(mock_connection).to have_received(:exec_params)
        .with(/CREATE INDEX.*USING ivfflat/, [])
    end

    it "stores metric in table comment" do
      allow(mock_connection).to receive(:exec_params)
        .with(/COMMENT ON TABLE.*vectra:metric=euclidean/, [])
        .and_return([])

      provider.create_index(name: "new_index", dimension: 384, metric: "euclidean")

      expect(mock_connection).to have_received(:exec_params)
        .with(/COMMENT ON TABLE.*vectra:metric=euclidean/, [])
    end
  end

  describe "#delete_index" do
    before do
      allow(mock_connection).to receive(:exec_params)
        .with(/DROP TABLE/, [])
        .and_return([])
    end

    it "drops the table" do
      result = provider.delete_index(name: "old_index")

      expect(result[:deleted]).to be true
    end
  end

  describe "error handling" do
    it "raises NotFoundError for undefined table" do
      allow(mock_connection).to receive(:exec_params)
        .and_raise(PG::UndefinedTable.new("relation does not exist"))

      expect { provider.list_indexes }
        .to raise_error(Vectra::NotFoundError)
    end

    it "raises AuthenticationError for invalid password" do
      allow(mock_connection).to receive(:exec_params)
        .and_raise(PG::InvalidPassword.new("password authentication failed"))

      expect { provider.list_indexes }
        .to raise_error(Vectra::AuthenticationError)
    end

    it "raises ValidationError for constraint violations" do
      allow(mock_connection).to receive(:exec_params)
        .and_raise(PG::UniqueViolation.new("duplicate key"))

      expect { provider.list_indexes }
        .to raise_error(Vectra::ValidationError)
    end
  end

  describe "configuration validation" do
    it "raises error when host is not configured" do
      config.host = nil

      expect { described_class.new(config) }
        .to raise_error(Vectra::ConfigurationError, /host.*must be configured/i)
    end

    it "accepts connection URL" do
      config.host = "postgres://user:pass@localhost/db"

      expect { described_class.new(config) }.not_to raise_error
    end
  end
end
