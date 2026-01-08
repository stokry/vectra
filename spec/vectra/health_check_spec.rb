# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::HealthCheck do
  let(:config) do
    cfg = Vectra::Configuration.new
    cfg.instance_variable_set(:@provider, :pinecone)
    cfg.api_key = "test-key"
    cfg.host = "https://test.pinecone.io"
    cfg
  end

  let(:mock_provider) { instance_double(Vectra::Providers::Pinecone) }

  let(:client) do
    client = Vectra::Client.allocate
    client.instance_variable_set(:@config, config)
    client.instance_variable_set(:@provider, mock_provider)
    client
  end

  before do
    allow(mock_provider).to receive(:provider_name).and_return(:pinecone)
  end

  describe "#health_check" do
    context "when provider is healthy" do
      before do
        allow(mock_provider).to receive_messages(
          list_indexes: [
            { name: "index-1" },
            { name: "index-2" }
          ]
        )
      end

      it "returns healthy result" do
        result = client.health_check

        expect(result).to be_healthy
        expect(result.provider).to eq(:pinecone)
        expect(result.indexes_available).to eq(2)
      end

      it "includes latency" do
        result = client.health_check

        expect(result.latency_ms).to be > 0
      end

      it "includes checked_at timestamp" do
        result = client.health_check

        expect(result.checked_at).to match(/\d{4}-\d{2}-\d{2}/)
      end
    end

    context "when provider is unhealthy" do
      before do
        allow(mock_provider).to receive(:list_indexes)
          .and_raise(Vectra::ConnectionError, "Connection refused")
      end

      it "returns unhealthy result" do
        result = client.health_check

        expect(result).to be_unhealthy
        expect(result.error).to eq("Vectra::ConnectionError")
        expect(result.error_message).to eq("Connection refused")
      end
    end

    context "with include_stats" do
      before do
        allow(mock_provider).to receive_messages(
          list_indexes: [{ name: "my-index" }],
          stats: {
            total_vector_count: 1000,
            dimension: 384
          }
        )
      end

      it "includes index stats" do
        result = client.health_check(include_stats: true)

        expect(result.stats[:vector_count]).to eq(1000)
        expect(result.stats[:dimension]).to eq(384)
      end
    end

    context "with pool stats" do
      let(:pgvector_provider) { double("PgvectorProvider") }

      let(:pgvector_client) do
        client = Vectra::Client.allocate
        client.instance_variable_set(:@config, config)
        client.instance_variable_set(:@provider, pgvector_provider)
        client
      end

      before do
        allow(pgvector_provider).to receive(:respond_to?).with(:pool_stats).and_return(true)
        allow(pgvector_provider).to receive_messages(
          provider_name: :pgvector,
          list_indexes: [],
          pool_stats: {
            available: 5,
            checked_out: 2,
            size: 10
          }
        )
      end

      it "includes pool stats" do
        result = pgvector_client.health_check

        expect(result.pool[:available]).to eq(5)
        expect(result.pool[:checked_out]).to eq(2)
      end
    end
  end

  describe "#healthy?" do
    it "returns true when healthy" do
      allow(mock_provider).to receive(:list_indexes).and_return([])

      expect(client.healthy?).to be true
    end

    it "returns false when unhealthy" do
      allow(mock_provider).to receive(:list_indexes)
        .and_raise(Vectra::ServerError, "Error")

      expect(client.healthy?).to be false
    end
  end
end

RSpec.describe Vectra::HealthCheckResult do
  describe "#healthy?" do
    it "returns true for healthy result" do
      result = described_class.new(
        healthy: true,
        provider: :pinecone,
        latency_ms: 50,
        checked_at: Time.now.iso8601
      )

      expect(result).to be_healthy
    end

    it "returns false for unhealthy result" do
      result = described_class.new(
        healthy: false,
        provider: :pinecone,
        latency_ms: 100,
        checked_at: Time.now.iso8601,
        error: "TimeoutError"
      )

      expect(result).not_to be_healthy
      expect(result).to be_unhealthy
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      result = described_class.new(
        healthy: true,
        provider: :qdrant,
        latency_ms: 25.5,
        checked_at: "2025-01-08T12:00:00Z",
        indexes_available: 3
      )

      hash = result.to_h

      expect(hash[:healthy]).to be true
      expect(hash[:provider]).to eq(:qdrant)
      expect(hash[:latency_ms]).to eq(25.5)
      expect(hash[:indexes_available]).to eq(3)
    end

    it "excludes nil values" do
      result = described_class.new(
        healthy: true,
        provider: :pgvector,
        latency_ms: 10,
        checked_at: Time.now.iso8601
      )

      hash = result.to_h

      expect(hash).not_to have_key(:error)
      expect(hash).not_to have_key(:error_message)
    end
  end

  describe "#to_json" do
    it "returns JSON string" do
      result = described_class.new(
        healthy: true,
        provider: :pinecone,
        latency_ms: 50,
        checked_at: "2025-01-08T12:00:00Z"
      )

      json = result.to_json
      parsed = JSON.parse(json)

      expect(parsed["healthy"]).to be true
      expect(parsed["provider"]).to eq("pinecone")
    end
  end
end

RSpec.describe Vectra::AggregateHealthCheck do
  let(:healthy_client) do
    client = instance_double(Vectra::Client)
    allow(client).to receive(:health_check).and_return(
      Vectra::HealthCheckResult.new(
        healthy: true,
        provider: :pinecone,
        latency_ms: 50,
        checked_at: Time.now.iso8601
      )
    )
    client
  end

  let(:unhealthy_client) do
    client = instance_double(Vectra::Client)
    allow(client).to receive(:health_check).and_return(
      Vectra::HealthCheckResult.new(
        healthy: false,
        provider: :qdrant,
        latency_ms: 100,
        checked_at: Time.now.iso8601,
        error: "ConnectionError"
      )
    )
    client
  end

  describe "#check_all" do
    it "returns aggregate results" do
      checker = described_class.new(
        primary: healthy_client,
        backup: healthy_client
      )

      result = checker.check_all

      expect(result[:overall_healthy]).to be true
      expect(result[:healthy_count]).to eq(2)
      expect(result[:total_count]).to eq(2)
    end

    it "reports partial failures" do
      checker = described_class.new(
        primary: healthy_client,
        backup: unhealthy_client
      )

      result = checker.check_all

      expect(result[:overall_healthy]).to be false
      expect(result[:healthy_count]).to eq(1)
      expect(result[:total_count]).to eq(2)
    end

    it "includes per-client results" do
      checker = described_class.new(
        pinecone: healthy_client
      )

      result = checker.check_all

      expect(result[:results]).to have_key(:pinecone)
      expect(result[:results][:pinecone][:healthy]).to be true
    end
  end

  describe "#all_healthy?" do
    it "returns true when all clients healthy" do
      checker = described_class.new(a: healthy_client, b: healthy_client)
      expect(checker.all_healthy?).to be true
    end

    it "returns false when any client unhealthy" do
      checker = described_class.new(a: healthy_client, b: unhealthy_client)
      expect(checker.all_healthy?).to be false
    end
  end

  describe "#any_healthy?" do
    it "returns true when any client healthy" do
      checker = described_class.new(a: healthy_client, b: unhealthy_client)
      expect(checker.any_healthy?).to be true
    end

    it "returns false when all clients unhealthy" do
      checker = described_class.new(a: unhealthy_client, b: unhealthy_client)
      expect(checker.any_healthy?).to be false
    end
  end
end
