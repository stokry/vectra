# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::Middleware::Retry do
  let(:middleware) { described_class.new(max_attempts: 3, backoff: :exponential) }
  let(:request) { Vectra::Middleware::Request.new(operation: :query, index: "test") }

  describe "#call" do
    it "succeeds on first attempt" do
      app = lambda do |_req|
        Vectra::Middleware::Response.new(result: { success: true })
      end

      response = middleware.call(request, app)
      expect(response.success?).to be true
      expect(response.metadata[:retry_count]).to eq(0)
    end

    it "retries on retryable error" do
      attempt_count = 0

      app = lambda do |_req|
        attempt_count += 1
        if attempt_count < 3
          Vectra::Middleware::Response.new(error: Vectra::RateLimitError.new("Rate limited", retry_after: 1))
        else
          Vectra::Middleware::Response.new(result: { success: true })
        end
      end

      response = middleware.call(request, app)
      expect(response.success?).to be true
      expect(response.metadata[:retry_count]).to eq(2)
    end

    it "gives up after max attempts" do
      app = lambda do |_req|
        Vectra::Middleware::Response.new(error: Vectra::ConnectionError.new("Connection failed"))
      end

      response = middleware.call(request, app)
      expect(response.failure?).to be true
      expect(response.metadata[:retry_count]).to eq(2)
    end

    it "does not retry on non-retryable errors" do
      attempt_count = 0

      app = lambda do |_req|
        attempt_count += 1
        Vectra::Middleware::Response.new(error: Vectra::ValidationError.new("Invalid input"))
      end

      response = middleware.call(request, app)
      expect(response.failure?).to be true
      expect(attempt_count).to eq(1)
    end
  end
end
