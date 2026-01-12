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

- [API Reference]({{ site.baseurl }}/api/overview)
- [Provider Guides]({{ site.baseurl }}/providers)
- [Examples]({{ site.baseurl }}/examples/basic-usage)
