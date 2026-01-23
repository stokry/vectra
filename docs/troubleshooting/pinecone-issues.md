---
layout: page
title: Pinecone Issues
permalink: /troubleshooting/pinecone-issues/
---

# Pinecone-Specific Issues

Common issues when using Pinecone with Vectra.

## Environment/Region Issues

### `ConfigurationError: Environment must be specified`

**Cause:** Pinecone requires an environment/region (e.g., `us-west-4`).

**Solution:**
```ruby
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'  # Required!
)
```

### Wrong Environment

**Cause:** Using environment that doesn't match your index.

**Solution:**
- Check your Pinecone dashboard for correct environment
- Ensure environment matches where your index was created

## Index Management

### `NotFoundError: Index not found`

**Cause:** Index doesn't exist in specified environment.

**Solution:**
```ruby
# List indexes to verify
indexes = client.list_indexes
puts indexes.map { |idx| idx[:name] }

# Create if missing
client.create_index(
  name: 'my-index',
  dimension: 1536,
  metric: 'cosine'
)
```

## Hybrid Search Limitations

### Hybrid Search Not Working as Expected

**Cause:** Pinecone requires sparse vectors for true hybrid search, not just text.

**Solution:**
```ruby
# Pinecone hybrid search needs sparse vectors
# Generate sparse vector from text using BM25 or similar
sparse_vector = generate_sparse_vector(text)  # Your implementation

# Then use sparse_values in upsert
client.upsert(
  index: 'docs',
  vectors: [{
    id: 'doc-1',
    values: dense_embedding,
    sparse_values: sparse_vector  # Required for hybrid search
  }]
)

# For query, you'd need to provide sparse vector too
# Vectra's hybrid_search may fall back to dense-only
```

**Note:** Vectra's `hybrid_search` with Pinecone currently uses dense vectors only. For true hybrid search, generate sparse vectors externally.

## Namespace Issues

### Namespace Not Working

**Cause:** Namespace parameter not passed or incorrect.

**Solution:**
```ruby
# Explicitly set namespace
client.upsert(
  index: 'docs',
  vectors: [...],
  namespace: 'production'  # Must match in query
)

# Query from same namespace
results = client.query(
  index: 'docs',
  vector: emb,
  namespace: 'production'  # Same namespace
)
```

## Rate Limits

### `RateLimitError: Rate limit exceeded`

**Cause:** Pinecone has strict rate limits based on plan.

**Solution:**
```ruby
# Add retry middleware
Vectra::Client.use Vectra::Middleware::Retry, max_attempts: 5

# Or implement backoff
begin
  client.upsert(...)
rescue Vectra::RateLimitError => e
  sleep(e.retry_after || 60)
  retry
end
```

## Dimension Mismatch

### `ValidationError: Vector dimension mismatch`

**Cause:** Vector dimension doesn't match index dimension.

**Solution:**
```ruby
# Check index dimension
index_info = client.describe_index(index: 'my-index')
required_dim = index_info[:dimension]

# Ensure vectors match
vectors = [
  { id: '1', values: Array.new(required_dim, 0.1) }  # Correct dimension
]
```

## API Version

### Unexpected API Errors

**Cause:** Pinecone API version mismatch.

**Solution:**
Vectra uses Pinecone API v2024-07. If you encounter issues:
- Check Pinecone changelog for breaking changes
- Report issue to [Vectra GitHub](https://github.com/stokry/vectra/issues)

## Connection Issues

### `ConnectionError: Failed to connect to Pinecone`

**Cause:** Network issues or incorrect API endpoint.

**Solution:**
```ruby
# Test connection
if client.healthy?
  puts "Connected"
else
  puts "Connection failed - check network/API key"
end

# Check ping
status = client.ping
puts "Latency: #{status[:latency_ms]}ms"
```

## Getting Help

- [Pinecone Documentation](https://docs.pinecone.io/)
- [Common Errors](/troubleshooting/common-errors/)
- [GitHub Issues](https://github.com/stokry/vectra/issues)
