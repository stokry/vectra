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

You can either use the convenience constructor:

```ruby
client = Vectra.weaviate(
  api_key: ENV["WEAVIATE_API_KEY"], # optional for local / required for cloud
  host: "http://localhost:8080"     # or your cloud endpoint
)
```

or configure via `Vectra::Client`:

```ruby
client = Vectra::Client.new(
  provider: :weaviate,
  api_key: ENV["WEAVIATE_API_KEY"],
  host: "https://your-weaviate-instance"
)
```

## Features

- ✅ Upsert vectors into Weaviate classes (per-index `class`)
- ✅ Vector similarity search via GraphQL `nearVector`
- ✅ Fetch by IDs
- ✅ Metadata filtering (exact match, ranges, arrays)
- ✅ Namespace support via `_namespace` property
- ✅ Delete by IDs or filter
- ✅ List and describe classes
- ✅ Basic stats via GraphQL `Aggregate`

## Basic Example

```ruby
require "vectra"

client = Vectra.weaviate(
  api_key: ENV["WEAVIATE_API_KEY"],
  host: "https://your-weaviate-instance"
)

index = "Document" # Weaviate class name

# Upsert vectors
client.upsert(
  index: index,
  vectors: [
    {
      id: "doc-1",
      values: [0.1, 0.2, 0.3],
      metadata: {
        title: "Getting started with Vectra",
        category: "docs"
      }
    }
  ],
  namespace: "prod" # stored as _namespace property
)

# Query with metadata filter
results = client.query(
  index: index,
  vector: [0.1, 0.2, 0.3],
  top_k: 5,
  namespace: "prod",
  filter: { category: "docs" },
  include_metadata: true
)

results.each do |match|
  puts "#{match.id} (score=#{match.score.round(3)}): #{match.metadata["title"]}"
end
```

## Advanced Filtering

Vectra maps simple Ruby hashes to Weaviate `where` filters:

```ruby
results = client.query(
  index: "Document",
  vector: query_embedding,
  top_k: 10,
  filter: {
    category: "blog",
    views: { "$gt" => 1000 },
    tags: ["ruby", "vectra"] # ContainsAny
  },
  include_metadata: true
)
```

Supported operators:

- Equality: `{ field: "value" }` or `{ field: { "$eq" => "value" } }`
- Inequality: `{ field: { "$ne" => "value" } }`
- Ranges: `{ field: { "$gt" => 10 } }`, `{ "$gte" => 10 }`, `{ "$lt" => 20 }`, `{ "$lte" => 20 }`
- Arrays: `{ field: ["a", "b"] }` (contains any), `{ field: { "$in" => ["a", "b"] } }`

## Configuration Options

| Option   | Type   | Required | Description                                   |
|----------|--------|----------|-----------------------------------------------|
| `host`   | String | Yes      | Weaviate base URL (`http://` or `https://`)  |
| `api_key`| String | No*      | API key if auth is enabled / cloud instances |

> `api_key` is optional for local, unsecured Weaviate; required for managed/cloud deployments.

## Documentation

- [Weaviate Docs](https://weaviate.io/developers)
- [Weaviate API Reference](https://weaviate.io/developers/weaviate/api/rest)
