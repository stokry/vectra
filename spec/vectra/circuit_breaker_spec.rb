# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::CircuitBreaker do
  let(:breaker) do
    described_class.new(
      name: "test",
      failure_threshold: 3,
      success_threshold: 2,
      recovery_timeout: 1
    )
  end

  describe "#initialize" do
    it "starts in closed state" do
      expect(breaker).to be_closed
      expect(breaker.failure_count).to eq(0)
    end

    it "sets configuration options" do
      stats = breaker.stats
      expect(stats[:failure_threshold]).to eq(3)
      expect(stats[:success_threshold]).to eq(2)
      expect(stats[:recovery_timeout]).to eq(1)
    end
  end

  describe "#call" do
    context "when circuit is closed" do
      it "executes the block" do
        result = breaker.call { "success" }
        expect(result).to eq("success")
      end

      it "tracks successful calls" do
        breaker.call { "ok" }
        expect(breaker.success_count).to eq(1)
      end

      it "opens circuit after failure threshold" do
        3.times do
          breaker.call { raise Vectra::ServerError, "fail" }
        rescue Vectra::ServerError
          # Expected
        end

        expect(breaker).to be_open
        expect(breaker.failure_count).to eq(3)
      end
    end

    context "when circuit is open" do
      before do
        breaker.trip!
      end

      it "raises OpenCircuitError without fallback" do
        expect { breaker.call { "test" } }
          .to raise_error(Vectra::CircuitBreaker::OpenCircuitError)
      end

      it "calls fallback when provided" do
        result = breaker.call(fallback: -> { "fallback" }) { "test" }
        expect(result).to eq("fallback")
      end

      it "includes circuit info in error" do
        breaker.call { "test" }
      rescue Vectra::CircuitBreaker::OpenCircuitError => e
        expect(e.circuit_name).to eq("test")
        expect(e.opened_at).not_to be_nil
      end
    end

    context "when circuit transitions to half-open" do
      before do
        breaker.trip!
        sleep(1.1) # Wait for recovery timeout
      end

      it "allows test request through" do
        result = breaker.call { "recovered" }
        expect(result).to eq("recovered")
        expect(breaker).to be_half_open
      end

      it "closes circuit after success threshold" do
        2.times { breaker.call { "ok" } }
        expect(breaker).to be_closed
      end

      it "reopens circuit on failure" do
        expect do
          breaker.call { raise Vectra::ServerError, "still broken" }
        end.to raise_error(Vectra::ServerError)

        expect(breaker).to be_open
      end
    end
  end

  describe "#reset!" do
    before do
      breaker.trip!
    end

    it "closes the circuit" do
      breaker.reset!
      expect(breaker).to be_closed
    end

    it "resets counters" do
      breaker.reset!
      expect(breaker.failure_count).to eq(0)
      expect(breaker.success_count).to eq(0)
    end
  end

  describe "#trip!" do
    it "opens the circuit" do
      breaker.trip!
      expect(breaker).to be_open
    end

    it "sets opened_at timestamp" do
      breaker.trip!
      expect(breaker.opened_at).not_to be_nil
    end
  end

  describe "#stats" do
    it "returns circuit statistics" do
      stats = breaker.stats
      expect(stats[:name]).to eq("test")
      expect(stats[:state]).to eq(:closed)
      expect(stats).to have_key(:failure_threshold)
      expect(stats).to have_key(:success_threshold)
    end
  end

  describe "monitored errors" do
    it "only opens on monitored errors" do
      # Non-monitored error should not increase failure count
      expect do
        breaker.call { raise ArgumentError, "not monitored" }
      end.to raise_error(ArgumentError)

      expect(breaker.failure_count).to eq(0)
    end

    it "opens on ServerError" do
      expect do
        breaker.call { raise Vectra::ServerError, "server down" }
      end.to raise_error(Vectra::ServerError)

      expect(breaker.failure_count).to eq(1)
    end

    it "opens on ConnectionError" do
      expect do
        breaker.call { raise Vectra::ConnectionError, "network issue" }
      end.to raise_error(Vectra::ConnectionError)

      expect(breaker.failure_count).to eq(1)
    end

    it "opens on TimeoutError" do
      expect do
        breaker.call { raise Vectra::TimeoutError, "timed out" }
      end.to raise_error(Vectra::TimeoutError)

      expect(breaker.failure_count).to eq(1)
    end
  end

  describe "thread safety" do
    it "handles concurrent calls safely" do
      threads = 10.times.map do
        Thread.new do
          5.times do
            breaker.call { sleep(0.01); "ok" }
          rescue Vectra::CircuitBreaker::OpenCircuitError
            # Expected when open
          end
        end
      end

      threads.each(&:join)
      # Should not raise any thread safety errors
    end
  end
end

RSpec.describe Vectra::CircuitBreakerRegistry do
  before do
    described_class.clear!
  end

  describe ".register" do
    it "creates a new circuit breaker" do
      breaker = described_class.register(:pinecone, failure_threshold: 5)
      expect(breaker).to be_a(Vectra::CircuitBreaker)
      expect(breaker.stats[:failure_threshold]).to eq(5)
    end
  end

  describe ".[]" do
    it "returns registered circuit" do
      described_class.register(:qdrant)
      expect(described_class[:qdrant]).to be_a(Vectra::CircuitBreaker)
    end

    it "returns nil for unregistered circuit" do
      expect(described_class[:unknown]).to be_nil
    end
  end

  describe ".all" do
    it "returns all registered circuits" do
      described_class.register(:a)
      described_class.register(:b)
      expect(described_class.all.keys).to contain_exactly(:a, :b)
    end
  end

  describe ".reset_all!" do
    it "resets all circuits" do
      described_class.register(:test)
      described_class[:test].trip!

      described_class.reset_all!
      expect(described_class[:test]).to be_closed
    end
  end

  describe ".stats" do
    it "returns stats for all circuits" do
      described_class.register(:x)
      described_class.register(:y)

      stats = described_class.stats
      expect(stats.keys).to contain_exactly(:x, :y)
      expect(stats[:x]).to have_key(:state)
    end
  end
end
