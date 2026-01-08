# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "sqlite3"

# Setup in-memory SQLite database for testing
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Create test table
ActiveRecord::Schema.define do
  create_table :test_documents, force: true do |t|
    t.string :title
    t.text :content
    t.string :category
    t.text :embedding # JSON array as text
    t.timestamps
  end
end

RSpec.describe Vectra::ActiveRecord do
  # Test model
  let(:test_model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_documents"

      include Vectra::ActiveRecord

      has_vector :embedding,
                  dimension: 3,
                  provider: :pgvector,
                  index: "test_docs",
                  auto_index: true,
                  metadata_fields: [:title, :category]

      # Serialize embedding as JSON
      serialize :embedding, Array
    end
  end

  let(:mock_client) { instance_double(Vectra::Client) }
  let(:test_vector) { [0.1, 0.2, 0.3] }
  let(:query_vector) { [0.15, 0.25, 0.35] }

  before do
    # Mock the client
    allow(test_model_class).to receive(:vectra_client).and_return(mock_client)
  end

  after do
    # Clean up test records
    test_model_class.delete_all
  end

  describe ".has_vector" do
    it "configures vector settings" do
      config = test_model_class._vectra_config

      expect(config[:attribute]).to eq(:embedding)
      expect(config[:dimension]).to eq(3)
      expect(config[:provider]).to eq(:pgvector)
      expect(config[:index]).to eq("test_docs")
      expect(config[:auto_index]).to be true
      expect(config[:metadata_fields]).to eq([:title, :category])
    end

    it "uses table_name as default index" do
      model_class = Class.new(ActiveRecord::Base) do
        self.table_name = "custom_table"
        include Vectra::ActiveRecord
        has_vector :embedding, dimension: 3
      end

      expect(model_class._vectra_config[:index]).to eq("custom_table")
    end

    it "uses global provider by default" do
      allow(Vectra.configuration).to receive(:provider).and_return(:pinecone)

      model_class = Class.new(ActiveRecord::Base) do
        self.table_name = "test"
        include Vectra::ActiveRecord
        has_vector :embedding, dimension: 3
      end

      expect(model_class._vectra_config[:provider]).to eq(:pinecone)
    end

    it "registers auto-index callbacks when enabled" do
      callbacks = test_model_class._save_callbacks.map(&:filter)
      expect(callbacks).to include(:_vectra_index_vector)

      destroy_callbacks = test_model_class._destroy_callbacks.map(&:filter)
      expect(destroy_callbacks).to include(:_vectra_delete_vector)
    end

    it "does not register callbacks when auto_index is false" do
      model_class = Class.new(ActiveRecord::Base) do
        self.table_name = "test_documents"
        include Vectra::ActiveRecord
        has_vector :embedding, dimension: 3, auto_index: false
        serialize :embedding, Array
      end

      callbacks = model_class._save_callbacks.map(&:filter)
      expect(callbacks).not_to include(:_vectra_index_vector)
    end
  end

  describe ".vectra_client" do
    it "creates a client with configured provider" do
      # Reset memoization
      test_model_class.instance_variable_set(:@_vectra_client, nil)

      expect(Vectra::Client).to receive(:new).with(provider: :pgvector).and_return(mock_client)
      expect(test_model_class.vectra_client).to eq(mock_client)
    end

    it "memoizes the client" do
      test_model_class.instance_variable_set(:@_vectra_client, mock_client)

      expect(Vectra::Client).not_to receive(:new)
      expect(test_model_class.vectra_client).to eq(mock_client)
      expect(test_model_class.vectra_client).to eq(mock_client) # Second call
    end
  end

  describe ".vector_search" do
    let(:mock_results) do
      [
        Vectra::QueryResult::Match.new(id: "test_docs_1", score: 0.95, metadata: { title: "Doc 1" }),
        Vectra::QueryResult::Match.new(id: "test_docs_2", score: 0.85, metadata: { title: "Doc 2" })
      ]
    end

    let(:mock_query_result) do
      instance_double(Vectra::QueryResult, matches: mock_results, map: mock_results)
    end

    before do
      test_model_class.create!(id: 1, title: "Doc 1", embedding: test_vector)
      test_model_class.create!(id: 2, title: "Doc 2", embedding: test_vector)
    end

    it "queries the vector index" do
      allow(mock_query_result).to receive(:above_score).and_return(mock_query_result)
      allow(mock_query_result).to receive(:map).and_yield(mock_results[0]).and_yield(mock_results[1]).and_return([])

      expect(mock_client).to receive(:query).with(
        index: "test_docs",
        vector: query_vector,
        top_k: 10,
        filter: {}
      ).and_return(mock_query_result)

      test_model_class.vector_search(query_vector, limit: 10)
    end

    it "applies score threshold filter" do
      expect(mock_client).to receive(:query).and_return(mock_query_result)
      expect(mock_query_result).to receive(:above_score).with(0.9).and_return(mock_query_result)
      allow(mock_query_result).to receive(:map).and_return([])

      test_model_class.vector_search(query_vector, score_threshold: 0.9)
    end

    it "returns raw results when load_records is false" do
      expect(mock_client).to receive(:query).and_return(mock_query_result)
      allow(mock_query_result).to receive(:above_score).and_return(mock_query_result)

      results = test_model_class.vector_search(query_vector, load_records: false)
      expect(results).to eq(mock_query_result)
    end

    it "loads ActiveRecord objects by default" do
      allow(mock_query_result).to receive(:above_score).and_return(mock_query_result)
      allow(mock_query_result).to receive(:map).and_yield(mock_results[0]).and_yield(mock_results[1])

      expect(mock_client).to receive(:query).and_return(mock_query_result)

      records = test_model_class.vector_search(query_vector)

      expect(records).to be_an(Array)
      expect(records.compact.first).to be_a(test_model_class)
    end

    it "adds vector_score to loaded records" do
      record1 = test_model_class.find(1)
      record2 = test_model_class.find(2)

      allow(mock_query_result).to receive(:above_score).and_return(mock_query_result)
      allow(mock_query_result).to receive(:map).and_yield(mock_results[0]).and_yield(mock_results[1]).and_return([record1, record2])
      allow(test_model_class).to receive(:where).and_return(test_model_class.where(id: [1, 2]))

      expect(mock_client).to receive(:query).and_return(mock_query_result)

      records = test_model_class.vector_search(query_vector)
      expect(records.first).to respond_to(:vector_score)
    end
  end

  describe ".similar_to" do
    let(:record) { test_model_class.create!(title: "Test", embedding: test_vector) }

    it "searches using record's vector" do
      expect(test_model_class).to receive(:_vectra_search).with(
        test_vector,
        limit: 10,
        filter: {}
      ).and_return([])

      test_model_class.similar_to(record)
    end

    it "raises error if record has no vector" do
      record_without_vector = test_model_class.new(title: "No Vector")

      expect do
        test_model_class.similar_to(record_without_vector)
      end.to raise_error(ArgumentError, "Record has no vector")
    end

    it "passes options to search" do
      expect(test_model_class).to receive(:_vectra_search).with(
        test_vector,
        limit: 5,
        filter: { category: "tech" }
      ).and_return([])

      test_model_class.similar_to(record, limit: 5, filter: { category: "tech" })
    end
  end

  describe "#index_vector!" do
    let(:record) do
      test_model_class.create!(
        title: "Test Document",
        category: "tech",
        embedding: test_vector
      )
    end

    it "upserts vector to index with metadata" do
      expect(mock_client).to receive(:upsert).with(
        index: "test_docs",
        vectors: [{
          id: "test_docs_#{record.id}",
          values: test_vector,
          metadata: { "title" => "Test Document", "category" => "tech" }
        }]
      )

      record.index_vector!
    end

    it "raises error if vector is nil" do
      record.embedding = nil

      expect do
        record.index_vector!
      end.to raise_error(ArgumentError, "embedding is nil")
    end

    it "includes only existing metadata fields" do
      # Test with missing metadata field
      allow(record).to receive(:respond_to?).with(:title).and_return(true)
      allow(record).to receive(:respond_to?).with(:category).and_return(false)
      allow(record).to receive(:title).and_return("Test")

      expect(mock_client).to receive(:upsert).with(
        index: "test_docs",
        vectors: [hash_including(metadata: { "title" => "Test" })]
      )

      record.index_vector!
    end
  end

  describe "#delete_vector!" do
    let(:record) { test_model_class.create!(title: "Test", embedding: test_vector) }

    it "deletes vector from index" do
      expect(mock_client).to receive(:delete).with(
        index: "test_docs",
        ids: ["test_docs_#{record.id}"]
      )

      record.delete_vector!
    end
  end

  describe "#similar" do
    let(:record) { test_model_class.create!(id: 1, title: "Test", embedding: test_vector) }
    let(:similar_record) { test_model_class.create!(id: 2, title: "Similar", embedding: test_vector) }

    before do
      # Create similar record
      similar_record
    end

    it "finds similar records" do
      expect(test_model_class).to receive(:_vectra_search).with(
        test_vector,
        limit: 11, # limit + 1 to account for self-exclusion
        filter: {}
      ).and_return([record, similar_record])

      results = record.similar(limit: 10)
      expect(results).to eq([similar_record])
      expect(results).not_to include(record) # Excludes self
    end

    it "raises error if vector is nil" do
      record.embedding = nil

      expect do
        record.similar
      end.to raise_error(ArgumentError, "embedding is nil")
    end

    it "applies filters" do
      expect(test_model_class).to receive(:_vectra_search).with(
        test_vector,
        limit: 6,
        filter: { category: "tech" }
      ).and_return([])

      record.similar(limit: 5, filter: { category: "tech" })
    end
  end

  describe "auto-indexing callbacks" do
    context "when auto_index is enabled" do
      it "indexes vector on create" do
        expect(mock_client).to receive(:upsert).once

        test_model_class.create!(title: "New Doc", embedding: test_vector)
      end

      it "indexes vector on update when embedding changes" do
        record = test_model_class.create!(title: "Doc", embedding: test_vector)
        allow(mock_client).to receive(:upsert) # Allow create call

        new_vector = [0.4, 0.5, 0.6]
        expect(mock_client).to receive(:upsert).with(
          index: "test_docs",
          vectors: [hash_including(values: new_vector)]
        )

        record.update!(embedding: new_vector)
      end

      it "does not index if embedding unchanged" do
        record = test_model_class.create!(title: "Doc", embedding: test_vector)
        allow(mock_client).to receive(:upsert).once # Only create call

        expect(mock_client).not_to receive(:upsert)
        record.update!(title: "New Title")
      end

      it "deletes vector on destroy" do
        record = test_model_class.create!(title: "Doc", embedding: test_vector)
        allow(mock_client).to receive(:upsert) # Allow create call

        expect(mock_client).to receive(:delete).with(
          index: "test_docs",
          ids: ["test_docs_#{record.id}"]
        )

        record.destroy!
      end

      it "handles indexing errors gracefully" do
        allow(mock_client).to receive(:upsert).and_raise(StandardError.new("Index error"))
        stub_const("Rails", double(logger: double(error: nil)))

        expect do
          test_model_class.create!(title: "Doc", embedding: test_vector)
        end.not_to raise_error
      end

      it "handles deletion errors gracefully" do
        record = test_model_class.create!(title: "Doc", embedding: test_vector)
        allow(mock_client).to receive(:upsert) # Allow create
        allow(mock_client).to receive(:delete).and_raise(StandardError.new("Delete error"))
        stub_const("Rails", double(logger: double(error: nil)))

        expect do
          record.destroy!
        end.not_to raise_error
      end
    end
  end

  describe "#_vectra_vector_id" do
    it "generates ID with index prefix" do
      record = test_model_class.create!(id: 123, title: "Test", embedding: test_vector)
      allow(mock_client).to receive(:upsert) # Mock create upsert

      expect(record.send(:_vectra_vector_id)).to eq("test_docs_123")
    end
  end
end
