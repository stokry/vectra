# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::Migration do
  let(:source_client) { Vectra::Client.new(provider: :memory) }
  let(:target_client) { Vectra::Client.new(provider: :memory) }
  let(:migration) { described_class.new(source_client, target_client) }

  let(:test_vectors) do
    10.times.map do |i|
      {
        id: "vec_#{i}",
        values: Array.new(3) { rand },
        metadata: { index: i, name: "Vector #{i}" }
      }
    end
  end

  before do
    # Populate source index
    source_client.upsert(index: "source-index", vectors: test_vectors)
  end

  describe "#initialize" do
    it "accepts source and target clients" do
      expect(migration.source_client).to eq(source_client)
      expect(migration.target_client).to eq(target_client)
    end

    it "raises error if source client is nil" do
      expect do
        described_class.new(nil, target_client)
      end.to raise_error(ArgumentError, /Source client cannot be nil/)
    end

    it "raises error if target client is nil" do
      expect do
        described_class.new(source_client, nil)
      end.to raise_error(ArgumentError, /Target client cannot be nil/)
    end
  end

  describe "#migrate" do
    it "migrates vectors from source to target" do
      result = migration.migrate(
        source_index: "source-index",
        target_index: "target-index"
      )

      expect(result[:migrated_count]).to eq(10)
      expect(result[:batches]).to be_positive
      expect(result[:errors]).to be_empty
    end

    it "migrates with different namespaces" do
      result = migration.migrate(
        source_index: "source-index",
        target_index: "target-index",
        source_namespace: nil,
        target_namespace: "new-namespace"
      )

      expect(result[:migrated_count]).to eq(10)

      # Verify vectors are in target namespace
      stats = target_client.stats(index: "target-index", namespace: "new-namespace")
      expect(stats[:total_vector_count]).to eq(10)
    end

    it "migrates with custom batch size" do
      result = migration.migrate(
        source_index: "source-index",
        target_index: "target-index",
        batch_size: 3,
        chunk_size: 2
      )

      expect(result[:migrated_count]).to eq(10)
      expect(result[:batches]).to be >= 4 # 10 vectors / 3 batch_size = at least 4 batches
    end

    it "calls progress callback" do
      progress_calls = []
      on_progress = lambda do |stats|
        progress_calls << stats
      end

      migration.migrate(
        source_index: "source-index",
        target_index: "target-index",
        on_progress: on_progress
      )

      expect(progress_calls).not_to be_empty
      expect(progress_calls.last[:migrated]).to eq(10)
      expect(progress_calls.last[:percentage]).to be_between(0, 100)
    end

    it "handles empty source index" do
      empty_client = Vectra::Client.new(provider: :memory)
      migration = described_class.new(empty_client, target_client)

      result = migration.migrate(
        source_index: "empty-index",
        target_index: "target-index"
      )

      expect(result[:migrated_count]).to eq(0)
      expect(result[:errors]).to be_empty
    end

    it "continues migration on batch errors" do
      # Make target client fail on some operations
      allow(target_client).to receive(:upsert).and_call_original
      allow(target_client).to receive(:upsert).with(
        hash_including(index: "target-index", vectors: anything)
      ).and_raise(StandardError, "Test error").once

      result = migration.migrate(
        source_index: "source-index",
        target_index: "target-index",
        batch_size: 3
      )

      # Should still migrate some vectors despite errors
      expect(result[:migrated_count]).to be < 10
      expect(result[:errors]).not_to be_empty
    end

    it "verifies migrated vectors match source" do
      migration.migrate(
        source_index: "source-index",
        target_index: "target-index"
      )

      # Fetch from both and compare
      source_vectors = source_client.fetch(
        index: "source-index",
        ids: test_vectors.map { |v| v[:id] }
      )
      target_vectors = target_client.fetch(
        index: "target-index",
        ids: test_vectors.map { |v| v[:id] }
      )

      expect(target_vectors.keys).to match_array(source_vectors.keys)
      test_vectors.each do |vec|
        target_vec = target_vectors[vec[:id]]
        expect(target_vec).not_to be_nil
        expect(target_vec.values).to eq(vec[:values])
        # Metadata keys may be strings or symbols depending on provider
        expect(target_vec.metadata.transform_keys(&:to_sym)).to eq(vec[:metadata].transform_keys(&:to_sym))
      end
    end
  end

  describe "#verify" do
    before do
      migration.migrate(
        source_index: "source-index",
        target_index: "target-index"
      )
    end

    it "compares vector counts between source and target" do
      result = migration.verify(
        source_index: "source-index",
        target_index: "target-index"
      )

      expect(result[:source_count]).to eq(10)
      expect(result[:target_count]).to eq(10)
      expect(result[:match]).to be true
    end

    it "handles namespace verification" do
      result = migration.verify(
        source_index: "source-index",
        target_index: "target-index",
        source_namespace: nil,
        target_namespace: nil
      )

      expect(result[:match]).to be true
    end

    it "detects mismatched counts" do
      # Add extra vector to target
      target_client.upsert(
        index: "target-index",
        vectors: [{ id: "extra", values: [0.1, 0.2, 0.3] }]
      )

      result = migration.verify(
        source_index: "source-index",
        target_index: "target-index"
      )

      expect(result[:match]).to be false
      expect(result[:source_count]).to eq(10)
      expect(result[:target_count]).to eq(11)
    end
  end
end
