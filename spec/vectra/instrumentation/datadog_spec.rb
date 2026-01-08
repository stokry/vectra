# frozen_string_literal: true

require "spec_helper"

# Mock Datadog StatsD - must be defined BEFORE loading the instrumentation module
# and we need to pretend the gem is already loaded
module Datadog
  class Statsd
    attr_reader :host, :port, :namespace

    def initialize(host, port, namespace: nil)
      @host = host
      @port = port
      @namespace = namespace
    end

    def timing(metric, value, tags: []); end

    def increment(metric, tags: []); end

    def gauge(metric, value, tags: []); end
  end
end

# Pretend the datadog/statsd gem is already loaded so require doesn't fail
$LOADED_FEATURES << "datadog/statsd.rb"

require "vectra/instrumentation/datadog"

RSpec.describe Vectra::Instrumentation::Datadog do
  let(:mock_statsd) { instance_double(Datadog::Statsd) }

  before do
    Vectra::Instrumentation.clear_handlers!
    Vectra.configuration.instrumentation = true
  end

  after do
    Vectra::Instrumentation.clear_handlers!
    Vectra.configuration.instrumentation = false
    described_class.instance_variable_set(:@statsd, nil)
  end

  describe ".setup!" do
    it "initializes DogStatsD client with default options" do
      allow(Datadog::Statsd).to receive(:new).with(
        "localhost",
        8125,
        namespace: "vectra"
      ).and_return(mock_statsd)

      described_class.setup!

      expect(described_class.statsd).to eq(mock_statsd)
      expect(Datadog::Statsd).to have_received(:new).with("localhost", 8125, namespace: "vectra")
    end

    it "accepts custom host and port" do
      allow(Datadog::Statsd).to receive(:new).with(
        "custom-host",
        9125,
        namespace: "vectra"
      ).and_return(mock_statsd)

      described_class.setup!(host: "custom-host", port: 9125)

      expect(Datadog::Statsd).to have_received(:new).with("custom-host", 9125, namespace: "vectra")
    end

    it "accepts custom namespace" do
      allow(Datadog::Statsd).to receive(:new).with(
        "localhost",
        8125,
        namespace: "my_app"
      ).and_return(mock_statsd)

      described_class.setup!(namespace: "my_app")

      expect(Datadog::Statsd).to have_received(:new).with("localhost", 8125, namespace: "my_app")
    end

    it "registers instrumentation handler" do
      allow(Datadog::Statsd).to receive(:new).and_return(mock_statsd)

      expect(Vectra::Instrumentation).to receive(:on_operation)

      described_class.setup!
    end

    it "handles missing Datadog gem gracefully" do
      allow(described_class).to receive(:require).with("datadog/statsd").and_raise(LoadError)

      expect do
        expect(described_class).to receive(:warn).with(/Datadog StatsD gem not found/)
        described_class.setup!
      end.not_to raise_error
    end

    it "handles events after setup" do
      allow(Datadog::Statsd).to receive(:new).and_return(mock_statsd)
      described_class.setup!

      event = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :pgvector,
        index: "test",
        duration: 123.45,
        metadata: {}
      )

      expect(mock_statsd).to receive(:timing).at_least(:once)
      expect(mock_statsd).to receive(:increment).at_least(:once)

      Vectra::Instrumentation.send(:notify_handlers, event)
    end
  end

  describe "metrics recording" do
    before do
      allow(Datadog::Statsd).to receive(:new).and_return(mock_statsd)
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

      let(:expected_tags) do
        [
          "provider:pinecone",
          "operation:query",
          "index:documents",
          "status:success"
        ]
      end

      it "records timing metric" do
        expect(mock_statsd).to receive(:timing).with(
          "operation.duration",
          45.67,
          tags: expected_tags
        )

        expect(mock_statsd).to receive(:increment).at_least(:once)
        allow(mock_statsd).to receive(:gauge)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "records count metric" do
        expect(mock_statsd).to receive(:increment).with(
          "operation.count",
          tags: expected_tags
        )

        allow(mock_statsd).to receive(:timing)
        allow(mock_statsd).to receive(:gauge)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "records result count gauge" do
        expect(mock_statsd).to receive(:gauge).with(
          "operation.results",
          10,
          tags: expected_tags
        )

        allow(mock_statsd).to receive(:timing)
        allow(mock_statsd).to receive(:increment)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "records vector count gauge if available" do
        event_with_vectors = Vectra::Instrumentation::Event.new(
          operation: :upsert,
          provider: :pgvector,
          index: "test",
          duration: 50.0,
          metadata: { vector_count: 100 }
        )

        tags = [
          "provider:pgvector",
          "operation:upsert",
          "index:test",
          "status:success"
        ]

        expect(mock_statsd).to receive(:gauge).with(
          "operation.vectors",
          100,
          tags: tags
        )

        allow(mock_statsd).to receive(:timing)
        allow(mock_statsd).to receive(:increment)

        Vectra::Instrumentation.send(:notify_handlers, event_with_vectors)
      end

      it "does not record vector count if not available" do
        expect(mock_statsd).not_to receive(:gauge).with(
          /vectors/,
          anything,
          anything
        )

        allow(mock_statsd).to receive(:timing)
        allow(mock_statsd).to receive(:increment)
        allow(mock_statsd).to receive(:gauge).with("operation.results", anything, anything)

        Vectra::Instrumentation.send(:notify_handlers, event)
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

      let(:base_tags) do
        [
          "provider:pgvector",
          "operation:upsert",
          "index:test",
          "status:error"
        ]
      end

      it "records error status in tags" do
        expect(mock_statsd).to receive(:timing).with(
          "operation.duration",
          100.0,
          tags: base_tags
        )

        allow(mock_statsd).to receive(:increment)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "increments error counter with error type" do
        error_tags = base_tags + ["error_type:StandardError"]

        expect(mock_statsd).to receive(:increment).with(
          "operation.error",
          tags: error_tags
        )

        allow(mock_statsd).to receive(:timing)
        allow(mock_statsd).to receive(:increment).with("operation.count", anything)

        Vectra::Instrumentation.send(:notify_handlers, event)
      end

      it "includes error class name in tags" do
        custom_error = Class.new(StandardError)
        custom_error_event = Vectra::Instrumentation::Event.new(
          operation: :query,
          provider: :pinecone,
          index: "docs",
          duration: 50.0,
          metadata: {},
          error: custom_error.new("Custom error")
        )

        expect(mock_statsd).to receive(:increment).with(
          "operation.error",
          tags: array_including("error_type:#{custom_error.name}")
        )

        allow(mock_statsd).to receive(:timing)
        allow(mock_statsd).to receive(:increment).with("operation.count", anything)

        Vectra::Instrumentation.send(:notify_handlers, custom_error_event)
      end
    end
  end

  describe "different operation types" do
    before do
      allow(Datadog::Statsd).to receive(:new).and_return(mock_statsd)
      described_class.setup!
    end

    it "handles upsert operations" do
      event = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :pgvector,
        index: "test",
        duration: 50.0,
        metadata: { vector_count: 100 }
      )

      expect(mock_statsd).to receive(:timing).with(
        "operation.duration",
        50.0,
        tags: array_including("operation:upsert")
      )

      allow(mock_statsd).to receive(:increment)
      allow(mock_statsd).to receive(:gauge)

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

      expect(mock_statsd).to receive(:timing).with(
        "operation.duration",
        30.0,
        tags: array_including("operation:query")
      )

      allow(mock_statsd).to receive(:increment)
      allow(mock_statsd).to receive(:gauge)

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

      expect(mock_statsd).to receive(:timing).with(
        "operation.duration",
        20.0,
        tags: array_including("operation:delete")
      )

      allow(mock_statsd).to receive(:increment)

      Vectra::Instrumentation.send(:notify_handlers, event)
    end
  end

  describe "tag generation" do
    before do
      allow(Datadog::Statsd).to receive(:new).and_return(mock_statsd)
      described_class.setup!
    end

    it "includes all required tags" do
      event = Vectra::Instrumentation::Event.new(
        operation: :fetch,
        provider: :weaviate,
        index: "embeddings",
        duration: 15.0,
        metadata: {}
      )

      expected_tags = [
        "provider:weaviate",
        "operation:fetch",
        "index:embeddings",
        "status:success"
      ]

      expect(mock_statsd).to receive(:timing).with(
        "operation.duration",
        anything,
        tags: expected_tags
      )

      allow(mock_statsd).to receive(:increment)

      Vectra::Instrumentation.send(:notify_handlers, event)
    end

    it "includes provider in tags" do
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :custom_provider,
        index: "test",
        duration: 25.0,
        metadata: {}
      )

      expect(mock_statsd).to receive(:timing).with(
        anything,
        anything,
        tags: array_including("provider:custom_provider")
      )

      allow(mock_statsd).to receive(:increment)

      Vectra::Instrumentation.send(:notify_handlers, event)
    end
  end

  describe "integration with Vectra::Instrumentation" do
    before do
      allow(Datadog::Statsd).to receive(:new).and_return(mock_statsd)
      described_class.setup!
    end

    it "works with actual instrumentation flow" do
      expect(mock_statsd).to receive(:timing).at_least(:once)
      expect(mock_statsd).to receive(:increment).at_least(:once)

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
      expect(mock_statsd).to receive(:timing).at_least(:once)
      expect(mock_statsd).to receive(:increment).at_least(:twice)

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

  describe "without statsd initialized" do
    it "does not raise error when recording metrics" do
      described_class.instance_variable_set(:@statsd, nil)
      described_class.instance_variable_set(:@handlers, [])

      # Manually register handler without setup
      Vectra::Instrumentation.on_operation do |event|
        described_class.send(:record_metrics, event)
      end

      event = Vectra::Instrumentation::Event.new(
        operation: :test,
        provider: :test,
        index: "test",
        duration: 10.0,
        metadata: {}
      )

      expect do
        Vectra::Instrumentation.send(:notify_handlers, event)
      end.not_to raise_error
    end
  end
end
