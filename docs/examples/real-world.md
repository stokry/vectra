---
layout: page
title: Real-World Examples
permalink: /examples/real-world/
---

# Real-World Examples

Production-ready examples demonstrating Vectra in real-world scenarios.

## E-Commerce Product Search

Semantic product search with filtering, caching, and performance optimization.

```ruby
require "vectra"

class ProductSearchService
  def initialize
    @client = Vectra.pinecone(
      api_key: ENV["PINECONE_API_KEY"],
      environment: "us-east-1"
    )
    
    # Performance optimizations
    @cache = Vectra::Cache.new(ttl: 600, max_size: 5000)
    @cached_client = Vectra::CachedClient.new(@client, cache: @cache)
    
    # Resilience patterns
    @rate_limiter = Vectra::RateLimiter.new(requests_per_second: 100)
    @circuit_breaker = Vectra::CircuitBreaker.new(
      name: "product-search",
      failure_threshold: 5,
      recovery_timeout: 60
    )
  end

  def search(query:, category: nil, price_range: nil, limit: 20)
    query_embedding = generate_embedding(query)
    
    filter = {}
    filter[:category] = category if category
    filter[:price_min] = price_range[:min] if price_range&.dig(:min)
    filter[:price_max] = price_range[:max] if price_range&.dig(:max)
    
    @rate_limiter.acquire do
      @circuit_breaker.call do
        @cached_client.query(
          index: "products",
          vector: query_embedding,
          top_k: limit,
          filter: filter,
          include_metadata: true
        )
      end
    end
  rescue Vectra::RateLimitError => e
    # Handle rate limiting gracefully
    Rails.logger.warn("Rate limit hit: #{e.retry_after}s")
    sleep(e.retry_after || 1)
    retry
  rescue Vectra::CircuitBreakerOpenError
    # Fallback to cached results or alternative search
    fallback_search(query, category)
  end

  private

  def generate_embedding(text)
    # Use your embedding model (OpenAI, sentence-transformers, etc.)
    OpenAI::Client.new.embeddings(
      parameters: { model: "text-embedding-ada-002", input: text }
    )["data"][0]["embedding"]
  end

  def fallback_search(query, category)
    # Fallback to database search or cached results
    Product.where("name ILIKE ?", "%#{query}%")
      .where(category: category)
      .limit(20)
  end
end

# Usage
service = ProductSearchService.new
results = service.search(
  query: "wireless headphones with noise cancellation",
  category: "Electronics",
  price_range: { min: 50, max: 200 }
)

results.each do |product|
  puts "#{product.metadata[:name]} - $#{product.metadata[:price]}"
end
```

## RAG Chatbot with Streaming

Retrieval-Augmented Generation chatbot with streaming responses and error handling.

```ruby
require "vectra"

class RAGChatbot
  def initialize
    @vectra_client = Vectra.qdrant(
      host: ENV["QDRANT_HOST"],
      api_key: ENV["QDRANT_API_KEY"]
    )
    
    @llm_client = OpenAI::Client.new
    @streaming = Vectra::Streaming.new(@vectra_client)
    
    # Monitoring
    Vectra::Instrumentation::Sentry.setup! if defined?(Sentry)
    Vectra::Logging.setup!(output: "log/chatbot.json.log")
  end

  def chat(user_message:, conversation_id:, &block)
    # 1. Retrieve relevant context
    context = retrieve_context(user_message, limit: 5)
    
    # 2. Build prompt with context
    prompt = build_prompt(user_message, context)
    
    # 3. Stream LLM response
    stream_llm_response(prompt, conversation_id, &block)
    
    # 4. Log interaction
    log_interaction(user_message, context, conversation_id)
  end

  private

  def retrieve_context(query, limit:)
    query_embedding = generate_embedding(query)
    
    results = @streaming.query_each(
      index: "knowledge_base",
      vector: query_embedding,
      top_k: limit,
      batch_size: 10,
      include_metadata: true
    ) do |batch|
      # Process in batches for memory efficiency
      batch
    end
    
    results.map { |r| r.metadata[:content] }.join("\n\n")
  end

  def build_prompt(user_message, context)
    <<~PROMPT
      You are a helpful assistant. Use the following context to answer the question.
      
      Context:
      #{context}
      
      Question: #{user_message}
      
      Answer:
    PROMPT
  end

  def stream_llm_response(prompt, conversation_id, &block)
    @llm_client.chat(
      parameters: {
        model: "gpt-4",
        messages: [{ role: "user", content: prompt }],
        stream: proc { |chunk, _bytesize|
          block.call(chunk) if block
        }
      }
    )
  end

  def log_interaction(user_message, context, conversation_id)
    Vectra::Logging.log_info(
      "Chat interaction",
      conversation_id: conversation_id,
      query_length: user_message.length,
      context_snippets: context.split("\n\n").size
    )
  end

  def generate_embedding(text)
    # Embedding generation
    @llm_client.embeddings(
      parameters: { model: "text-embedding-ada-002", input: text }
    )["data"][0]["embedding"]
  end
end

# Usage with streaming
chatbot = RAGChatbot.new

chatbot.chat(
  user_message: "How do I implement authentication in Rails?",
  conversation_id: "conv-123"
) do |chunk|
  print chunk.dig("choices", 0, "delta", "content")
end
```

## Multi-Tenant SaaS Application

SaaS application with tenant isolation, audit logging, and health monitoring.

```ruby
require "vectra"

class TenantDocumentService
  def initialize(tenant_id:)
    @tenant_id = tenant_id
    @client = Vectra.pgvector(
      connection_url: ENV["DATABASE_URL"],
      pool_size: 10
    )
    
    # Audit logging for compliance
    @audit = Vectra::AuditLog.new(
      output: "log/audit.json.log",
      enabled: true
    )
    
    # Health monitoring
    @health_checker = Vectra::AggregateHealthCheck.new(
      primary: @client
    )
  end

  def index_document(document_id:, content:, metadata: {})
    embedding = generate_embedding(content)
    
    result = @client.upsert(
      index: "documents",
      vectors: [{
        id: document_id,
        values: embedding,
        metadata: metadata.merge(tenant_id: @tenant_id)
      }],
      namespace: "tenant-#{@tenant_id}"
    )
    
    # Audit log
    @audit.log_data_modification(
      user_id: current_user&.id,
      operation: "upsert",
      index: "documents",
      record_count: 1
    )
    
    result
  end

  def search_documents(query:, limit: 20)
    query_embedding = generate_embedding(query)
    
    # Ensure tenant isolation via namespace
    results = @client.query(
      index: "documents",
      vector: query_embedding,
      top_k: limit,
      namespace: "tenant-#{@tenant_id}",
      filter: { tenant_id: @tenant_id }, # Double protection
      include_metadata: true
    )
    
    # Audit log
    @audit.log_access(
      user_id: current_user&.id,
      operation: "query",
      index: "documents",
      result_count: results.size
    )
    
    results
  end

  def health_status
    @health_checker.check_all
  end

  private

  def generate_embedding(text)
    # Your embedding generation
  end
end

# Usage per tenant
tenant_service = TenantDocumentService.new(tenant_id: "acme-corp")

# Index document (isolated to tenant)
tenant_service.index_document(
  document_id: "doc-123",
  content: "Important business document...",
  metadata: { title: "Q4 Report", category: "Finance" }
)

# Search (only returns tenant's documents)
results = tenant_service.search_documents(query: "financial report")

# Health check
health = tenant_service.health_status
puts "System healthy: #{health[:overall_healthy]}"
```

## High-Performance Batch Processing

Processing large datasets with async batch operations and progress tracking.

```ruby
require "vectra"

class DocumentIndexer
  def initialize
    @client = Vectra.pinecone(
      api_key: ENV["PINECONE_API_KEY"],
      environment: "us-east-1"
    )
    
    @batch_client = Vectra::Batch.new(@client)
  end

  def index_large_dataset(documents, concurrency: 4)
    total = documents.size
    processed = 0
    errors = []
    
    # Convert to vectors
    vectors = documents.map do |doc|
      {
        id: doc[:id],
        values: generate_embedding(doc[:content]),
        metadata: doc[:metadata]
      }
    end
    
    # Process in async batches
    result = @batch_client.upsert_async(
      index: "documents",
      vectors: vectors,
      concurrency: concurrency,
      on_progress: proc { |success, failed, total|
        processed = success + failed
        progress = (processed.to_f / total * 100).round(1)
        puts "Progress: #{progress}% (#{processed}/#{total})"
      },
      on_error: proc { |error, vector|
        errors << { id: vector[:id], error: error.message }
      }
    )
    
    {
      success: result[:success],
      failed: result[:failed],
      errors: errors,
      total: total
    }
  end

  private

  def generate_embedding(text)
    # Embedding generation
  end
end

# Usage
indexer = DocumentIndexer.new

# Index 10,000 documents with 4 concurrent workers
result = indexer.index_large_dataset(
  large_document_array,
  concurrency: 4
)

puts "Indexed: #{result[:success]}"
puts "Failed: #{result[:failed]}"
puts "Errors: #{result[:errors].size}"
```

## Production-Ready Configuration

Complete production setup with all monitoring, resilience, and performance features.

```ruby
# config/initializers/vectra.rb
require "vectra"

Vectra.configure do |config|
  config.provider = :pinecone
  config.api_key = Rails.application.credentials.dig(:vectra, :api_key)
  config.environment = ENV["PINECONE_ENVIRONMENT"] || "us-east-1"
  
  # Performance
  config.cache_enabled = true
  config.cache_ttl = 600
  config.cache_max_size = 10000
  config.async_concurrency = 4
  config.batch_size = 100
  
  # Resilience
  config.max_retries = 3
  config.retry_delay = 1
  config.timeout = 30
  
  # Logging
  config.logger = Rails.logger
end

# Setup monitoring
if defined?(Sentry)
  Vectra::Instrumentation::Sentry.setup!
end

if defined?(Honeybadger)
  Vectra::Instrumentation::Honeybadger.setup!
end

# Setup structured logging
Vectra::Logging.setup!(
  output: Rails.root.join("log", "vectra.json.log"),
  app: Rails.application.class.module_parent_name,
  env: Rails.env
)

# Setup audit logging
Vectra::AuditLogging.setup!(
  output: Rails.root.join("log", "audit.json.log"),
  enabled: Rails.env.production?,
  app: Rails.application.class.module_parent_name,
  env: Rails.env
)

# Global rate limiter
$vectra_rate_limiter = Vectra::RateLimiter.new(
  requests_per_second: ENV.fetch("VECTRA_RATE_LIMIT", 100).to_i,
  burst_size: ENV.fetch("VECTRA_BURST_SIZE", 200).to_i
)

# Global circuit breaker
$vectra_circuit_breaker = Vectra::CircuitBreaker.new(
  name: "vectra-main",
  failure_threshold: 5,
  recovery_timeout: 60
)

# Application helper
module VectraHelper
  def vectra_client
    @vectra_client ||= begin
      client = Vectra::Client.new
      cached = Vectra::CachedClient.new(client)
      cached
    end
  end

  def safe_vectra_query(**args)
    $vectra_rate_limiter.acquire do
      $vectra_circuit_breaker.call do
        vectra_client.query(**args)
      end
    end
  rescue Vectra::CircuitBreakerOpenError
    # Fallback logic
    Rails.logger.error("Circuit breaker open, using fallback")
    fallback_search(args)
  rescue Vectra::RateLimitError => e
    Rails.logger.warn("Rate limit: #{e.retry_after}s")
    sleep(e.retry_after || 1)
    retry
  end
end
```

## Best Practices

### 1. Always Use Caching for Frequent Queries

```ruby
cache = Vectra::Cache.new(ttl: 600, max_size: 10000)
cached_client = Vectra::CachedClient.new(client, cache: cache)
```

### 2. Implement Rate Limiting

```ruby
limiter = Vectra::RateLimiter.new(requests_per_second: 100)
limiter.acquire { client.query(...) }
```

### 3. Use Circuit Breaker for Resilience

```ruby
breaker = Vectra::CircuitBreaker.new(failure_threshold: 5)
breaker.call { client.query(...) }
```

### 4. Enable Monitoring

```ruby
Vectra::Instrumentation::Sentry.setup!
Vectra::Logging.setup!(output: "log/vectra.json.log")
```

### 5. Audit Critical Operations

```ruby
audit = Vectra::AuditLog.new(output: "log/audit.json.log")
audit.log_access(user_id: user.id, operation: "query", index: "docs")
```

### 6. Use Streaming for Large Queries

```ruby
streaming = Vectra::Streaming.new(client)
streaming.query_each(index: "docs", vector: vec, batch_size: 100) do |batch|
  process_batch(batch)
end
```

### 7. Health Checks in Production

```ruby
health = client.health_check(include_stats: true)
raise "Unhealthy" unless health.healthy?
```

## Next Steps

- [Comprehensive Demo](../examples/) - Full feature demonstration
- [Performance Guide](../guides/performance/) - Optimization strategies
- [Monitoring Guide](../guides/monitoring/) - Production monitoring
- [Security Guide](../guides/security/) - Security best practices
