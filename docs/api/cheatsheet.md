---
layout: page
title: API Cheatsheet
permalink: /api/cheatsheet/
---

# API Cheatsheet

Quick reference for the most important Vectra APIs.

> For full details, see the [API Overview](/api/overview/) and provider guides.

## Core Client

### Initialize Client

```ruby
require 'vectra'

client = Vectra::Client.new(
  provider: :qdrant,          # :pinecone, :qdrant, :weaviate, :pgvector, :memory
  api_key:  ENV['QDRANT_API_KEY'],
  host:     'http://localhost:6333',
  environment: 'us-west-4'   # For Pinecone
)
```

Or use shortcuts:

```ruby
client = Vectra.qdrant(host: 'http://localhost:6333')
client = Vectra.pinecone(api_key: ENV['PINECONE_API_KEY'], environment: 'us-west-4')
client = Vectra.pgvector(connection_url: ENV['DATABASE_URL'])
client = Vectra.memory # In-memory (testing only)
```

### Upsert

```ruby
client.upsert(
  index: 'documents',
  vectors: [
    {
      id: 'doc-1',
      values: embedding_array,
      metadata: { title: 'Hello World', category: 'docs' }
    }
  ],
  namespace: 'default' # optional
)
```

### Query (similarity search)

```ruby
results = client.query(
  index: 'documents',
  vector: query_embedding,
  top_k: 10,
  filter: { category: 'docs' },
  namespace: 'default',
  include_values: false,
  include_metadata: true
)

results.each do |match|
  puts "#{match.id} (score=#{match.score.round(3)}): #{match.metadata['title']}"
end
```

### Hybrid Search (semantic + keyword)

```ruby
results = client.hybrid_search(
  index: 'documents',
  vector: query_embedding,
  text: 'ruby vector search',
  alpha: 0.7,            # 70% semantic, 30% keyword
  top_k: 10,
  filter: { category: 'blog' }
)
```

Supported providers: Qdrant ✅, Weaviate ✅, pgvector ✅, Pinecone ⚠️

### Fetch

```ruby
vectors = client.fetch(
  index: 'documents',
  ids: ['doc-1', 'doc-2'],
  namespace: 'default'
)

vectors['doc-1'].values   # => [0.1, 0.2, ...]
vectors['doc-1'].metadata # => { 'title' => 'Hello World' }
```

### Update

```ruby
client.update(
  index: 'documents',
  id: 'doc-1',
  metadata: { category: 'guides' }
)
```

### Delete

```ruby
# By IDs
client.delete(index: 'documents', ids: ['doc-1', 'doc-2'])

# By filter
client.delete(index: 'documents', filter: { category: 'old' })

# Delete all in namespace
client.delete(index: 'documents', delete_all: true)
```

### Index Management

```ruby
# Create index
client.create_index(name: 'documents', dimension: 384, metric: 'cosine')

# List indexes
indexes = client.list_indexes
# => [{ name: 'documents', dimension: 384, ... }]

# Describe index
info = client.describe_index(index: 'documents')
# => { name: 'documents', dimension: 384, metric: 'cosine', status: 'ready' }

# Get stats
stats = client.stats(index: 'documents')
# => { total_vector_count: 1000, dimension: 384, namespaces: { ... } }

# List namespaces
namespaces = client.list_namespaces(index: 'documents')
# => ['tenant-1', 'tenant-2']

# Delete index
client.delete_index(name: 'old-index')
```

**Note:** `create_index` and `delete_index` are supported by Pinecone, Qdrant, and pgvector. Memory and Weaviate providers don't support these operations.

---

## Health & Monitoring

### Health Check

```ruby
if client.healthy?
  puts 'Vectra provider is healthy'
else
  puts 'Vectra provider is NOT healthy'
end
```

### Ping (with latency)

```ruby
status = client.ping
# => { healthy: true, provider: :qdrant, latency_ms: 23.4 }

puts "Provider: #{status[:provider]}, latency: #{status[:latency_ms]}ms"
```

### Rails Health Endpoint (Example)

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get '/health/vectra', to: 'health#vectra'
end
```

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def vectra
    client = Vectra::Client.new

    status = client.ping
    if status[:healthy]
      render json: { status: 'ok', provider: status[:provider], latency_ms: status[:latency_ms] }
    else
      render json: { status: 'unhealthy' }, status: :service_unavailable
    end
  rescue => e
    render json: { status: 'error', error: e.message }, status: :service_unavailable
  end
end
```

Use this endpoint for Kubernetes / load balancer health checks.

---

## Vector Helpers

### Normalize Embeddings

```ruby
embedding  = openai_response['data'][0]['embedding']
normalized = Vectra::Vector.normalize(embedding, type: :l2) # or :l1

client.upsert(
  index: 'documents',
  vectors: [
    { id: 'doc-1', values: normalized, metadata: { title: 'Hello' } }
  ]
)
```

### In-Place Normalization

```ruby
vector = Vectra::Vector.new(id: 'doc-1', values: embedding)
vector.normalize! # Mutates values
client.upsert(index: 'documents', vectors: [vector])
```

---

## Batch Operations

### Simple Batch Upsert

```ruby
vectors = products.map do |product|
  {
    id: product.id.to_s,
    values: product.embedding,
    metadata: { name: product.name, price: product.price }
  }
end

client.upsert(index: 'products', vectors: vectors)
```

### Batch with Progress Callback

```ruby
Vectra::Batch.upsert(
  client: client,
  index: 'products',
  vectors: vectors,
  batch_size: 100,
  on_progress: ->(batch_index, total_batches, batch_count) do
    puts "Batch #{batch_index + 1}/#{total_batches} (#{batch_count} vectors)"
  end
)
```

### Batch Query (Multiple Vectors)

```ruby
batch = Vectra::Batch.new(client, concurrency: 4)

# Find similar items for multiple products at once
product_embeddings = products.map(&:embedding)
results = batch.query_async(
  index: 'products',
  vectors: product_embeddings,
  top_k: 5
)

# Each result corresponds to one product
results.each_with_index do |result, i|
  puts "Similar to product #{i}: #{result.ids}"
end
```

---

## ActiveRecord + has_vector DSL

### Basic Setup

```ruby
class Document < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding,
    provider: :qdrant,
    index: 'documents',
    dimension: 1536,
    metadata_fields: [:title, :category]
end
```

### Auto-Index on Save

```ruby
doc = Document.create!(
  title: 'Hello World',
  category: 'docs',
  embedding: EmbeddingService.generate('Hello World')
)
```

### Vector Search from Model

```ruby
results = Document.vector_search(
  embedding: EmbeddingService.generate('vector search in ruby'),
  limit: 10,
  filter: { category: 'docs' }
)

results.each do |doc|
  puts doc.title
end
```

---

## Error Handling

```ruby
begin
  client.query(index: 'missing', vector: [0.1, 0.2, 0.3])
rescue Vectra::NotFoundError => e
  Rails.logger.warn("Index not found: #{e.message}")
rescue Vectra::RateLimitError => e
  Rails.logger.error("Rate limited: #{e.message}")
rescue Vectra::Error => e
  Rails.logger.error("Vectra error: #{e.message}")
end
```

---

## See Also

- [API Overview](/api/overview/)
- [Recipes & Patterns](/guides/recipes/)
- [Rails Integration Guide](/guides/rails-integration/)
- [Memory Provider (Testing)](/providers/memory/)
