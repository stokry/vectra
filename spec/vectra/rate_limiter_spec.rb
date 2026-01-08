# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::RateLimiter do
  let(:limiter) { described_class.new(requests_per_second: 10, burst_size: 5) }

  describe "#initialize" do
    it "sets requests_per_second" do
      expect(limiter.requests_per_second).to eq(10)
    end

    it "sets burst_size" do
      expect(limiter.burst_size).to eq(5)
    end

    it "defaults burst_size to 2x RPS" do
      limiter = described_class.new(requests_per_second: 10)
      expect(limiter.burst_size).to eq(20)
    end

    it "starts with full token bucket" do
      expect(limiter.available_tokens).to eq(5)
    end
  end

  describe "#acquire" do
    it "executes block when tokens available" do
      result = limiter.acquire { "success" }
      expect(result).to eq("success")
    end

    it "consumes a token" do
      initial = limiter.available_tokens
      limiter.acquire { :ok }
      expect(limiter.available_tokens).to be < initial
    end

    it "raises when no tokens and wait is false" do
      # Exhaust tokens
      5.times { limiter.try_acquire }

      expect do
        limiter.acquire(wait: false) { :ok }
      end.to raise_error(Vectra::RateLimiter::RateLimitExceededError)
    end

    it "includes wait time in error" do
      5.times { limiter.try_acquire }

      begin
        limiter.acquire(wait: false) { :ok }
      rescue Vectra::RateLimiter::RateLimitExceededError => e
        expect(e.wait_time).to be > 0
      end
    end
  end

  describe "#try_acquire" do
    it "returns true when token available" do
      expect(limiter.try_acquire).to be true
    end

    it "returns false when no tokens" do
      5.times { limiter.try_acquire }
      expect(limiter.try_acquire).to be false
    end

    it "waits when wait is true" do
      5.times { limiter.try_acquire }

      # Should wait and eventually succeed
      result = limiter.try_acquire(wait: true, timeout: 1)
      expect(result).to be true
    end
  end

  describe "#available_tokens" do
    it "returns current token count" do
      expect(limiter.available_tokens).to eq(5)
    end

    it "decreases after acquire" do
      limiter.acquire { :ok }
      expect(limiter.available_tokens).to be < 5
    end

    it "refills over time" do
      5.times { limiter.try_acquire }
      expect(limiter.available_tokens).to eq(0)

      sleep(0.2) # Should refill ~2 tokens at 10/sec
      expect(limiter.available_tokens).to be > 0
    end
  end

  describe "#time_until_token" do
    it "returns 0 when tokens available" do
      expect(limiter.time_until_token).to eq(0)
    end

    it "returns wait time when no tokens" do
      5.times { limiter.try_acquire }
      expect(limiter.time_until_token).to be > 0
    end
  end

  describe "#stats" do
    it "returns rate limiter statistics" do
      stats = limiter.stats
      expect(stats[:requests_per_second]).to eq(10)
      expect(stats[:burst_size]).to eq(5)
      expect(stats).to have_key(:available_tokens)
      expect(stats).to have_key(:time_until_token)
    end
  end

  describe "#reset!" do
    it "restores full token capacity" do
      5.times { limiter.try_acquire }
      expect(limiter.available_tokens).to eq(0)

      limiter.reset!
      expect(limiter.available_tokens).to eq(5)
    end
  end

  describe "token refill" do
    it "respects burst_size cap" do
      sleep(1) # Should have plenty of time to refill
      expect(limiter.available_tokens).to be <= 5
    end
  end
end

RSpec.describe Vectra::RateLimitedClient do
  let(:mock_client) { instance_double(Vectra::Client) }
  let(:rate_limited) do
    described_class.new(mock_client, requests_per_second: 100, burst_size: 10)
  end

  before do
    allow(mock_client).to receive(:provider_name).and_return(:test)
  end

  describe "#query" do
    before do
      allow(mock_client).to receive(:query).and_return({ matches: [] })
    end

    it "rate limits queries" do
      result = rate_limited.query(index: "test", vector: [0.1], top_k: 10)
      expect(result).to eq({ matches: [] })
    end

    it "consumes rate limit tokens" do
      initial = rate_limited.limiter.available_tokens
      rate_limited.query(index: "test", vector: [0.1], top_k: 10)
      expect(rate_limited.limiter.available_tokens).to be < initial
    end
  end

  describe "#upsert" do
    before do
      allow(mock_client).to receive(:upsert).and_return({ upserted_count: 1 })
    end

    it "rate limits upserts" do
      result = rate_limited.upsert(index: "test", vectors: [])
      expect(result).to eq({ upserted_count: 1 })
    end
  end

  describe "method delegation" do
    it "passes through non-rate-limited methods" do
      allow(mock_client).to receive(:list_indexes).and_return([])
      expect(rate_limited.list_indexes).to eq([])
    end

    it "responds to client methods" do
      allow(mock_client).to receive(:respond_to?).with(:stats, anything).and_return(true)
      expect(rate_limited).to respond_to(:stats)
    end
  end

  describe "#rate_limit_stats" do
    it "returns limiter stats" do
      stats = rate_limited.rate_limit_stats
      expect(stats[:requests_per_second]).to eq(100)
    end
  end
end

RSpec.describe Vectra::RateLimiterRegistry do
  before { described_class.clear! }

  describe ".configure" do
    it "creates rate limiter for provider" do
      described_class.configure(:pinecone, requests_per_second: 100)
      expect(described_class[:pinecone]).to be_a(Vectra::RateLimiter)
    end
  end

  describe ".[]" do
    it "returns configured limiter" do
      described_class.configure(:qdrant, requests_per_second: 50)
      expect(described_class[:qdrant].requests_per_second).to eq(50)
    end

    it "returns nil for unconfigured provider" do
      expect(described_class[:unknown]).to be_nil
    end
  end

  describe ".stats" do
    it "returns stats for all limiters" do
      described_class.configure(:a, requests_per_second: 10)
      described_class.configure(:b, requests_per_second: 20)

      stats = described_class.stats
      expect(stats.keys).to contain_exactly(:a, :b)
    end
  end

  describe ".reset_all!" do
    it "resets all limiters" do
      described_class.configure(:test, requests_per_second: 10, burst_size: 2)
      2.times { described_class[:test].try_acquire }

      described_class.reset_all!
      expect(described_class[:test].available_tokens).to eq(2)
    end
  end
end
