# frozen_string_literal: true

# Load pg gem first if available to avoid class definition conflicts
begin
  require "pg"
rescue LoadError
  # pg gem not installed - define stub classes for testing
  module PG
    class Error < StandardError; end
    class UndefinedTable < Error; end
    class InvalidPassword < Error; end
    class ConnectionBad < Error; end
    class UniqueViolation < Error; end
    class CheckViolation < Error; end
  end
end

RSpec.describe Vectra::Providers::Pgvector do
  # Storage for executed queries - accessible to all tests
  let(:executed_queries) { [] }

  # Smart mock connection that records ALL queries and returns appropriate results
  let(:mock_connection) do
    queries = executed_queries
    result_handlers = mock_result_handlers

    Class.new do
      define_method(:exec_params) do |sql, params = []|
        queries << { sql: sql, params: params }

        # Find matching handler based on SQL pattern
        handler = result_handlers.find { |pattern, _| sql =~ pattern }
        handler ? handler[1].call(sql, params) : []
      end

      def quote_ident(name)
        "\"#{name}\""
      end

      def escape_literal(str)
        "'#{str}'"
      end
    end.new
  end

  # Default handlers - can be overridden in individual test contexts
  let(:mock_result_handlers) { {} }

  let(:config) do
    cfg = Vectra::Configuration.new
    cfg.instance_variable_set(:@provider, :pgvector)
    cfg.host = "postgres://user:pass@localhost/testdb"
    cfg
  end

  let(:provider) do
    prov = described_class.new(config)
    prov.instance_variable_set(:@connection, mock_connection)
    prov
  end

  # Helper to verify SQL was executed with expected pattern
  def expect_sql_matching(pattern)
    matching = executed_queries.find { |q| q[:sql] =~ pattern }
    expect(matching).not_to be_nil,
                            "Expected SQL matching #{pattern.inspect}, got: #{executed_queries.map { |q| q[:sql] }}"
    matching
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

    let(:mock_result_handlers) do
      {
        /SELECT EXISTS/ => ->(_sql, _params) { [{ "exists" => true }] },
        /INSERT INTO/ => ->(_sql, _params) { [] }
      }
    end

    it "upserts vectors and returns count" do
      result = provider.upsert(index: "test_index", vectors: vectors)

      expect(result[:upserted_count]).to eq(2)
      expect_sql_matching(/INSERT INTO "test_index"/)
    end

    it "generates correct INSERT SQL with ON CONFLICT" do
      provider.upsert(index: "test_index", vectors: vectors)

      insert_query = expect_sql_matching(/INSERT INTO/)
      expect(insert_query[:sql]).to include("ON CONFLICT (id) DO UPDATE")
      expect(insert_query[:sql]).to include("embedding = EXCLUDED.embedding")
    end

    it "includes namespace in upsert params" do
      provider.upsert(index: "test_index", vectors: vectors, namespace: "production")

      insert_query = executed_queries.find { |q| q[:sql] =~ /INSERT INTO/ }
      expect(insert_query[:params]).to include("production")
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

    let(:mock_result_handlers) do
      {
        /SELECT EXISTS/ => ->(_sql, _params) { [{ "exists" => true }] },
        /obj_description/ => ->(_sql, _params) { [{ "comment" => "vectra:metric=cosine" }] },
        /SELECT.*FROM/ => ->(_sql, _params) { mock_results }
      }
    end

    it "returns QueryResult with correct structure" do
      result = provider.query(index: "test_index", vector: query_vector, top_k: 5)

      expect(result).to be_a(Vectra::QueryResult)
      expect(result.size).to eq(2)
      expect(result.first.id).to eq("vec1")
      expect(result.first.score).to eq(0.95)
    end

    it "parses metadata from JSON" do
      result = provider.query(index: "test_index", vector: query_vector)

      expect(result.first.metadata).to eq("text" => "Hello")
    end

    it "generates SQL with cosine distance operator" do
      provider.query(index: "test_index", vector: query_vector, top_k: 5)

      query = expect_sql_matching(/SELECT.*FROM "test_index"/)
      expect(query[:sql]).to include("<=>") # cosine distance operator
      expect(query[:sql]).to include("ORDER BY")
      expect(query[:sql]).to include("LIMIT 5")
    end

    it "includes namespace in WHERE clause when provided" do
      provider.query(index: "test_index", vector: query_vector, namespace: "prod")

      # Use more specific pattern to avoid matching SELECT EXISTS
      query = expect_sql_matching(/SELECT id,.*score.*FROM/)
      expect(query[:sql]).to include("namespace = 'prod'")
    end

    it "includes metadata filter in WHERE clause" do
      provider.query(index: "test_index", vector: query_vector, filter: { category: "tech" })

      # Use more specific pattern to avoid matching SELECT EXISTS
      query = expect_sql_matching(/SELECT id,.*score.*FROM/)
      expect(query[:sql]).to include("metadata->>'category' = 'tech'")
    end
  end

  describe "#fetch" do
    let(:mock_results) do
      [
        { "id" => "vec1", "embedding" => "[0.1,0.2,0.3]", "metadata" => '{"text": "Hello"}' }
      ]
    end

    let(:mock_result_handlers) do
      {
        /SELECT EXISTS/ => ->(_sql, _params) { [{ "exists" => true }] },
        /SELECT id, embedding, metadata/ => ->(_sql, _params) { mock_results }
      }
    end

    it "fetches vectors by IDs and returns Hash with Vector objects" do
      result = provider.fetch(index: "test_index", ids: ["vec1"])

      expect(result).to be_a(Hash)
      expect(result["vec1"]).to be_a(Vectra::Vector)
      expect(result["vec1"].values).to eq([0.1, 0.2, 0.3])
      expect(result["vec1"].metadata).to eq("text" => "Hello")
    end

    it "generates correct SELECT SQL with IN clause for IDs" do
      provider.fetch(index: "test_index", ids: %w[vec1 vec2])

      query = expect_sql_matching(/SELECT id, embedding, metadata/)
      expect(query[:sql]).to include("WHERE id IN")
    end
  end

  describe "#update" do
    let(:mock_result_handlers) do
      {
        /SELECT EXISTS/ => ->(_sql, _params) { [{ "exists" => true }] },
        /UPDATE/ => ->(_sql, _params) { [] }
      }
    end

    it "updates metadata and returns success" do
      result = provider.update(
        index: "test_index",
        id: "vec1",
        metadata: { updated: true }
      )

      expect(result[:updated]).to be true
      query = expect_sql_matching(/UPDATE "test_index"/)
      expect(query[:sql]).to include("metadata = ")
      expect(query[:sql]).to include("WHERE id = ")
    end

    it "generates UPDATE SQL with vector embedding when values provided" do
      provider.update(index: "test_index", id: "vec1", values: [0.1, 0.2, 0.3])

      query = expect_sql_matching(/UPDATE.*SET/)
      expect(query[:sql]).to include("embedding = $1::vector")
    end

    it "combines metadata and values in single UPDATE" do
      provider.update(
        index: "test_index",
        id: "vec1",
        values: [0.1, 0.2],
        metadata: { key: "value" }
      )

      query = expect_sql_matching(/UPDATE/)
      expect(query[:sql]).to include("embedding = $1::vector")
      expect(query[:sql]).to include("metadata = ")
    end
  end

  describe "#delete" do
    let(:mock_result_handlers) do
      {
        /SELECT EXISTS/ => ->(_sql, _params) { [{ "exists" => true }] },
        /DELETE FROM/ => ->(_sql, _params) { [] }
      }
    end

    it "deletes by IDs using WHERE IN clause" do
      result = provider.delete(index: "test_index", ids: %w[vec1 vec2])

      expect(result[:deleted]).to be true
      query = expect_sql_matching(/DELETE FROM "test_index"/)
      expect(query[:sql]).to include("WHERE id IN")
    end

    it "deletes all records when delete_all is true" do
      provider.delete(index: "test_index", delete_all: true)

      query = expect_sql_matching(/DELETE FROM "test_index"/)
      expect(query[:sql]).not_to include("WHERE")
    end

    it "deletes by metadata filter using JSONB operators" do
      provider.delete(index: "test_index", filter: { category: "old" })

      query = expect_sql_matching(/DELETE FROM/)
      expect(query[:params]).to include("category")
      expect(query[:params]).to include("old")
    end

    it "deletes by namespace when specified" do
      provider.delete(index: "test_index", namespace: "staging")

      query = expect_sql_matching(/DELETE FROM/)
      expect(query[:sql]).to include("namespace")
    end
  end

  describe "#list_indexes" do
    let(:mock_result_handlers) do
      {
        /information_schema\.columns/ => lambda { |_sql, _params|
          [{ "table_name" => "documents" }, { "table_name" => "embeddings" }]
        },
        /pg_attribute/ => ->(_sql, _params) { [{ "data_type" => "vector(384)" }] },
        /obj_description/ => ->(_sql, _params) { [{ "comment" => "vectra:metric=cosine" }] }
      }
    end

    it "returns array of indexes with metadata" do
      result = provider.list_indexes

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first[:name]).to eq("documents")
      expect(result.first[:dimension]).to eq(384)
      expect(result.first[:metric]).to eq("cosine")
    end

    it "queries information_schema for vector columns" do
      provider.list_indexes

      query = expect_sql_matching(/information_schema\.columns/)
      expect(query[:sql]).to include("data_type = 'USER-DEFINED'")
      expect(query[:sql]).to include("udt_name = 'vector'")
    end
  end

  describe "#describe_index" do
    context "when index exists" do
      let(:mock_result_handlers) do
        {
          /pg_attribute/ => ->(_sql, _params) { [{ "data_type" => "vector(768)" }] },
          /obj_description/ => ->(_sql, _params) { [{ "comment" => "vectra:metric=euclidean" }] }
        }
      end

      it "returns complete index details" do
        result = provider.describe_index(index: "test_index")

        expect(result[:name]).to eq("test_index")
        expect(result[:dimension]).to eq(768)
        expect(result[:metric]).to eq("euclidean")
        expect(result[:status]).to eq("ready")
      end

      it "extracts dimension from vector type definition" do
        result = provider.describe_index(index: "test_index")

        expect(result[:dimension]).to eq(768)
      end
    end

    context "when index does not exist" do
      let(:mock_result_handlers) do
        {
          /pg_attribute/ => ->(_sql, _params) { [] }
        }
      end

      it "raises NotFoundError" do
        expect { provider.describe_index(index: "missing") }
          .to raise_error(Vectra::NotFoundError, /not found/)
      end
    end
  end

  describe "#stats" do
    let(:mock_result_handlers) do
      {
        /SELECT EXISTS/ => ->(_sql, _params) { [{ "exists" => true }] },
        # GROUP BY must come BEFORE plain COUNT - both queries contain COUNT(*)
        /GROUP BY namespace/ => lambda { |_sql, _params|
          [
            { "namespace" => "", "count" => "1000" },
            { "namespace" => "prod", "count" => "500" }
          ]
        },
        # Plain COUNT query (without GROUP BY)
        /SELECT COUNT\(\*\) as count FROM/ => ->(_sql, _params) { [{ "count" => "1500" }] },
        /pg_attribute/ => ->(_sql, _params) { [{ "data_type" => "vector(512)" }] },
        /obj_description/ => ->(_sql, _params) { [{ "comment" => "vectra:metric=cosine" }] }
      }
    end

    it "returns comprehensive statistics" do
      result = provider.stats(index: "test_index")

      expect(result[:total_vector_count]).to eq(1500)
      expect(result[:dimension]).to eq(512)
      expect(result[:namespaces]).to include("" => { vector_count: 1000 })
      expect(result[:namespaces]).to include("prod" => { vector_count: 500 })
    end

    it "queries COUNT and GROUP BY for namespace breakdown" do
      provider.stats(index: "test_index")

      expect_sql_matching(/SELECT COUNT\(\*\) as count/)
      expect_sql_matching(/GROUP BY namespace/)
    end
  end

  describe "#create_index" do
    let(:mock_result_handlers) do
      {
        /CREATE TABLE/ => ->(_sql, _params) { [] },
        /CREATE INDEX/ => ->(_sql, _params) { [] },
        /COMMENT ON TABLE/ => ->(_sql, _params) { [] },
        /pg_attribute/ => ->(_sql, _params) { [{ "data_type" => "vector(384)" }] },
        /obj_description/ => ->(_sql, _params) { [{ "comment" => "vectra:metric=cosine" }] }
      }
    end

    it "creates table with correct schema" do
      provider.create_index(name: "new_index", dimension: 384)

      query = expect_sql_matching(/CREATE TABLE IF NOT EXISTS/)
      expect(query[:sql]).to include("id TEXT PRIMARY KEY")
      expect(query[:sql]).to include("embedding vector(384)")
      expect(query[:sql]).to include("namespace TEXT")
      expect(query[:sql]).to include("metadata JSONB")
    end

    it "creates IVFFlat index with correct operator" do
      provider.create_index(name: "new_index", dimension: 384, metric: "cosine")

      query = expect_sql_matching(/CREATE INDEX/)
      expect(query[:sql]).to include("USING ivfflat")
      expect(query[:sql]).to include("vector_cosine_ops")
    end

    it "stores metric as table comment for later retrieval" do
      provider.create_index(name: "new_index", dimension: 384, metric: "euclidean")

      query = expect_sql_matching(/COMMENT ON TABLE/)
      expect(query[:sql]).to include("vectra:metric=euclidean")
    end

    it "uses inner_product operator for inner_product metric" do
      provider.create_index(name: "new_index", dimension: 384, metric: "inner_product")

      query = expect_sql_matching(/CREATE INDEX/)
      expect(query[:sql]).to include("vector_ip_ops")
    end
  end

  describe "#delete_index" do
    let(:mock_result_handlers) do
      {
        /DROP TABLE/ => ->(_sql, _params) { [] }
      }
    end

    it "drops the table with CASCADE" do
      result = provider.delete_index(name: "old_index")

      expect(result[:deleted]).to be true
      query = expect_sql_matching(/DROP TABLE/)
      expect(query[:sql]).to include("CASCADE")
      expect(query[:sql]).to include('"old_index"')
    end
  end

  describe "error handling" do
    before do
      allow(mock_connection).to receive(:exec_params)
        .and_raise(error_to_raise)
    end

    context "with PG::UndefinedTable" do
      let(:error_to_raise) { PG::UndefinedTable.new("relation does not exist") }

      it "translates to Vectra::NotFoundError" do
        expect { provider.list_indexes }
          .to raise_error(Vectra::NotFoundError, /not found/i)
      end
    end

    context "with PG::InvalidPassword" do
      let(:error_to_raise) { PG::InvalidPassword.new("password authentication failed") }

      it "translates to Vectra::AuthenticationError" do
        expect { provider.list_indexes }
          .to raise_error(Vectra::AuthenticationError, /authentication/i)
      end
    end

    context "with PG::ConnectionBad" do
      let(:error_to_raise) { PG::ConnectionBad.new("could not connect") }

      it "translates to Vectra::ConnectionError" do
        expect { provider.list_indexes }
          .to raise_error(Vectra::ConnectionError)
      end
    end

    context "with PG::UniqueViolation" do
      let(:error_to_raise) { PG::UniqueViolation.new("duplicate key value") }

      it "translates to Vectra::ValidationError" do
        expect { provider.list_indexes }
          .to raise_error(Vectra::ValidationError)
      end
    end
  end

  describe "configuration validation" do
    it "raises ConfigurationError when host is not configured" do
      config.host = nil

      expect { described_class.new(config) }
        .to raise_error(Vectra::ConfigurationError, /host.*must be configured/i)
    end

    it "accepts PostgreSQL connection URL format" do
      config.host = "postgres://user:pass@localhost:5432/mydb"

      new_provider = described_class.new(config)
      expect(new_provider.provider_name).to eq(:pgvector)
    end

    it "accepts simple hostname format" do
      config.host = "localhost"

      new_provider = described_class.new(config)
      expect(new_provider.provider_name).to eq(:pgvector)
    end
  end

  describe "SQL injection prevention" do
    let(:mock_result_handlers) do
      {
        /SELECT EXISTS/ => ->(_sql, _params) { [{ "exists" => true }] },
        /DELETE FROM/ => ->(_sql, _params) { [] },
        /INSERT INTO/ => ->(_sql, _params) { [] }
      }
    end

    it "uses parameterized queries for user input" do
      provider.delete(index: "test_index", ids: ["id'; DROP TABLE users; --"])

      query = expect_sql_matching(/DELETE FROM/)
      # Verify the dangerous string is in params, not interpolated in SQL
      expect(query[:params]).to include("id'; DROP TABLE users; --")
    end

    it "properly escapes table names" do
      provider.upsert(
        index: "table\"; DROP TABLE users; --",
        vectors: [{ id: "1", values: [0.1] }]
      )

      # Table name should be properly quoted
      query = expect_sql_matching(/INSERT INTO/)
      expect(query[:sql]).to include('"table"; DROP TABLE users; --"')
    end
  end

  describe "#text_search" do
    let(:query_text) { "ruby programming" }
    let(:mock_results) do
      [
        { "id" => "vec1", "score" => "0.95", "metadata" => '{"text": "Ruby guide"}' },
        { "id" => "vec2", "score" => "0.90", "metadata" => '{"text": "Programming tips"}' }
      ]
    end

    let(:mock_result_handlers) do
      {
        /SELECT EXISTS/ => ->(_sql, _params) { [{ "exists" => true }] },
        /SELECT.*FROM "test_index"/ => ->(_sql, _params) { mock_results }
      }
    end

    it "performs text search using PostgreSQL full-text search" do
      result = provider.text_search(
        index: "test_index",
        text: query_text,
        top_k: 5
      )

      expect(result).to be_a(Vectra::QueryResult)
      expect(result.size).to eq(2)
      expect(result.first.score).to eq(0.95)
      expect(result.first.id).to eq("vec1")
    end

    it "generates SQL with to_tsvector and plainto_tsquery" do
      provider.text_search(index: "test_index", text: query_text, top_k: 5)

      query = expect_sql_matching(/SELECT.*FROM "test_index"/)
      expect(query[:sql]).to include("to_tsvector")
      expect(query[:sql]).to include("plainto_tsquery")
      expect(query[:sql]).to include("ts_rank")
    end

    it "includes text column parameter" do
      provider.text_search(
        index: "test_index",
        text: query_text,
        top_k: 5,
        text_column: "description"
      )

      query = expect_sql_matching(/SELECT.*FROM "test_index"/)
      expect(query[:sql]).to include('"description"')
    end

    it "includes namespace in WHERE clause when provided" do
      provider.text_search(
        index: "test_index",
        text: query_text,
        top_k: 10,
        namespace: "prod"
      )

      query = expect_sql_matching(/SELECT id,.*score.*FROM/)
      expect(query[:sql]).to include("namespace = 'prod'")
    end
  end
end
