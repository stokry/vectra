# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Vectra::JsonLogger do
  let(:output) { StringIO.new }
  let(:logger) { described_class.new(output, app: "test-app") }

  describe "#initialize" do
    it "accepts IO output" do
      expect(logger.output).to eq(output)
    end

    it "stores default metadata" do
      expect(logger.default_metadata).to eq({ app: "test-app" })
    end
  end

  describe "logging methods" do
    it "logs debug messages" do
      logger.debug("Debug message", key: "value")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["level"]).to eq("debug")
      expect(entry["message"]).to eq("Debug message")
      expect(entry["key"]).to eq("value")
    end

    it "logs info messages" do
      logger.info("Info message")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["level"]).to eq("info")
    end

    it "logs warn messages" do
      logger.warn("Warning")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["level"]).to eq("warn")
    end

    it "logs error messages" do
      logger.error("Error occurred", error: "TestError")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["level"]).to eq("error")
      expect(entry["error"]).to eq("TestError")
    end

    it "logs fatal messages" do
      logger.fatal("Fatal error")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["level"]).to eq("fatal")
    end
  end

  describe "JSON output format" do
    it "includes timestamp" do
      logger.info("Test")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["timestamp"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it "includes logger name" do
      logger.info("Test")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["logger"]).to eq("vectra")
    end

    it "includes default metadata" do
      logger.info("Test")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["app"]).to eq("test-app")
    end

    it "merges custom data" do
      logger.info("Test", custom: "data", number: 42)

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["custom"]).to eq("data")
      expect(entry["number"]).to eq(42)
    end
  end

  describe "#log_operation" do
    let(:event) do
      Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test-index",
        duration: 123.45,
        metadata: { result_count: 10 }
      )
    end

    it "logs operation event" do
      logger.log_operation(event)

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["message"]).to eq("vectra.query")
      expect(entry["provider"]).to eq("pinecone")
      expect(entry["operation"]).to eq("query")
      expect(entry["index"]).to eq("test-index")
      expect(entry["duration_ms"]).to eq(123.45)
      expect(entry["success"]).to be true
    end

    it "logs error events" do
      error_event = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :qdrant,
        index: "vectors",
        duration: 50.0,
        error: Vectra::ServerError.new("Connection failed")
      )

      logger.log_operation(error_event)

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["level"]).to eq("error")
      expect(entry["success"]).to be false
      expect(entry["error_class"]).to eq("Vectra::ServerError")
      expect(entry["error_message"]).to eq("Connection failed")
    end

    it "includes vector_count when present" do
      event_with_vectors = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :pgvector,
        index: "embeddings",
        duration: 200.0,
        metadata: { vector_count: 100 }
      )

      logger.log_operation(event_with_vectors)

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["vector_count"]).to eq(100)
    end
  end
end

RSpec.describe Vectra::Logging do
  let(:output) { StringIO.new }

  before do
    Vectra::Instrumentation.clear_handlers!
  end

  describe ".setup!" do
    it "creates JSON logger" do
      described_class.setup!(output: output, env: "test")
      expect(described_class.logger).to be_a(Vectra::JsonLogger)
    end

    it "registers instrumentation handler" do
      described_class.setup!(output: output)

      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      output.rewind
      expect(output.read).to include("vectra.query")
    end
  end

  describe ".log" do
    before { described_class.setup!(output: output) }

    it "logs custom messages" do
      described_class.log(:info, "Custom log", custom_key: "value")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["message"]).to eq("Custom log")
      expect(entry["custom_key"]).to eq("value")
    end
  end
end

RSpec.describe Vectra::JsonFormatter do
  let(:formatter) { described_class.new(service: "vectra-api") }

  describe "#call" do
    it "formats log entry as JSON" do
      output = formatter.call("INFO", Time.now, nil, "Test message")
      entry = JSON.parse(output)

      expect(entry["level"]).to eq("info")
      expect(entry["message"]).to eq("Test message")
      expect(entry["service"]).to eq("vectra-api")
    end

    it "handles exception messages" do
      error = StandardError.new("Something went wrong")
      output = formatter.call("ERROR", Time.now, nil, error)
      entry = JSON.parse(output)

      expect(entry["message"]).to include("StandardError")
      expect(entry["message"]).to include("Something went wrong")
    end

    it "handles hash messages" do
      output = formatter.call("INFO", Time.now, nil, { message: "Structured", key: "value" })
      entry = JSON.parse(output)

      expect(entry["message"]).to eq("Structured")
      expect(entry["key"]).to eq("value")
    end
  end
end
