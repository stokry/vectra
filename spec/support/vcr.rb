# frozen_string_literal: true

require "vcr"
require "webmock/rspec"

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: %i[method uri body]
  }

  # Filter sensitive data
  config.filter_sensitive_data("<PINECONE_API_KEY>") { ENV.fetch("PINECONE_API_KEY", "test-api-key") }
  config.filter_sensitive_data("<QDRANT_API_KEY>") { ENV.fetch("QDRANT_API_KEY", "test-api-key") }
  config.filter_sensitive_data("<WEAVIATE_API_KEY>") { ENV.fetch("WEAVIATE_API_KEY", "test-api-key") }

  # Ignore localhost for development
  config.ignore_localhost = true

  # Allow requests to be made when no cassette is active (useful for debugging)
  config.allow_http_connections_when_no_cassette = false
end

# Disable all HTTP requests by default
WebMock.disable_net_connect!(allow_localhost: true)
