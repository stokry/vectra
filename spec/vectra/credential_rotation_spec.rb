# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::CredentialRotator do
  let(:primary_key) { "primary-key-123" }
  let(:secondary_key) { "secondary-key-456" }
  let(:rotator) { described_class.new(primary_key: primary_key, secondary_key: secondary_key) }

  describe "#initialize" do
    it "sets primary and secondary keys" do
      expect(rotator.primary_key).to eq(primary_key)
      expect(rotator.secondary_key).to eq(secondary_key)
      expect(rotator.current_key).to eq(primary_key)
    end
  end

  describe "#test_secondary" do
    let(:mock_client) { instance_double(Vectra::Client) }

    before do
      allow(mock_client).to receive(:healthy?).and_return(true)
    end

    it "returns true when secondary key is valid" do
      rotator = described_class.new(
        primary_key: primary_key,
        secondary_key: secondary_key,
        test_client: mock_client
      )

      expect(rotator.test_secondary).to be true
    end

    it "returns false when secondary key is invalid" do
      allow(mock_client).to receive(:healthy?).and_raise(Vectra::AuthenticationError, "Invalid key")

      rotator = described_class.new(
        primary_key: primary_key,
        secondary_key: secondary_key,
        test_client: mock_client
      )

      expect(rotator.test_secondary).to be false
    end

    it "returns false when no secondary key" do
      rotator = described_class.new(primary_key: primary_key, secondary_key: nil)
      expect(rotator.test_secondary).to be false
    end
  end

  describe "#switch_to_secondary" do
    let(:mock_client) { instance_double(Vectra::Client) }

    before do
      allow(mock_client).to receive(:healthy?).and_return(true)
    end

    it "switches to secondary key" do
      rotator = described_class.new(
        primary_key: primary_key,
        secondary_key: secondary_key,
        test_client: mock_client
      )

      rotator.switch_to_secondary
      expect(rotator.current_key).to eq(secondary_key)
      expect(rotator).to be_rotation_complete
    end

    it "validates before switching by default" do
      allow(mock_client).to receive(:healthy?).and_raise(Vectra::AuthenticationError, "Invalid")

      rotator = described_class.new(
        primary_key: primary_key,
        secondary_key: secondary_key,
        test_client: mock_client
      )

      expect do
        rotator.switch_to_secondary
      end.to raise_error(Vectra::CredentialRotationError)
    end

    it "skips validation when validate is false" do
      rotator.switch_to_secondary(validate: false)
      expect(rotator.current_key).to eq(secondary_key)
    end
  end

  describe "#rollback" do
    it "reverts to primary key" do
      rotator.switch_to_secondary(validate: false)
      rotator.rollback

      expect(rotator.current_key).to eq(primary_key)
      expect(rotator).not_to be_rotation_complete
    end
  end

  describe "#active_key" do
    it "returns current active key" do
      expect(rotator.active_key).to eq(primary_key)

      rotator.switch_to_secondary(validate: false)
      expect(rotator.active_key).to eq(secondary_key)
    end
  end
end

RSpec.describe Vectra::CredentialRotationManager do
  before { described_class.clear! }

  describe ".register" do
    it "creates rotator for provider" do
      described_class.register(:pinecone, primary: "key1", secondary: "key2")
      expect(described_class[:pinecone]).to be_a(Vectra::CredentialRotator)
    end
  end

  describe ".[]" do
    it "returns registered rotator" do
      described_class.register(:qdrant, primary: "key1")
      expect(described_class[:qdrant].primary_key).to eq("key1")
    end
  end

  describe ".test_all_secondary" do
    it "tests all secondary keys" do
      mock_client1 = instance_double(Vectra::Client, healthy?: true)
      mock_client2 = instance_double(Vectra::Client, healthy?: false)

      rotator1 = Vectra::CredentialRotator.new(
        primary_key: "key1",
        secondary_key: "key1-new",
        test_client: mock_client1
      )
      rotator2 = Vectra::CredentialRotator.new(
        primary_key: "key2",
        secondary_key: "key2-new",
        test_client: mock_client2
      )

      described_class.instance_variable_set(:@rotators, { a: rotator1, b: rotator2 })

      results = described_class.test_all_secondary
      expect(results[:a]).to be true
      expect(results[:b]).to be false
    end
  end

  describe ".status" do
    it "returns rotation status for all providers" do
      described_class.register(:test, primary: "key1", secondary: "key2")
      described_class[:test].switch_to_secondary(validate: false)

      status = described_class.status
      expect(status[:test][:rotation_complete]).to be true
      expect(status[:test][:has_secondary]).to be true
    end
  end
end
