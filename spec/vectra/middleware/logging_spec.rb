# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"

RSpec.describe Vectra::Middleware::Logging do
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }
  let(:middleware) { described_class.new(logger: logger) }
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
    it "logs before and after successful operation" do
      middleware.call(request, successful_app)

      logs = log_output.string
      expect(logs).to include("UPSERT")
      expect(logs).to include("index=test")
      expect(logs).to include("namespace=prod")
      expect(logs).to include("✅")
      expect(logs).to include("completed")
    end

    it "logs errors" do
      expect do
        middleware.call(request, failing_app)
      end.to raise_error(StandardError)

      logs = log_output.string
      expect(logs).to include("💥")
      expect(logs).to include("Test error")
    end

    it "adds duration metadata to response" do
      response = middleware.call(request, successful_app)
      expect(response.metadata[:duration_ms]).to be_a(Float)
      expect(response.metadata[:duration_ms]).to be > 0
    end
  end
end
