---
layout: page
title: Memory Provider
permalink: /providers/memory/
---

# Memory Provider

The **Memory provider** is an in-memory vector store built into Vectra.
It is designed **exclusively for testing, local development, and CI** – no external database required.

> Not for production use. All data lives in process memory and is lost when the process exits.

## When to Use

- ✅ RSpec / Minitest suites (fast, isolated tests)
- ✅ Local development without provisioning Pinecone/Qdrant/Weaviate/pgvector
- ✅ CI pipelines where external services are not available
- ❌ Not suitable for production workloads

## Setup

### Global Configuration (Rails Example)

```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.provider = :memory if Rails.env.test?
end
```

Then in your application code:

```ruby
client = Vectra::Client.new
```

### Direct Construction

```ruby
require "vectra"

client = Vectra.memory
```

No `host`, `api_key`, or environment configuration is required.

## Features

- ✅ `upsert` – store vectors in memory
- ✅ `query` – cosine similarity search (with optional metadata filtering)
- ✅ `fetch` – retrieve vectors by ID
- ✅ `update` – merge metadata for existing vectors
- ✅ `delete` – delete by IDs, namespace, filter, or `delete_all`
- ✅ `list_indexes` / `describe_index` – basic index metadata (dimension, metric)
- ✅ `stats` – vector counts per namespace
- ✅ `clear!` – wipe all data between tests

## Basic Usage

```ruby
client = Vectra.memory

# Upsert
client.upsert(
  index: "documents",
  vectors: [
    {
      id: "doc-1",
      values: [0.1, 0.2, 0.3],
      metadata: { title: "Hello", category: "docs" }
    }
  ],
  namespace: "test-suite"
)

# Query
results = client.query(
  index: "documents",
  vector: [0.1, 0.2, 0.3],
  top_k: 5,
  namespace: "test-suite",
  filter: { category: "docs" },
  include_metadata: true
)

results.each do |match|
  puts "#{match.id}: #{match.metadata["title"]} (score=#{match.score.round(3)})"
end
```

## Metadata Filtering

The Memory provider supports a subset of the same filter operators as other providers:

```ruby
results = client.query(
  index: "products",
  vector: query_embedding,
  top_k: 10,
  filter: {
    status: ["active", "preview"],         # IN
    price: { "$gte" => 10, "$lte" => 100 },# range
    brand: { "$ne" => "Acme" }             # not equal
  },
  include_metadata: true
)
```

Supported operators:

- Equality: `{ field: "value" }` or `{ field: { "$eq" => "value" } }`
- Inequality: `{ field: { "$ne" => "value" } }`
- Ranges: `{ field: { "$gt" => 10 } }`, `{ "$gte" => 10 }`, `{ "$lt" => 20 }`, `{ "$lte" => 20 }`
- Arrays / IN: `{ field: ["a", "b"] }` or `{ field: { "$in" => ["a", "b"] } }`

## Resetting State Between Tests

The Memory provider exposes a `clear!` method to reset all in-memory state:

```ruby
RSpec.describe "MyService" do
  let(:client) { Vectra.memory }

  before do
    client.provider.clear! if client.provider.respond_to?(:clear!)
  end

  # your tests...
end
```

You can also call `clear!` on the provider obtained from a regular `Vectra::Client`:

```ruby
client = Vectra::Client.new(provider: :memory)
client.provider.clear!
```

## Limitations

- Not distributed – data lives only in the current Ruby process.
- No persistence – all vectors are lost when the process exits or `clear!` is called.
- Intended for **testing and development only**, not for production traffic.

