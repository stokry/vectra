# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::Instrumentation do
  before do
    described_class.clear_handlers!
    Vectra.configuration.instrumentation = false
  end

  after do
    described_class.clear_handlers!
    Vectra.configuration.instrumentation = false
  end

  describe ".on_operation" do
    it "registers a handler" do
      handler_called = false
      described_class.on_operation { |_event| handler_called = true }

      Vectra.configuration.instrumentation = true
      described_class.instrument(operation: :test, provider: :pgvector, index: "test") { "result" }

      expect(handler_called).to be true
    end

    it "calls multiple handlers in order" do
      calls = []
      described_class.on_operation { |_event| calls << :first }
      described_class.on_operation { |_event| calls << :second }

      Vectra.configuration.instrumentation = true
      described_class.instrument(operation: :test, provider: :pgvector, index: "test") { "result" }

      expect(calls).to eq([:first, :second])
    end
  end

  describe ".instrument" do
    let(:events) { [] }

    before do
      described_class.on_operation { |event| events << event }
      Vectra.configuration.instrumentation = true
    end

    it "creates event with correct attributes" do
      described_class.instrument(
        operation: :upsert,
        provider: :pgvector,
        index: "documents",
        metadata: { vector_count: 10 }
      ) { "result" }

      event = events.first
      expect(event.operation).to eq(:upsert)
      expect(event.provider).to eq(:pgvector)
      expect(event.index).to eq("documents")
      expect(event.metadata[:vector_count]).to eq(10)
    end

    it "measures duration" do
      described_class.instrument(operation: :test, provider: :pgvector, index: "test") do
        sleep 0.1
      end

      event = events.first
      expect(event.duration).to be >= 100  # At least 100ms
      expect(event.duration).to be < 200   # Less than 200ms
    end

    it "captures errors" do
      expect do
        described_class.instrument(operation: :test, provider: :pgvector, index: "test") do
          raise StandardError, "Test error"
        end
      end.to raise_error(StandardError, "Test error")

      event = events.first
      expect(event.failure?).to be true
      expect(event.error).to be_a(StandardError)
      expect(event.error.message).to eq("Test error")
    end

    it "returns block result" do
      result = described_class.instrument(operation: :test, provider: :pgvector, index: "test") do
        "success"
      end

      expect(result).to eq("success")
    end

    context "when instrumentation is disabled" do
      before { Vectra.configuration.instrumentation = false }

      it "does not call handlers" do
        handler_called = false
        described_class.on_operation { |_event| handler_called = true }

        described_class.instrument(operation: :test, provider: :pgvector, index: "test") { "result" }

        expect(handler_called).to be false
      end

      it "still executes the block" do
        result = described_class.instrument(operation: :test, provider: :pgvector, index: "test") do
          "result"
        end

        expect(result).to eq("result")
      end
    end
  end

  describe Vectra::Instrumentation::Event do
    before do
      Vectra::Instrumentation.clear_handlers!
      Vectra.configuration.instrumentation = false
    end

    after do
      Vectra::Instrumentation.clear_handlers!
      Vectra.configuration.instrumentation = false
    end

    let(:event) do
      described_class.new(
        operation: :query,
        provider: :pgvector,
        index: "documents",
        duration: 123.45,
        metadata: { top_k: 10 },
        error: nil
      )
    end

    describe "#success?" do
      it "returns true when no error" do
        expect(event.success?).to be true
      end

      it "returns false when error present" do
        error_event = described_class.new(
          operation: :query,
          provider: :pgvector,
          index: "test",
          duration: 100,
          error: StandardError.new("error")
        )

        expect(error_event.success?).to be false
      end
    end

    describe "#failure?" do
      it "returns false when no error" do
        expect(event.failure?).to be false
      end

      it "returns true when error present" do
        error_event = described_class.new(
          operation: :query,
          provider: :pgvector,
          index: "test",
          duration: 100,
          error: StandardError.new("error")
        )

        expect(error_event.failure?).to be true
      end
    end
  end

  describe "error handling in handlers" do
    it "continues executing other handlers if one fails" do
      calls = []
      described_class.on_operation { |_event| raise "Handler error" }
      described_class.on_operation { |_event| calls << :second }

      Vectra.configuration.instrumentation = true

      expect do
        described_class.instrument(operation: :test, provider: :pgvector, index: "test") { "result" }
      end.not_to raise_error

      expect(calls).to eq([:second])
    end
  end
end
