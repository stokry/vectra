# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::Pool do
  let(:mock_connection) { double("Connection", close: nil, status: 0) } # rubocop:disable RSpec/VerifiedDoubles -- generic connection mock
  let(:pool) { described_class.new(size: 3, timeout: 1) { mock_connection } }

  after do
    pool.shutdown
  end

  describe "#initialize" do
    it "sets size" do
      expect(pool.size).to eq(3)
    end

    it "sets timeout" do
      expect(pool.timeout).to eq(1)
    end

    it "raises without factory block" do
      expect { described_class.new(size: 3) }.to raise_error(ArgumentError)
    end
  end

  describe "#warmup" do
    it "pre-creates connections" do
      count = pool.warmup(2)
      expect(count).to eq(2)
      expect(pool.stats[:available]).to eq(2)
    end

    it "does not exceed pool size" do
      pool.warmup(5)
      expect(pool.stats[:available]).to be <= 3
    end

    it "defaults to pool size" do
      pool.warmup
      expect(pool.stats[:available]).to eq(3)
    end
  end

  describe "#with_connection" do
    it "yields a connection" do
      pool.with_connection do |conn|
        expect(conn).to eq(mock_connection)
      end
    end

    it "returns connection to pool after block" do
      pool.with_connection { |_c| :ok }
      expect(pool.stats[:checked_out]).to eq(0)
    end

    it "returns connection even on error" do
      expect do
        pool.with_connection { |_c| raise "test error" }
      end.to raise_error("test error")

      expect(pool.stats[:checked_out]).to eq(0)
    end
  end

  describe "#checkout and #checkin" do
    it "checks out a connection" do
      conn = pool.checkout
      expect(conn).to eq(mock_connection)
      expect(pool.stats[:checked_out]).to eq(1)
      pool.checkin(conn)
    end

    it "checks in a connection" do
      conn = pool.checkout
      pool.checkin(conn)
      expect(pool.stats[:checked_out]).to eq(0)
      expect(pool.stats[:available]).to eq(1)
    end

    it "raises TimeoutError when pool exhausted" do
      # Fill up the pool
      3.times { pool.checkout }

      expect { pool.checkout }.to raise_error(Vectra::Pool::TimeoutError)
    end
  end

  describe "#shutdown" do
    it "closes all connections" do
      pool.warmup(2)
      pool.shutdown

      expect(pool.stats[:shutdown]).to be true
      expect(pool.stats[:available]).to eq(0)
    end

    it "prevents further checkouts" do
      pool.shutdown

      expect { pool.checkout }.to raise_error(Vectra::Pool::PoolExhaustedError)
    end
  end

  describe "#stats" do
    it "returns pool statistics" do
      pool.warmup(2)
      pool.checkout

      stats = pool.stats
      expect(stats[:size]).to eq(3)
      expect(stats[:available]).to eq(1)
      expect(stats[:checked_out]).to eq(1)
    end
  end

  describe "#pool_healthy?" do
    it "returns true for active pool" do
      pool.warmup(1)
      expect(pool.pool_healthy?).to be true
    end

    it "returns false after shutdown" do
      pool.shutdown
      expect(pool.pool_healthy?).to be false
    end
  end

  describe "concurrent access" do
    it "handles multiple threads safely" do
      threads = 10.times.map do
        Thread.new do
          pool.with_connection { |_c| sleep(0.01) }
        end
      end

      threads.each(&:join)
      expect(pool.stats[:checked_out]).to eq(0)
    end
  end
end

RSpec.describe Vectra::PooledConnection do
  let(:test_class) do
    Class.new do
      include Vectra::PooledConnection

      attr_reader :config

      def initialize
        @config = Struct.new(:pool_size, :pool_timeout, :host).new(2, 1, "localhost")
      end

      def parse_connection_params
        { host: "localhost" }
      end
    end
  end

  let(:instance) { test_class.new }

  # NOTE: These tests require pg gem, skip if not available
  describe "#connection_pool", skip: "Requires pg gem" do
    it "creates a pool" do
      expect(instance.connection_pool).to be_a(Vectra::Pool)
    end
  end

  describe "#warmup_pool", skip: "Requires pg gem" do
    it "warms up the pool" do
      expect(instance.warmup_pool(1)).to be_positive
    end
  end

  describe "#pool_stats" do
    it "returns not_initialized when pool not created" do
      expect(instance.pool_stats).to eq({ status: "not_initialized" })
    end
  end
end
