# frozen_string_literal: true

RSpec.shared_context "with pinecone configuration" do
  let(:api_key) { "test-pinecone-api-key-12345" }
  let(:environment) { "us-east-1" }
  let(:index_name) { "test-index" }

  before do
    Vectra.configure do |config|
      config.provider = :pinecone
      config.api_key = api_key
      config.environment = environment
    end
  end
end

RSpec.shared_context "with qdrant configuration" do
  let(:api_key) { "test-qdrant-api-key-12345" }
  let(:host) { "https://test.qdrant.io" }
  let(:index_name) { "test-collection" }

  before do
    Vectra.configure do |config|
      config.provider = :qdrant
      config.api_key = api_key
      config.host = host
    end
  end
end

RSpec.shared_context "with weaviate configuration" do
  let(:api_key) { "test-weaviate-api-key-12345" }
  let(:host) { "https://test.weaviate.io" }
  let(:index_name) { "TestClass" }

  before do
    Vectra.configure do |config|
      config.provider = :weaviate
      config.api_key = api_key
      config.host = host
    end
  end
end
