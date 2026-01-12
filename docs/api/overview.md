---
layout: page
title: API Overview
permalink: /api/overview/
---

# API Reference

## Client Initialization

```ruby
client = Vectra::Client.new(
  provider: :pinecone,        # Required: :pinecone, :qdrant, :weaviate, :pgvector
  api_key: 'your-api-key',    # Required for cloud providers
  index_name: 'my-index',     # Optional, provider-dependent
  host: 'localhost',          # For self-hosted providers
  port: 6333,                 # For self-hosted providers
  environment: 'us-west-4'    # For Pinecone
)
```

## Core Methods

### `upsert(vectors:)`

Upsert vectors into the index. If a vector with the same ID exists, it will be updated.

**Parameters:**
- `vectors` (Array) - Array of vector hashes

**Vector Hash:**
```ruby
{
  id: 'unique-id',                    # Required
  values: [0.1, 0.2, 0.3],           # Required
  metadata: { key: 'value' }         # Optional
}
```

**Example:**
```ruby
client.upsert(
  vectors: [
    { id: '1', values: [0.1, 0.2], metadata: { category: 'news' } }
  ]
)
```

### `query(vector:, top_k:, include_metadata:)`

Search for similar vectors.

**Parameters:**
- `vector` (Array) - Query vector
- `top_k` (Integer) - Number of results to return (default: 10)
- `include_metadata` (Boolean) - Include metadata in results (default: true)

**Returns:**
```ruby
Vectra::QueryResult {
  matches: [
    { id: '1', score: 0.95, metadata: {...} },
    ...
  ],
  namespace: 'default'
}
```

**Example:**
```ruby
results = client.query(vector: [0.1, 0.2], top_k: 5)
```

### `delete(ids:)`

Delete vectors by IDs.

**Parameters:**
- `ids` (Array) - Array of vector IDs to delete

**Example:**
```ruby
client.delete(ids: ['vec-1', 'vec-2'])
```

### `fetch(ids:)`

Fetch vectors by IDs.

**Parameters:**
- `ids` (Array) - Array of vector IDs

**Returns:**
```ruby
{
  'vec-1' => { values: [...], metadata: {...} },
  ...
}
```

### `stats`

Get index statistics.

**Returns:**
```ruby
{
  'dimension' => 1536,
  'vector_count' => 1000,
  'index_fullness' => 0.8
}
```

### `hybrid_search(index:, vector:, text:, alpha:, top_k:)`

Combine semantic (vector) and keyword (text) search.

**Parameters:**
- `index` (String) - Index/collection name
- `vector` (Array) - Query vector for semantic search
- `text` (String) - Text query for keyword search
- `alpha` (Float) - Balance between semantic and keyword (0.0 = pure keyword, 1.0 = pure semantic)
- `top_k` (Integer) - Number of results (default: 10)
- `namespace` (String, optional) - Namespace
- `filter` (Hash, optional) - Metadata filter
- `include_values` (Boolean) - Include vector values (default: false)
- `include_metadata` (Boolean) - Include metadata (default: true)

**Example:**
```ruby
results = client.hybrid_search(
  index: 'docs',
  vector: embedding,
  text: 'ruby programming',
  alpha: 0.7  # 70% semantic, 30% keyword
)
```

**Provider Support:** Qdrant ✅, Weaviate ✅, pgvector ✅, Pinecone ⚠️

### `healthy?`

Quick health check - returns true if provider connection is healthy.

**Returns:** Boolean

**Example:**
```ruby
if client.healthy?
  client.upsert(...)
end
```

### `ping`

Ping provider and get connection health status with latency.

**Returns:**
```ruby
{
  healthy: true,
  provider: :pinecone,
  latency_ms: 45.23
}
```

**Example:**
```ruby
status = client.ping
puts "Latency: #{status[:latency_ms]}ms"
```

### `Vector.normalize(vector, type: :l2)`

Normalize a vector array (non-mutating).

**Parameters:**
- `vector` (Array) - Vector values to normalize
- `type` (Symbol) - Normalization type: `:l2` (default) or `:l1`

**Returns:** Array of normalized values

**Example:**
```ruby
embedding = openai_response['data'][0]['embedding']
normalized = Vectra::Vector.normalize(embedding)
client.upsert(vectors: [{ id: 'doc-1', values: normalized }])
```

### `vector.normalize!(type: :l2)`

Normalize vector in-place (mutates the vector).

**Parameters:**
- `type` (Symbol) - Normalization type: `:l2` (default) or `:l1`

**Returns:** Self (for method chaining)

**Example:**
```ruby
vector = Vectra::Vector.new(id: 'doc-1', values: embedding)
vector.normalize!  # L2 normalization
client.upsert(vectors: [vector])
```

## Error Handling

```ruby
begin
  client.query(vector: [0.1, 0.2])
rescue Vectra::Error => e
  puts "Vectra error: #{e.message}"
rescue => e
  puts "Unexpected error: #{e.message}"
end
```

See [Detailed API Documentation]({{ site.baseurl }}/api/methods) for more methods.
