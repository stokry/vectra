---
layout: page
title: Common Errors
permalink: /troubleshooting/common-errors/
---

# Common Errors and Solutions

This guide covers common errors you might encounter when using Vectra.

## Configuration Errors

### `ConfigurationError: Provider must be configured`

**Cause:** No provider specified in client initialization or global config.

**Solution:**
```ruby
# Set provider explicitly
client = Vectra::Client.new(provider: :qdrant, ...)

# Or configure globally
Vectra.configure do |config|
  config.provider = :qdrant
end
```

### `ConfigurationError: API key must be configured`

**Cause:** Missing API key for cloud providers (Pinecone, Qdrant Cloud, Weaviate Cloud).

**Solution:**
```ruby
# Set API key
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  ...
)

# Or use Rails credentials
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: Rails.application.credentials.pinecone_api_key,
  ...
)
```

### `UnsupportedProviderError: Provider 'xyz' is not supported`

**Cause:** Invalid provider name.

**Solution:**
Use one of: `:pinecone`, `:qdrant`, `:weaviate`, `:pgvector`, `:memory`

```ruby
client = Vectra::Client.new(provider: :qdrant, ...)  # ✅
client = Vectra::Client.new(provider: 'qdrant', ...)  # ✅ (auto-converted)
client = Vectra::Client.new(provider: :invalid, ...)  # ❌
```

## Validation Errors

### `ValidationError: Index name cannot be nil`

**Cause:** No index specified and no default index set.

**Solution:**
```ruby
# Option 1: Set default index
client = Vectra::Client.new(index: 'docs', ...)
client.upsert(vectors: [...])  # Uses 'docs'

# Option 2: Specify index in call
client.upsert(index: 'docs', vectors: [...])

# Option 3: In Rails, use config/vectra.yml with single entry
```

### `ValidationError: Vectors cannot be empty`

**Cause:** Empty array passed to `upsert`.

**Solution:**
```ruby
# Check before upserting
vectors = prepare_vectors
client.upsert(index: 'docs', vectors: vectors) if vectors.any?
```

### `ValidationError: Inconsistent vector dimensions`

**Cause:** Vectors in a batch have different dimensions.

**Solution:**
```ruby
# Ensure all vectors have same dimension
vectors = [
  { id: '1', values: [0.1, 0.2, 0.3] },  # 3 dimensions
  { id: '2', values: [0.4, 0.5, 0.6] }   # 3 dimensions ✅
]

# Not:
vectors = [
  { id: '1', values: [0.1, 0.2] },       # 2 dimensions
  { id: '2', values: [0.4, 0.5, 0.6] }   # 3 dimensions ❌
]
```

## Connection Errors

### `ConnectionError: Failed to connect`

**Cause:** Provider host unreachable or incorrect URL.

**Solution:**
```ruby
# Check host URL
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'http://localhost:6333'  # Verify this is correct
)

# Test connection
if client.healthy?
  puts "Connected!"
else
  puts "Connection failed"
end
```

### `TimeoutError: Request timed out`

**Cause:** Request took longer than configured timeout.

**Solution:**
```ruby
# Increase timeout
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'http://localhost:6333',
  timeout: 60  # seconds
)

# Or temporarily override
client.with_timeout(120) do |c|
  c.upsert(index: 'docs', vectors: large_batch)
end
```

## Authentication Errors

### `AuthenticationError: Invalid API key`

**Cause:** Wrong or expired API key.

**Solution:**
```ruby
# Verify API key
puts ENV['PINECONE_API_KEY']  # Should not be nil/empty

# Regenerate if needed
# Pinecone: https://app.pinecone.io/
# Qdrant Cloud: https://cloud.qdrant.io/
```

### `AuthenticationError: Access forbidden`

**Cause:** API key doesn't have required permissions.

**Solution:**
- Check API key permissions in provider dashboard
- Regenerate API key with correct permissions
- Verify you're using the right environment/region

## Not Found Errors

### `NotFoundError: Index 'xyz' not found`

**Cause:** Index doesn't exist.

**Solution:**
```ruby
# Create index first
client.create_index(name: 'xyz', dimension: 1536, metric: 'cosine')

# Or check if exists
indexes = client.list_indexes
if indexes.any? { |idx| idx[:name] == 'xyz' }
  # Index exists
else
  client.create_index(name: 'xyz', dimension: 1536, metric: 'cosine')
end
```

### `NotFoundError: Vector ID 'xyz' not found`

**Cause:** Vector doesn't exist in index.

**Solution:**
```ruby
# Check if vector exists before fetching
vectors = client.fetch(index: 'docs', ids: ['xyz'])
if vectors['xyz']
  # Vector exists
else
  # Vector not found
end
```

## Feature Support Errors

### `UnsupportedFeatureError: Hybrid search is not supported by pinecone provider`

**Cause:** Provider doesn't support the requested feature.

**Solution:**
```ruby
# Check feature support before using
if client.provider.respond_to?(:hybrid_search)
  results = client.hybrid_search(...)
else
  # Fallback to vector search
  results = client.query(...)
end

# Or validate upfront
client.validate!(features: [:hybrid_search])
```

## Rate Limit Errors

### `RateLimitError: Rate limit exceeded`

**Cause:** Too many requests in short time.

**Solution:**
```ruby
# Add retry middleware
Vectra::Client.use Vectra::Middleware::Retry, max_attempts: 5

# Or implement exponential backoff
begin
  client.upsert(...)
rescue Vectra::RateLimitError => e
  sleep(e.retry_after || 60)
  retry
end
```

## Data Type Errors

### `TypeError: no implicit conversion of String into Integer`

**Cause:** Using integer IDs when provider expects strings (or vice versa).

**Solution:**
```ruby
# Always use string IDs for consistency
client.upsert(vectors: [
  { id: '1', values: [...] },  # ✅
  { id: '2', values: [...] }   # ✅
])

# Not:
client.upsert(vectors: [
  { id: 1, values: [...] },    # ⚠️ May work but not recommended
  { id: 2, values: [...] }
])
```

## Memory/Performance Errors

### `NoMemoryError` or Slow Performance

**Cause:** Processing too many vectors at once.

**Solution:**
```ruby
# Use batch operations
Vectra::Batch.upsert_async(
  index: 'docs',
  vectors: large_array,
  chunk_size: 100,  # Process in chunks
  on_progress: ->(stats) {
    puts "Processed: #{stats[:processed]}/#{stats[:total]}"
  }
)
```

## Debugging Tips

### 1. Enable Logging

```ruby
Vectra.configure do |config|
  config.logger = Rails.logger  # Or Logger.new(STDOUT)
end

# Or use middleware
Vectra::Client.use Vectra::Middleware::Logging
```

### 2. Validate Configuration

```ruby
# Check if client is properly configured
if client.valid?
  puts "Client is valid"
else
  puts "Client has issues"
end

# Detailed validation
begin
  client.validate!(require_default_index: true, features: [:text_search])
  puts "All checks passed"
rescue Vectra::ConfigurationError => e
  puts "Validation failed: #{e.message}"
end
```

### 3. Check Health

```ruby
# Quick health check
if client.healthy?
  puts "Provider is healthy"
else
  puts "Provider is unhealthy"
end

# Detailed health check
health = client.health_check
puts health.inspect
```

### 4. Test with Memory Provider

```ruby
# Use memory provider for debugging
client = Vectra::Client.new(provider: :memory)
# No external dependencies, fast tests
```

## Getting More Help

- [Pinecone Issues](/troubleshooting/pinecone-issues/)
- [Qdrant Issues](/troubleshooting/qdrant-issues/)
- [pgvector Issues](/troubleshooting/pgvector-issues/)
- [GitHub Issues](https://github.com/stokry/vectra/issues)
