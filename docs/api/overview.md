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
