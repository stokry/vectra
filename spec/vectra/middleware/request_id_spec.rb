# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"

RSpec.describe Vectra::Middleware::RequestId do
  let(:middleware) { described_class.new }
  let(:request) { Vectra::Middleware::Request.new(operation: :upsert, index: "test", namespace: "prod") }
  let(:successful_app) do
    lambda do |_req|
      Vectra::Middleware::Response.new(result: { success: true })
    end
  end
  let(:failing_app) do
    lambda do |_req|
      raise StandardError, "Test error"
    end
  end

  describe "#call" do
    it "assigns a request ID to request metadata" do
      middleware.call(request, successful_app)

      expect(request.metadata[:request_id]).to be_a(String)
      expect(request.metadata[:request_id]).to start_with("vectra_")
    end

    it "propagates request ID to response metadata" do
      response = middleware.call(request, successful_app)

      expect(response.metadata[:request_id]).to eq(request.metadata[:request_id])
    end

    it "generates unique IDs for each request" do
      request2 = Vectra::Middleware::Request.new(operation: :query, index: "test")

      middleware.call(request, successful_app)
      middleware.call(request2, successful_app)

      expect(request.metadata[:request_id]).not_to eq(request2.metadata[:request_id])
    end

    it "preserves request ID on error" do
      expect do
        middleware.call(request, failing_app)
      end.to raise_error(StandardError)

      expect(request.metadata[:request_id]).to be_a(String)
      expect(request.metadata[:request_id]).to start_with("vectra_")
    end
  end

  describe "custom prefix" do
    let(:middleware) { described_class.new(prefix: "myapp") }

    it "uses the custom prefix" do
      middleware.call(request, successful_app)

      expect(request.metadata[:request_id]).to start_with("myapp_")
    end
  end

  describe "custom generator" do
    let(:counter) { [0] }
    let(:middleware) do
      c = counter
      described_class.new(generator: ->(prefix) { "#{prefix}-#{c[0] += 1}" })
    end

    it "uses the custom generator" do
      middleware.call(request, successful_app)

      expect(request.metadata[:request_id]).to eq("vectra-1")
    end

    it "calls generator for each request" do
      request2 = Vectra::Middleware::Request.new(operation: :query, index: "test")

      middleware.call(request, successful_app)
      middleware.call(request2, successful_app)

      expect(request.metadata[:request_id]).to eq("vectra-1")
      expect(request2.metadata[:request_id]).to eq("vectra-2")
    end
  end

  describe "on_assign callback" do
    it "invokes the callback with the generated request ID" do
      captured_ids = []
      middleware = described_class.new(on_assign: ->(id) { captured_ids << id })

      middleware.call(request, successful_app)

      expect(captured_ids.size).to eq(1)
      expect(captured_ids.first).to eq(request.metadata[:request_id])
    end
  end

  describe "logging" do
    let(:log_output) { StringIO.new }
    let(:logger) { Logger.new(log_output) }
    let(:middleware) { described_class.new(logger: logger) }

    it "logs request ID on before hook" do
      middleware.call(request, successful_app)

      logs = log_output.string
      expect(logs).to include("request_id=")
      expect(logs).to include("operation=upsert")
      expect(logs).to include("index=test")
    end

    it "logs request ID with status on after hook" do
      middleware.call(request, successful_app)

      logs = log_output.string
      expect(logs).to include("status=success")
    end

    it "logs request ID on error" do
      expect do
        middleware.call(request, failing_app)
      end.to raise_error(StandardError)

      logs = log_output.string
      expect(logs).to include("request_id=")
      expect(logs).to include("error=StandardError")
      expect(logs).to include("message=Test error")
    end
  end

  describe "middleware chain integration" do
    let(:config) do
      Vectra::Configuration.new.tap do |c|
        c.provider = :memory
      end
    end
    let(:provider) { Vectra::Providers::Memory.new(config) }

    it "works within a middleware stack" do
      stack = Vectra::Middleware::Stack.new(provider, [described_class.new])

      result = stack.call(:upsert, index: "test", vectors: [{ id: "1", values: [0.1, 0.2, 0.3] }])

      expect(result).to have_key(:upserted_count)
      expect(result[:upserted_count]).to eq(1)
    end
  end
end
