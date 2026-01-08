# frozen_string_literal: true

require "spec_helper"

# Mock New Relic Agent
module NewRelic
  module Agent
    class << self
      def record_metric(name, value); end

      def add_custom_attributes(attrs); end

      def notice_error(error); end
    end
  end
end

RSpec.describe Vectra::Instrumentation::NewRelic do
  let(:new_relic_agent) { NewRelic::Agent }

  before do
    Vectra::Instrumentation.clear_handlers!
    Vectra.configuration.instrumentation = true
  end

  after do
    Vectra::Instrumentation.clear_handlers!
    Vectra.configuration.instrumentation = false
  end

  describe ".setup!" do
    it "registers instrumentation handler" do
      expect(Vectra::Instrumentation).to receive(:on_operation)

      described_class.setup!
    end

    it "does nothing if New Relic is not available" do
      hide_const("NewRelic::Agent")

      expect(Vectra::Instrumentation).not_to receive(:on_operation)

      described_class.setup!
    end

    it "handles events after setup" do
      described_class.setup!

      event = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :pgvector,
        index: "test",
        duration: 123.45,
        metadata: {}
      )

      expect(new_relic_agent).to receive(:record_metric).at_least(:once)
      expect(new_relic_agent).to receive(:add_custom_attributes)

      Vectra::Instrumentation.send(:notify_handlers, event)
    end
  end

  describe "metrics recording" do
    before do
      described_class.setup!
    end

    context "for successful operations" do
      let(:event) do
        Vectra::Instrumentation::Event.new(
          operation: :query,
          provider: :pinecone,
          index: "documents",
          duration: 45.67,
          metadata: { result_count: 10 }
        )
      end

      it "records duration metric" do
        expect(new_relic_agent).to receive(:record_metric).with(
          "Custom/Vectra/pinecone/query/duration",
          45.67
        )

        expect(new_relic_agent).to receive(:record_metric).at_least(:once)
        allow(new_relic_agent).to receive(:add_custom_attributes)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "records call count metric" do
        expect(new_relic_agent).to receive(:record_metric).with(
          "Custom/Vectra/pinecone/query/calls",
          1
        )

        expect(new_relic_agent).to receive(:record_metric).at_least(:once)
        allow(new_relic_agent).to receive(:add_custom_attributes)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "records success metric" do
        expect(new_relic_agent).to receive(:record_metric).with(
          "Custom/Vectra/pinecone/query/success",
          1
        )

        expect(new_relic_agent).to receive(:record_metric).at_least(:once)
        allow(new_relic_agent).to receive(:add_custom_attributes)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "records result count if available" do
        expect(new_relic_agent).to receive(:record_metric).with(
          "Custom/Vectra/pinecone/query/results",
          10
        )

        expect(new_relic_agent).to receive(:record_metric).at_least(:once)
        allow(new_relic_agent).to receive(:add_custom_attributes)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "does not record result count if not available" do
        event_without_count = Vectra::Instrumentation::Event.new(
          operation: :query,
          provider: :pinecone,
          index: "documents",
          duration: 45.67,
          metadata: {}
        )

        expect(new_relic_agent).not_to receive(:record_metric).with(
          /results/,
          anything
        )

        expect(new_relic_agent).to receive(:record_metric).at_least(:once)
        allow(new_relic_agent).to receive(:add_custom_attributes)

        Vectra::Instrumentation.send(:notify_handlers, event_without_count)
      end
    end

    context "for failed operations" do
      let(:error) { StandardError.new("Test error") }
      let(:event) do
        Vectra::Instrumentation::Event.new(
          operation: :upsert,
          provider: :pgvector,
          index: "test",
          duration: 100.0,
          metadata: {},
          error: error
        )
      end

      it "records error metric" do
        expect(new_relic_agent).to receive(:record_metric).with(
          "Custom/Vectra/pgvector/upsert/error",
          1
        )

        expect(new_relic_agent).to receive(:record_metric).at_least(:once)
        allow(new_relic_agent).to receive(:add_custom_attributes)
        allow(new_relic_agent).to receive(:notice_error)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "does not record success metric" do
        expect(new_relic_agent).not_to receive(:record_metric).with(
          /success/,
          anything
        )

        expect(new_relic_agent).to receive(:record_metric).at_least(:once)
        allow(new_relic_agent).to receive(:add_custom_attributes)
        allow(new_relic_agent).to receive(:notice_error)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "notifies New Relic of the error" do
        expect(new_relic_agent).to receive(:notice_error).with(error)

        allow(new_relic_agent).to receive(:record_metric)
        allow(new_relic_agent).to receive(:add_custom_attributes)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end
    end
  end

  describe "transaction attributes" do
    before do
      described_class.setup!
    end

    let(:event) do
      Vectra::Instrumentation::Event.new(
        operation: :fetch,
        provider: :qdrant,
        index: "embeddings",
        duration: 23.45,
        metadata: {}
      )
    end

    it "adds custom attributes to transaction" do
      expect(new_relic_agent).to receive(:add_custom_attributes).with(
        vectra_operation: :fetch,
        vectra_provider: :qdrant,
        vectra_index: "embeddings",
        vectra_duration: 23.45
      )

      allow(new_relic_agent).to receive(:record_metric)

      Vectra::Instrumentation.send(:notify_handlers, event)
    end

    it "includes all event details" do
      custom_event = Vectra::Instrumentation::Event.new(
        operation: :delete,
        provider: :weaviate,
        index: "vectors",
        duration: 56.78,
        metadata: { ids: [1, 2, 3] }
      )

      expect(new_relic_agent).to receive(:add_custom_attributes).with(
        hash_including(
          vectra_operation: :delete,
          vectra_provider: :weaviate,
          vectra_index: "vectors"
        )
      )

      allow(new_relic_agent).to receive(:record_metric)

      Vectra::Instrumentation.send(:notify_handlers, custom_event)
    end
  end

  describe "different operation types" do
    before do
      described_class.setup!
      allow(new_relic_agent).to receive(:add_custom_attributes)
    end

    it "handles upsert operations" do
      event = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :pgvector,
        index: "test",
        duration: 50.0,
        metadata: { vector_count: 100 }
      )

      expect(new_relic_agent).to receive(:record_metric).with(
        "Custom/Vectra/pgvector/upsert/duration",
        50.0
      )

      expect(new_relic_agent).to receive(:record_metric).at_least(:once)

      Vectra::Instrumentation.send(:notify_handlers, event)
    end

    it "handles query operations" do
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "docs",
        duration: 30.0,
        metadata: { result_count: 5 }
      )

      expect(new_relic_agent).to receive(:record_metric).with(
        "Custom/Vectra/pinecone/query/duration",
        30.0
      )

      expect(new_relic_agent).to receive(:record_metric).at_least(:once)

      Vectra::Instrumentation.send(:notify_handlers, event)
    end

    it "handles delete operations" do
      event = Vectra::Instrumentation::Event.new(
        operation: :delete,
        provider: :qdrant,
        index: "vectors",
        duration: 20.0,
        metadata: {}
      )

      expect(new_relic_agent).to receive(:record_metric).with(
        "Custom/Vectra/qdrant/delete/duration",
        20.0
      )

      expect(new_relic_agent).to receive(:record_metric).at_least(:once)

      Vectra::Instrumentation.send(:notify_handlers, event)
    end
  end

  describe "integration with Vectra::Instrumentation" do
    it "works with actual instrumentation flow" do
      described_class.setup!

      expect(new_relic_agent).to receive(:record_metric).at_least(:once)
      expect(new_relic_agent).to receive(:add_custom_attributes)

      Vectra::Instrumentation.instrument(
        operation: :test,
        provider: :test_provider,
        index: "test_index",
        metadata: {}
      ) do
        "test result"
      end
    end

    it "handles errors during instrumentation" do
      described_class.setup!

      expect(new_relic_agent).to receive(:record_metric).at_least(:once)
      expect(new_relic_agent).to receive(:add_custom_attributes)
      expect(new_relic_agent).to receive(:notice_error)

      expect do
        Vectra::Instrumentation.instrument(
          operation: :test,
          provider: :test_provider,
          index: "test_index",
          metadata: {}
        ) do
          raise StandardError, "Test error"
        end
      end.to raise_error(StandardError, "Test error")
    end
  end
end
