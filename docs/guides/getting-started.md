---
layout: page
title: Getting Started
permalink: /guides/getting-started/
---

# Getting Started with Vectra

## Initialize a Client

```ruby
require 'vectra'

# Initialize with Pinecone
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'
)
```

## Basic Operations

### Upsert Vectors

```ruby
client.upsert(
  vectors: [
    {
      id: 'vec-1',
      values: [0.1, 0.2, 0.3],
      metadata: { title: 'Document 1' }
    },
    {
      id: 'vec-2',
      values: [0.2, 0.3, 0.4],
      metadata: { title: 'Document 2' }
    }
  ]
)
```

### Query (Search)

```ruby
# Classic API
results = client.query(
  vector: [0.1, 0.2, 0.3],
  top_k: 5,
  include_metadata: true
)

results.each do |match|
  puts "ID: #{match.id}, Score: #{match.score}"
end

# Chainable Query Builder
results = client
  .query("my-index")
  .vector([0.1, 0.2, 0.3])
  .top_k(5)
  .with_metadata
  .execute

results.each do |match|
  puts "ID: #{match.id}, Score: #{match.score}"
end
```

### Normalize Embeddings

For better cosine similarity results, normalize your embeddings before upserting:

```ruby
# Normalize OpenAI embeddings (recommended)
embedding = openai_response['data'][0]['embedding']
normalized = Vectra::Vector.normalize(embedding)
client.upsert(vectors: [{ id: 'doc-1', values: normalized }])

# Or normalize in-place
vector = Vectra::Vector.new(id: 'doc-1', values: embedding)
vector.normalize!  # L2 normalization (default, unit vector)
client.upsert(vectors: [vector])

# L1 normalization (sum of absolute values = 1)
vector.normalize!(type: :l1)
```

### Delete Vectors

```ruby
client.delete(ids: ['vec-1', 'vec-2'])
```

### Get Vector Stats

```ruby
stats = client.stats
puts "Index dimension: #{stats['dimension']}"
puts "Vector count: #{stats['vector_count']}"
```

### Health Check & Ping

```ruby
# Quick health check
if client.healthy?
  client.upsert(...)
else
  handle_unhealthy_connection
end

# Ping with latency measurement
status = client.ping
puts "Provider: #{status[:provider]}"
puts "Healthy: #{status[:healthy]}"
puts "Latency: #{status[:latency_ms]}ms"

if status[:error]
  puts "Error: #{status[:error_message]}"
end
```

### Hybrid Search (Semantic + Keyword)

Combine the best of both worlds: semantic understanding from vectors and exact keyword matching:

```ruby
# Hybrid search with 70% semantic, 30% keyword
results = client.hybrid_search(
  index: 'docs',
  vector: embedding,           # Semantic search
  text: 'ruby programming',  # Keyword search
  alpha: 0.7,                 # 0.0 = pure keyword, 1.0 = pure semantic
  top_k: 10
)

results.each do |match|
  puts "#{match.id}: #{match.score}"
end

# Pure semantic (alpha = 1.0)
results = client.hybrid_search(
  index: 'docs',
  vector: embedding,
  text: 'ruby',
  alpha: 1.0
)

# Pure keyword (alpha = 0.0)
results = client.hybrid_search(
  index: 'docs',
  vector: embedding,
  text: 'ruby programming',
  alpha: 0.0
)
```

**Provider Support:**
- **Qdrant**: ✅ Full support (prefetch + rescore API)
- **Weaviate**: ✅ Full support (hybrid GraphQL with BM25)
- **Pinecone**: ⚠️ Partial support (requires sparse vectors for true hybrid search)
- **pgvector**: ✅ Full support (combines vector similarity + PostgreSQL full-text search)

**Note for pgvector:** Your table needs a text column with a tsvector index:
```sql
CREATE INDEX idx_content_fts ON my_index USING gin(to_tsvector('english', content));
```

### Dimension Validation

Vectra automatically validates that all vectors in a batch have the same dimension:

```ruby
# This will raise ValidationError
vectors = [
  { id: "vec1", values: [0.1, 0.2, 0.3] }, # 3 dimensions
  { id: "vec2", values: [0.4, 0.5] }        # 2 dimensions - ERROR!
]

client.upsert(vectors: vectors)
# => ValidationError: Inconsistent vector dimensions at index 1: expected 3, got 2
```

## Rails Generator (vectra:index)

For Rails apps, you can generate everything you need for a model with a single command:

```bash
rails generate vectra:index Product embedding dimension:1536 provider:qdrant
```

This will:

- Create a **pgvector migration** when `provider=pgvector` (adds `embedding` vector column)
- Generate a **model concern** (`ProductVector`) with `has_vector :embedding`
- Update the **model** to include `ProductVector`
- Append an entry to **`config/vectra.yml`** with index metadata (no API keys)

### Complete Rails Integration Guide

For a comprehensive Rails guide including:
- Step-by-step setup
- Embedding generation (OpenAI, Cohere)
- Processing 1000+ products with batch operations
- Background jobs for async processing
- Hybrid search examples
- Performance optimization tips

👉 **[Read the complete Rails Integration Guide]({{ site.baseurl }}/guides/rails-integration/)**

## Configuration

Create a configuration file (Rails: `config/initializers/vectra.rb`):

```ruby
Vectra.configure do |config|
  config.provider = :pinecone
  config.api_key = ENV['PINECONE_API_KEY']
  config.environment = 'us-west-4'
end

# Later in your code:
client = Vectra::Client.new
```

## Next Steps

- **[Rails Integration Guide]({{ site.baseurl }}/guides/rails-integration/)** - Complete step-by-step guide for Rails apps
- [API Reference]({{ site.baseurl }}/api/overview)
- [Provider Guides]({{ site.baseurl }}/providers)
- [Examples]({{ site.baseurl }}/examples/basic-usage)
