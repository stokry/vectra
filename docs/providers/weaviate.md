---
layout: page
title: Weaviate
permalink: /providers/weaviate/
---

# Weaviate Provider

[Weaviate](https://weaviate.io/) is an open-source vector search engine with semantic search capabilities.

## Setup

### Local Installation

```bash
docker run -p 8080:8080 semitechnologies/weaviate:latest
```

### Connect with Vectra

```ruby
client = Vectra::Client.new(
  provider: :weaviate,
  host: 'localhost',
  port: 8080,
  class_name: 'Document'
)
```

## Features

- ✅ Upsert vectors
- ✅ Query/search
- ✅ Delete vectors
- ✅ Class management
- ✅ Metadata filtering
- ✅ Semantic search

## Example

```ruby
# Initialize client
client = Vectra::Client.new(
  provider: :weaviate,
  host: 'localhost',
  port: 8080
)

# Upsert vectors
client.upsert(
  vectors: [
    { id: 'doc-1', values: [0.1, 0.2, 0.3], metadata: { category: 'news' } }
  ]
)

# Search
results = client.query(vector: [0.1, 0.2, 0.3], top_k: 5)
```

## Configuration Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `host` | String | Yes | Weaviate host address |
| `port` | Integer | Yes | Weaviate port (default: 8080) |
| `class_name` | String | No | Class name for vectors |
| `api_key` | String | No | API key if auth is enabled |

## Documentation

- [Weaviate Docs](https://weaviate.io/developers)
- [Weaviate API Reference](https://weaviate.io/developers/weaviate/api/rest)
