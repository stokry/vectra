# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::Streaming do
  let(:client) { instance_double(Vectra::Client) }
  let(:streaming) { described_class.new(client, page_size: 10) }

  let(:mock_match) do
    instance_double(Vectra::Match, id: "match_1", score: 0.9, values: [0.1], metadata: {})
  end

  let(:mock_result) do
    result = instance_double(Vectra::QueryResult)
    allow(result).to receive(:each).and_yield(mock_match)
    allow(result).to receive(:empty?).and_return(false)
    allow(result).to receive(:size).and_return(1)
    result
  end

  describe "#initialize" do
    it "sets page_size" do
      expect(streaming.page_size).to eq(10)
    end

    it "defaults to minimum of 1 page_size" do
      stream = described_class.new(client, page_size: 0)
      expect(stream.page_size).to eq(1)
    end
  end

  describe "#query_stream" do
    before do
      allow(client).to receive(:query).and_return(mock_result)
    end

    it "returns a lazy enumerator" do
      result = streaming.query_stream(
        index: "test",
        vector: [0.1, 0.2, 0.3],
        total: 5
      )

      expect(result).to be_a(Enumerator::Lazy)
    end

    it "fetches results lazily" do
      result = streaming.query_stream(
        index: "test",
        vector: [0.1, 0.2, 0.3],
        total: 5
      )

      # Only fetch first result
      first = result.first
      expect(first).to eq(mock_match)
    end
  end

  describe "#query_each" do
    before do
      allow(client).to receive(:query).and_return(mock_result)
    end

    it "yields each match to the block" do
      matches = []
      streaming.query_each(
        index: "test",
        vector: [0.1, 0.2, 0.3],
        total: 5
      ) { |m| matches << m }

      expect(matches).not_to be_empty
    end

    it "returns count of yielded matches" do
      count = streaming.query_each(
        index: "test",
        vector: [0.1, 0.2, 0.3],
        total: 5
      ) { |_m| }

      expect(count).to be_positive
    end

    it "returns 0 when no block given" do
      count = streaming.query_each(
        index: "test",
        vector: [0.1, 0.2, 0.3],
        total: 5
      )

      expect(count).to eq(0)
    end
  end

  describe "#scan_all" do
    let(:stats) { { total_vector_count: 100 } }

    before do
      allow(client).to receive(:stats).and_return(stats)
    end

    it "returns 0 when no block given" do
      count = streaming.scan_all(index: "test")
      expect(count).to eq(0)
    end

    it "returns total count when block given" do
      count = streaming.scan_all(index: "test") { |_v| }
      expect(count).to eq(100)
    end
  end
end

RSpec.describe Vectra::StreamingResult do
  let(:enumerator) { [1, 2, 3].lazy }
  let(:result) { described_class.new(enumerator, { total: 3 }) }

  describe "#each" do
    it "iterates over the enumerator" do
      items = []
      result.each { |i| items << i }
      expect(items).to eq([1, 2, 3])
    end
  end

  describe "#take" do
    it "takes n items" do
      expect(result.take(2).to_a).to eq([1, 2])
    end
  end

  describe "#to_a" do
    it "converts to array" do
      expect(result.to_a).to eq([1, 2, 3])
    end
  end

  describe "#metadata" do
    it "returns metadata" do
      expect(result.metadata).to eq({ total: 3 })
    end
  end
end
