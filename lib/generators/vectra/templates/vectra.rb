# frozen_string_literal: true

# Vectra configuration
#
# For more information see: https://github.com/stokry/vectra

# Ensure Vectra and all Providers are loaded (important for Rails autoloading)
require 'vectra'

Vectra.configure do |config|
  # Provider configuration
  config.provider = :<%= options[:provider] %>

  <%- if options[:provider] == 'pinecone' -%>
  # Pinecone credentials
  config.api_key = Rails.application.credentials.dig(:pinecone, :api_key)
  config.environment = Rails.application.credentials.dig(:pinecone, :environment) || 'us-east-1'
  # Or use direct host:
  # config.host = 'your-index-host.pinecone.io'

  <%- elsif options[:provider] == 'pgvector' -%>
  # PostgreSQL with pgvector extension
  <%- if options[:database_url] -%>
  config.host = '<%= options[:database_url] %>'
  <%- else -%>
  config.host = ENV['DATABASE_URL'] || Rails.configuration.database_configuration[Rails.env]['url']
  <%- end -%>
  config.api_key = nil  # pgvector uses connection URL for auth

  # Connection pooling (recommended for production)
  config.pool_size = ENV.fetch('VECTRA_POOL_SIZE', 10).to_i
  config.pool_timeout = 5

  # Batch operations
  config.batch_size = ENV.fetch('VECTRA_BATCH_SIZE', 100).to_i

  <%- elsif options[:provider] == 'qdrant' -%>
  # Qdrant credentials
  config.api_key = Rails.application.credentials.dig(:qdrant, :api_key)
  config.host = Rails.application.credentials.dig(:qdrant, :host)

  <%- elsif options[:provider] == 'weaviate' -%>
  # Weaviate credentials
  config.api_key = Rails.application.credentials.dig(:weaviate, :api_key)
  config.host = Rails.application.credentials.dig(:weaviate, :host)

  <%- end -%>
  # Timeouts
  config.timeout = 30
  config.open_timeout = 10

  # Retry configuration
  config.max_retries = 3
  config.retry_delay = 1

  # Logging
  config.logger = Rails.logger

  <%- if options[:instrumentation] -%>
  # Instrumentation (metrics and monitoring)
  config.instrumentation = true

  # Uncomment for New Relic:
  # require 'vectra/instrumentation/new_relic'
  # Vectra::Instrumentation::NewRelic.setup!

  # Uncomment for Datadog:
  # require 'vectra/instrumentation/datadog'
  # Vectra::Instrumentation::Datadog.setup!(
  #   host: ENV['DD_AGENT_HOST'] || 'localhost',
  #   port: ENV['DD_DOGSTATSD_PORT']&.to_i || 8125
  # )

  # Custom instrumentation:
  # Vectra.on_operation do |event|
  #   Rails.logger.info "Vectra: #{event.operation} on #{event.provider} took #{event.duration}ms"
  #   if event.failure?
  #     Rails.logger.error "Vectra error: #{event.error.message}"
  #   end
  # end
  <%- end -%>
end
