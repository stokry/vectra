---
layout: page
title: Qdrant
permalink: /providers/qdrant/
---

# Qdrant Provider

[Qdrant](https://qdrant.tech/) is an open-source vector search engine.

## Setup

### Local Installation

```bash
docker run -p 6333:6333 qdrant/qdrant
```

### Connect with Vectra

```ruby
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'localhost',
  port: 6333,
  collection_name: 'my-collection'
)
```

## Features

- ✅ Upsert vectors
- ✅ Query/search
- ✅ Delete vectors
- ✅ Fetch vectors by ID
- ✅ Collection management
- ✅ Metadata filtering
- ✅ Hybrid search

## Example

```ruby
# Initialize client
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'localhost',
  port: 6333
)

# Upsert vectors
client.upsert(
  vectors: [
    { id: 'doc-1', values: [0.1, 0.2, 0.3], metadata: { source: 'web' } }
  ]
)

# Search
results = client.query(vector: [0.1, 0.2, 0.3], top_k: 10)
```

## Configuration Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `host` | String | Yes | Qdrant host address |
| `port` | Integer | Yes | Qdrant port (default: 6333) |
| `collection_name` | String | No | Collection name |
| `api_key` | String | No | API key if auth is enabled |

## Documentation

- [Qdrant Docs](https://qdrant.tech/documentation/)
- [Qdrant API Reference](https://api.qdrant.tech/)
