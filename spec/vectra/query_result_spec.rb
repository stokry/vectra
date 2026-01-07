# frozen_string_literal: true

RSpec.describe Vectra::QueryResult do
  let(:matches) do
    [
      { id: "vec1", score: 0.95, metadata: { text: "First" } },
      { id: "vec2", score: 0.85, metadata: { text: "Second" } },
      { id: "vec3", score: 0.75, metadata: { text: "Third" } }
    ]
  end

  subject(:result) { described_class.new(matches: matches, namespace: "test") }

  describe "#initialize" do
    it "creates result with matches" do
      expect(result.matches).to have(3).items
      expect(result.namespace).to eq("test")
    end

    it "converts hash matches to Match objects" do
      expect(result.matches.first).to be_a(Vectra::Match)
    end

    it "accepts Match objects directly" do
      match_objects = matches.map { |m| Vectra::Match.new(**m) }
      result = described_class.new(matches: match_objects)

      expect(result.matches).to all(be_a(Vectra::Match))
    end
  end

  describe "#each" do
    it "iterates over matches" do
      ids = []
      result.each { |match| ids << match.id }

      expect(ids).to eq(["vec1", "vec2", "vec3"])
    end

    it "is enumerable" do
      expect(result.map(&:id)).to eq(["vec1", "vec2", "vec3"])
    end
  end

  describe "#size" do
    it "returns number of matches" do
      expect(result.size).to eq(3)
    end
  end

  describe "#empty?" do
    it "returns false when matches exist" do
      expect(result.empty?).to be false
    end

    it "returns true when no matches" do
      empty_result = described_class.new(matches: [])
      expect(empty_result.empty?).to be true
    end
  end

  describe "#first" do
    it "returns first match" do
      expect(result.first.id).to eq("vec1")
    end
  end

  describe "#last" do
    it "returns last match" do
      expect(result.last.id).to eq("vec3")
    end
  end

  describe "#[]" do
    it "returns match by index" do
      expect(result[1].id).to eq("vec2")
    end
  end

  describe "#ids" do
    it "returns all vector IDs" do
      expect(result.ids).to eq(["vec1", "vec2", "vec3"])
    end
  end

  describe "#scores" do
    it "returns all scores" do
      expect(result.scores).to eq([0.95, 0.85, 0.75])
    end
  end

  describe "#max_score" do
    it "returns highest score" do
      expect(result.max_score).to eq(0.95)
    end

    it "returns nil for empty results" do
      empty_result = described_class.new(matches: [])
      expect(empty_result.max_score).to be_nil
    end
  end

  describe "#min_score" do
    it "returns lowest score" do
      expect(result.min_score).to eq(0.75)
    end
  end

  describe "#above_score" do
    it "filters matches by minimum score" do
      filtered = result.above_score(0.8)

      expect(filtered.size).to eq(2)
      expect(filtered.ids).to eq(["vec1", "vec2"])
    end

    it "returns new QueryResult instance" do
      filtered = result.above_score(0.8)

      expect(filtered).to be_a(described_class)
      expect(filtered).not_to equal(result)
    end

    it "preserves namespace and usage" do
      result = described_class.new(
        matches: matches,
        namespace: "test",
        usage: { read_units: 5 }
      )

      filtered = result.above_score(0.8)

      expect(filtered.namespace).to eq("test")
      expect(filtered.usage).to eq(read_units: 5)
    end
  end

  describe "#to_a" do
    it "converts to array of hashes" do
      array = result.to_a

      expect(array).to be_an(Array)
      expect(array.first).to be_a(Hash)
      expect(array.first[:id]).to eq("vec1")
    end
  end

  describe "#to_h" do
    it "converts to hash" do
      hash = result.to_h

      expect(hash[:matches]).to be_an(Array)
      expect(hash[:namespace]).to eq("test")
    end

    it "omits nil values" do
      result = described_class.new(matches: matches)
      hash = result.to_h

      expect(hash).not_to have_key(:namespace)
      expect(hash).not_to have_key(:usage)
    end
  end

  describe ".from_response" do
    it "creates QueryResult from API response" do
      response = {
        matches: [
          { id: "vec1", score: 0.9, metadata: { text: "Test" } }
        ],
        namespace: "production",
        usage: { read_units: 1 }
      }

      result = described_class.from_response(response)

      expect(result).to be_a(described_class)
      expect(result.size).to eq(1)
      expect(result.namespace).to eq("production")
      expect(result.usage).to eq(read_units: 1)
    end

    it "handles response with string keys" do
      response = {
        "matches" => [{ "id" => "vec1", "score" => 0.9 }],
        "namespace" => "test"
      }

      result = described_class.from_response(response)

      expect(result.size).to eq(1)
      expect(result.namespace).to eq("test")
    end
  end

  describe "#to_s" do
    it "returns string representation" do
      str = result.to_s

      expect(str).to include("QueryResult")
      expect(str).to include("matches=3")
      expect(str).to include("test")
    end
  end
end

RSpec.describe Vectra::Match do
  subject(:match) do
    described_class.new(
      id: "vec1",
      score: 0.95,
      values: [0.1, 0.2, 0.3],
      metadata: { text: "Hello", category: "greeting" }
    )
  end

  describe "#initialize" do
    it "creates match with required attributes" do
      expect(match.id).to eq("vec1")
      expect(match.score).to eq(0.95)
      expect(match.values).to eq([0.1, 0.2, 0.3])
      expect(match.metadata).to eq("text" => "Hello", "category" => "greeting")
    end

    it "converts id to string" do
      m = described_class.new(id: 123, score: 0.9)
      expect(m.id).to eq("123")
    end

    it "converts score to float" do
      m = described_class.new(id: "vec1", score: 1)
      expect(m.score).to eq(1.0)
    end

    it "sets empty metadata when not provided" do
      m = described_class.new(id: "vec1", score: 0.9)
      expect(m.metadata).to eq({})
    end
  end

  describe "#values?" do
    it "returns true when values are present" do
      expect(match.values?).to be true
    end

    it "returns false when values are nil" do
      m = described_class.new(id: "vec1", score: 0.9)
      expect(m.values?).to be false
    end
  end

  describe "#metadata?" do
    it "returns true when metadata exists" do
      expect(match.metadata?).to be true
    end

    it "returns false when metadata is empty" do
      m = described_class.new(id: "vec1", score: 0.9)
      expect(m.metadata?).to be false
    end
  end

  describe "#[]" do
    it "accesses metadata by string key" do
      expect(match["text"]).to eq("Hello")
    end

    it "accesses metadata by symbol key" do
      expect(match[:text]).to eq("Hello")
    end
  end

  describe "#to_vector" do
    it "converts to Vector object" do
      vector = match.to_vector

      expect(vector).to be_a(Vectra::Vector)
      expect(vector.id).to eq("vec1")
      expect(vector.values).to eq([0.1, 0.2, 0.3])
      expect(vector.metadata).to eq("text" => "Hello", "category" => "greeting")
    end

    it "raises error when values are not included" do
      m = described_class.new(id: "vec1", score: 0.9)

      expect { m.to_vector }
        .to raise_error(Vectra::Error, /values not included/)
    end
  end

  describe "#to_h" do
    it "converts to hash" do
      hash = match.to_h

      expect(hash).to eq(
        id: "vec1",
        score: 0.95,
        values: [0.1, 0.2, 0.3],
        metadata: { "text" => "Hello", "category" => "greeting" }
      )
    end

    it "excludes nil values" do
      m = described_class.new(id: "vec1", score: 0.9)
      hash = m.to_h

      expect(hash).not_to have_key(:values)
      expect(hash).not_to have_key(:metadata)
    end
  end

  describe ".from_hash" do
    it "creates Match from hash" do
      hash = {
        id: "vec1",
        score: 0.9,
        values: [0.1],
        metadata: { key: "value" }
      }

      m = described_class.from_hash(hash)

      expect(m.id).to eq("vec1")
      expect(m.score).to eq(0.9)
      expect(m.values).to eq([0.1])
    end
  end

  describe "#==" do
    it "returns true for equal matches" do
      other = described_class.new(id: "vec1", score: 0.95)
      expect(match == other).to be true
    end

    it "returns false for different ids" do
      other = described_class.new(id: "vec2", score: 0.95)
      expect(match == other).to be false
    end

    it "returns false for different scores" do
      other = described_class.new(id: "vec1", score: 0.85)
      expect(match == other).to be false
    end
  end

  describe "#to_s" do
    it "returns string representation" do
      str = match.to_s

      expect(str).to include("Match")
      expect(str).to include("vec1")
      expect(str).to include("0.95")
    end
  end
end
