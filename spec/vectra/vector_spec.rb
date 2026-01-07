# frozen_string_literal: true

RSpec.describe Vectra::Vector do
  subject(:vector) do
    described_class.new(
      id: "vec1",
      values: [0.1, 0.2, 0.3],
      metadata: { text: "Hello world", category: "greeting" }
    )
  end

  describe "#initialize" do
    it "creates a vector with required attributes" do
      expect(vector.id).to eq("vec1")
      expect(vector.values).to eq([0.1, 0.2, 0.3])
      expect(vector.metadata).to eq("text" => "Hello world", "category" => "greeting")
    end

    it "accepts symbol as id" do
      vec = described_class.new(id: :vec1, values: [0.1])
      expect(vec.id).to eq("vec1")
    end

    it "converts integer values to float" do
      vec = described_class.new(id: "vec1", values: [1, 2, 3])
      expect(vec.values).to eq([1.0, 2.0, 3.0])
    end

    it "converts metadata keys to strings" do
      vec = described_class.new(id: "vec1", values: [0.1], metadata: { key: "value" })
      expect(vec.metadata).to eq("key" => "value")
    end

    it "sets empty metadata when not provided" do
      vec = described_class.new(id: "vec1", values: [0.1])
      expect(vec.metadata).to eq({})
    end

    context "with validation errors" do
      it "raises error for nil id" do
        expect { described_class.new(id: nil, values: [0.1]) }
          .to raise_error(Vectra::ValidationError, /ID cannot be nil/)
      end

      it "raises error for nil values" do
        expect { described_class.new(id: "vec1", values: nil) }
          .to raise_error(Vectra::ValidationError, /values cannot be nil/)
      end

      it "raises error for empty values" do
        expect { described_class.new(id: "vec1", values: []) }
          .to raise_error(Vectra::ValidationError, /values cannot be empty/)
      end

      it "raises error for non-numeric values" do
        expect { described_class.new(id: "vec1", values: [0.1, "invalid", 0.3]) }
          .to raise_error(Vectra::ValidationError, /must be numeric/)
      end
    end
  end

  describe "#dimension" do
    it "returns the number of values" do
      expect(vector.dimension).to eq(3)
    end
  end

  describe "#metadata?" do
    it "returns true when metadata exists" do
      expect(vector.metadata?).to be true
    end

    it "returns false when metadata is empty" do
      vec = described_class.new(id: "vec1", values: [0.1])
      expect(vec.metadata?).to be false
    end
  end

  describe "#sparse?" do
    it "returns false when no sparse values" do
      expect(vector.sparse?).to be false
    end

    it "returns true when sparse values exist" do
      vec = described_class.new(
        id: "vec1",
        values: [0.1],
        sparse_values: { indices: [0], values: [0.5] }
      )
      expect(vec.sparse?).to be true
    end
  end

  describe "#to_h" do
    it "converts vector to hash" do
      hash = vector.to_h

      expect(hash).to eq(
        id: "vec1",
        values: [0.1, 0.2, 0.3],
        metadata: { "text" => "Hello world", "category" => "greeting" }
      )
    end

    it "excludes empty metadata" do
      vec = described_class.new(id: "vec1", values: [0.1])
      expect(vec.to_h).not_to have_key(:metadata)
    end

    it "includes sparse values when present" do
      vec = described_class.new(
        id: "vec1",
        values: [0.1],
        sparse_values: { indices: [0], values: [0.5] }
      )

      hash = vec.to_h
      expect(hash[:sparse_values]).to eq(indices: [0], values: [0.5])
    end
  end

  describe ".from_hash" do
    it "creates vector from hash with string keys" do
      hash = { "id" => "vec1", "values" => [0.1, 0.2], "metadata" => { "key" => "value" } }
      vec = described_class.from_hash(hash)

      expect(vec.id).to eq("vec1")
      expect(vec.values).to eq([0.1, 0.2])
      expect(vec.metadata).to eq("key" => "value")
    end

    it "creates vector from hash with symbol keys" do
      hash = { id: "vec1", values: [0.1, 0.2], metadata: { key: "value" } }
      vec = described_class.from_hash(hash)

      expect(vec.id).to eq("vec1")
      expect(vec.values).to eq([0.1, 0.2])
    end
  end

  describe "#cosine_similarity" do
    let(:other_vector) { described_class.new(id: "vec2", values: [0.1, 0.2, 0.3]) }

    it "calculates similarity with another Vector" do
      similarity = vector.cosine_similarity(other_vector)
      expect(similarity).to be_within(0.0001).of(1.0)
    end

    it "calculates similarity with array of values" do
      similarity = vector.cosine_similarity([0.1, 0.2, 0.3])
      expect(similarity).to be_within(0.0001).of(1.0)
    end

    it "returns 0 for orthogonal vectors" do
      orthogonal = described_class.new(id: "vec2", values: [0.0, 0.0, 1.0])
      vec = described_class.new(id: "vec1", values: [1.0, 0.0, 0.0])

      similarity = vec.cosine_similarity(orthogonal)
      expect(similarity).to be_within(0.0001).of(0.0)
    end

    it "returns 0 for zero vectors" do
      zero_vec = described_class.new(id: "vec2", values: [0.0, 0.0, 0.0])
      similarity = vector.cosine_similarity(zero_vec)
      expect(similarity).to eq(0.0)
    end

    it "raises error for different dimensions" do
      different = described_class.new(id: "vec2", values: [0.1, 0.2])
      expect { vector.cosine_similarity(different) }
        .to raise_error(ArgumentError, /same dimension/)
    end
  end

  describe "#euclidean_distance" do
    let(:other_vector) { described_class.new(id: "vec2", values: [0.1, 0.2, 0.3]) }

    it "calculates distance to another Vector" do
      distance = vector.euclidean_distance(other_vector)
      expect(distance).to be_within(0.0001).of(0.0)
    end

    it "calculates distance to array of values" do
      distance = vector.euclidean_distance([0.1, 0.2, 0.3])
      expect(distance).to be_within(0.0001).of(0.0)
    end

    it "returns correct distance for different vectors" do
      different = described_class.new(id: "vec2", values: [0.2, 0.4, 0.6])
      distance = vector.euclidean_distance(different)
      expected = Math.sqrt((0.1**2) + (0.2**2) + (0.3**2))
      expect(distance).to be_within(0.0001).of(expected)
    end

    it "raises error for different dimensions" do
      different = described_class.new(id: "vec2", values: [0.1, 0.2])
      expect { vector.euclidean_distance(different) }
        .to raise_error(ArgumentError, /same dimension/)
    end
  end

  describe "#==" do
    it "returns true for equal vectors" do
      other = described_class.new(
        id: "vec1",
        values: [0.1, 0.2, 0.3],
        metadata: { text: "Hello world", category: "greeting" }
      )
      expect(vector == other).to be true
    end

    it "returns false for different ids" do
      other = described_class.new(id: "vec2", values: [0.1, 0.2, 0.3])
      expect(vector == other).to be false
    end

    it "returns false for different values" do
      other = described_class.new(id: "vec1", values: [0.2, 0.3, 0.4])
      expect(vector == other).to be false
    end

    it "returns false for different metadata" do
      other = described_class.new(id: "vec1", values: [0.1, 0.2, 0.3], metadata: { different: "data" })
      expect(vector == other).to be false
    end

    it "returns false for non-Vector objects" do
      expect(vector == "not a vector").to be false
    end
  end

  describe "#to_s" do
    it "returns a string representation" do
      str = vector.to_s
      expect(str).to include("Vectra::Vector")
      expect(str).to include("vec1")
      expect(str).to include("dimension=3")
    end
  end

  describe "#hash" do
    it "returns consistent hash value" do
      expect(vector.hash).to eq(vector.hash)
    end

    it "returns same hash for equal vectors" do
      other = described_class.new(
        id: "vec1",
        values: [0.1, 0.2, 0.3],
        metadata: { text: "Hello world", category: "greeting" }
      )
      expect(vector.hash).to eq(other.hash)
    end
  end
end
