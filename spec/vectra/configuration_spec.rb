# frozen_string_literal: true

RSpec.describe Vectra::Configuration do
  subject(:config) { described_class.new }

  describe "#initialize" do
    it "sets default values" do
      expect(config.provider).to be_nil
      expect(config.api_key).to be_nil
      expect(config.environment).to be_nil
      expect(config.host).to be_nil
      expect(config.timeout).to eq(30)
      expect(config.open_timeout).to eq(10)
      expect(config.max_retries).to eq(3)
      expect(config.retry_delay).to eq(1)
      expect(config.logger).to be_nil
    end
  end

  describe "#provider=" do
    it "accepts supported provider as symbol" do
      config.provider = :pinecone
      expect(config.provider).to eq(:pinecone)
    end

    it "accepts supported provider as string" do
      config.provider = "qdrant"
      expect(config.provider).to eq(:qdrant)
    end

    it "raises error for unsupported provider" do
      expect { config.provider = :invalid }
        .to raise_error(Vectra::UnsupportedProviderError, /not supported/)
    end
  end

  describe "#validate!" do
    context "when provider is not set" do
      it "raises ConfigurationError" do
        config.api_key = "test-key"
        expect { config.validate! }.to raise_error(Vectra::ConfigurationError, /Provider must be configured/)
      end
    end

    context "when api_key is not set" do
      it "raises ConfigurationError" do
        config.provider = :pinecone
        expect { config.validate! }.to raise_error(Vectra::ConfigurationError, /API key must be configured/)
      end
    end

    context "when api_key is empty" do
      it "raises ConfigurationError" do
        config.provider = :pinecone
        config.api_key = ""
        expect { config.validate! }.to raise_error(Vectra::ConfigurationError, /API key must be configured/)
      end
    end

    context "with Pinecone provider" do
      before do
        config.provider = :pinecone
        config.api_key = "test-key"
      end

      it "is valid with environment" do
        config.environment = "us-east-1"
        expect { config.validate! }.not_to raise_error
      end

      it "is valid with host" do
        config.host = "test-index.pinecone.io"
        expect { config.validate! }.not_to raise_error
      end

      it "raises error without environment or host" do
        expect { config.validate! }
          .to raise_error(Vectra::ConfigurationError, /requires either 'environment' or 'host'/)
      end
    end

    context "with Qdrant provider" do
      before do
        config.provider = :qdrant
        config.api_key = "test-key"
      end

      it "is valid with host" do
        config.host = "https://test.qdrant.io"
        expect { config.validate! }.not_to raise_error
      end

      it "raises error without host" do
        expect { config.validate! }
          .to raise_error(Vectra::ConfigurationError, /requires 'host'/)
      end
    end

    context "with Weaviate provider" do
      before do
        config.provider = :weaviate
        config.api_key = "test-key"
      end

      it "is valid with host" do
        config.host = "https://test.weaviate.io"
        expect { config.validate! }.not_to raise_error
      end

      it "raises error without host" do
        expect { config.validate! }
          .to raise_error(Vectra::ConfigurationError, /requires 'host'/)
      end
    end
  end

  describe "#valid?" do
    it "returns true when configuration is valid" do
      config.provider = :pinecone
      config.api_key = "test-key"
      config.environment = "us-east-1"
      expect(config.valid?).to be true
    end

    it "returns false when configuration is invalid" do
      config.provider = :pinecone
      expect(config.valid?).to be false
    end
  end

  describe "#dup" do
    before do
      config.provider = :pinecone
      config.api_key = "test-key"
      config.environment = "us-east-1"
      config.timeout = 60
      config.max_retries = 5
    end

    it "creates a duplicate configuration" do
      duplicate = config.dup

      expect(duplicate.provider).to eq(config.provider)
      expect(duplicate.api_key).to eq(config.api_key)
      expect(duplicate.environment).to eq(config.environment)
      expect(duplicate.timeout).to eq(config.timeout)
      expect(duplicate.max_retries).to eq(config.max_retries)
    end

    it "creates an independent copy" do
      duplicate = config.dup
      duplicate.api_key = "different-key"

      expect(config.api_key).to eq("test-key")
      expect(duplicate.api_key).to eq("different-key")
    end
  end

  describe "#to_h" do
    before do
      config.provider = :pinecone
      config.api_key = "test-key"
      config.environment = "us-east-1"
      config.timeout = 45
    end

    it "converts configuration to hash" do
      hash = config.to_h

      expect(hash).to include(
        provider: :pinecone,
        api_key: "test-key",
        environment: "us-east-1",
        timeout: 45
      )
    end
  end

  describe "global configuration" do
    after { Vectra.reset_configuration! }

    it "provides a global configuration" do
      expect(Vectra.configuration).to be_a(described_class)
    end

    it "allows configuration via block" do
      Vectra.configure do |c|
        c.provider = :pinecone
        c.api_key = "global-key"
      end

      expect(Vectra.configuration.provider).to eq(:pinecone)
      expect(Vectra.configuration.api_key).to eq("global-key")
    end

    it "can reset configuration" do
      Vectra.configure do |c|
        c.provider = :pinecone
        c.api_key = "test"
      end

      Vectra.reset_configuration!

      expect(Vectra.configuration.provider).to be_nil
      expect(Vectra.configuration.api_key).to be_nil
    end
  end
end
