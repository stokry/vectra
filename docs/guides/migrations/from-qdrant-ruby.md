---
layout: page
title: Migrating from qdrant-ruby
permalink: /guides/migrations/from-qdrant-ruby/
---

# Migrating from qdrant-ruby to vectra-client

This guide helps you migrate from the `qdrant-ruby` gem to `vectra-client`.

## Why Migrate?

- **Unified API**: Same interface across Pinecone, Qdrant, Weaviate, pgvector
- **Production-ready**: Middleware, retry logic, circuit breakers built-in
- **Better testing**: In-memory provider for fast tests
- **ActiveRecord integration**: `has_vector` DSL for Rails apps

## Step 1: Update Gemfile

```ruby
# Remove
gem 'qdrant-ruby'

# Add
gem 'vectra-client'
```

Then run:
```bash
bundle install
```

## Step 2: Update Client Initialization

### Before (qdrant-ruby)

```ruby
require 'qdrant'

client = Qdrant::Client.new(
  url: 'http://localhost:6333',
  api_key: ENV['QDRANT_API_KEY']  # Optional
)
```

### After (vectra-client)

```ruby
require 'vectra'

client = Vectra::Client.new(
  provider: :qdrant,
  host: 'http://localhost:6333',
  api_key: ENV['QDRANT_API_KEY']  # Optional for local
)
```

## Step 3: Update Method Calls

### Collections → Indexes

Qdrant uses "collections", but Vectra uses "indexes" for consistency across providers.

### Upsert

**Before:**
```ruby
collection = client.collections.get('my-collection')
collection.upsert(
  points: [
    { id: 1, vector: [0.1, 0.2, 0.3], payload: { title: 'Hello' } }
  ]
)
```

**After:**
```ruby
client.upsert(
  index: 'my-collection',
  vectors: [
    { id: '1', values: [0.1, 0.2, 0.3], metadata: { title: 'Hello' } }
  ]
)
```

**Key differences:**
- `points` → `vectors`
- `id` can be string (Qdrant supports both, Vectra uses strings for consistency)
- `vector` → `values`
- `payload` → `metadata`

### Query

**Before:**
```ruby
collection = client.collections.get('my-collection')
results = collection.search(
  vector: [0.1, 0.2, 0.3],
  limit: 10,
  filter: { must: [{ key: 'category', match: { value: 'docs' } }] }
)
```

**After:**
```ruby
results = client.query(
  index: 'my-collection',
  vector: [0.1, 0.2, 0.3],
  top_k: 10,
  filter: { category: 'docs' }  # Simplified filter syntax
)
```

**Filter differences:**

Qdrant uses complex filter syntax:
```ruby
filter: {
  must: [
    { key: 'category', match: { value: 'docs' } },
    { key: 'price', range: { gte: 10, lte: 100 } }
  ]
}
```

Vectra uses simplified syntax (automatically converted):
```ruby
filter: {
  category: 'docs',
  price: { gte: 10, lte: 100 }
}
```

### Fetch

**Before:**
```ruby
collection = client.collections.get('my-collection')
points = collection.retrieve(ids: [1, 2])
```

**After:**
```ruby
vectors = client.fetch(
  index: 'my-collection',
  ids: ['1', '2']  # String IDs
)
```

### Delete

**Before:**
```ruby
collection = client.collections.get('my-collection')
collection.delete(points: [1, 2])
```

**After:**
```ruby
client.delete(
  index: 'my-collection',
  ids: ['1', '2']
)
```

## Step 4: Collection Management

### List Collections

**Before:**
```ruby
collections = client.collections.list
```

**After:**
```ruby
indexes = client.list_indexes
# Returns Array<Hash> with collection details
```

### Create Collection

**Before:**
```ruby
client.collections.create(
  collection_name: 'my-collection',
  vectors: { size: 1536, distance: 'Cosine' }
)
```

**After:**
```ruby
client.create_index(
  name: 'my-collection',
  dimension: 1536,
  metric: 'cosine'
)
```

### Describe Collection

**Before:**
```ruby
info = client.collections.get('my-collection')
```

**After:**
```ruby
info = client.describe_index(index: 'my-collection')
```

## Step 5: Response Format Differences

### Query Results

**Before:**
```ruby
results.each do |result|
  puts result['id']
  puts result['score']
  puts result['payload']
end
```

**After:**
```ruby
results.each do |match|
  puts match.id        # String
  puts match.score     # Float
  puts match.metadata  # Hash (was 'payload')
end
```

### Fetch Results

**Before:**
```ruby
points = collection.retrieve(ids: [1])
points[0]['vector']
```

**After:**
```ruby
vectors = client.fetch(index: 'my-collection', ids: ['1'])
vectors['1'].values  # Vectra::Vector object
```

## Step 6: Filter Syntax Migration

### Simple Filters

**Before:**
```ruby
filter: {
  must: [{ key: 'category', match: { value: 'docs' } }]
}
```

**After:**
```ruby
filter: { category: 'docs' }
```

### Range Filters

**Before:**
```ruby
filter: {
  must: [
    { key: 'price', range: { gte: 10, lte: 100 } }
  ]
}
```

**After:**
```ruby
filter: { price: { gte: 10, lte: 100 } }
```

### Complex Filters

For complex filters (AND/OR/NOT), Vectra converts them automatically. If you need full control, you can still use Qdrant's native filter format:

```ruby
# Vectra will pass through complex filters
filter: {
  must: [
    { key: 'category', match: { value: 'docs' } },
    { key: 'price', range: { gte: 10 } }
  ]
}
```

## Step 7: Advanced Features

### Hybrid Search

Qdrant supports hybrid search (BM25 + vector). Vectra exposes this:

```ruby
results = client.hybrid_search(
  index: 'my-collection',
  vector: embedding,
  text: 'ruby programming',
  alpha: 0.7
)
```

### Text Search

Qdrant's BM25 text search:

```ruby
results = client.text_search(
  index: 'my-collection',
  text: 'iPhone 15 Pro',
  top_k: 10
)
```

### Default Index/Namespace

```ruby
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'http://localhost:6333',
  index: 'my-collection',
  namespace: 'default'
)

# Omit index/namespace in calls
client.upsert(vectors: [...])
```

## Migration Checklist

- [ ] Update `Gemfile` (remove `qdrant-ruby`, add `vectra-client`)
- [ ] Update client initialization (`url` → `host`)
- [ ] Replace `client.collections.get('name')` with direct method calls
- [ ] Update `points` → `vectors`, `payload` → `metadata`
- [ ] Convert ID types to strings if needed
- [ ] Simplify filter syntax where possible
- [ ] Update query result iteration (use `match.id` instead of `result['id']`)
- [ ] Update fetch result access (use `.values` instead of `['vector']`)
- [ ] Test all operations (upsert, query, fetch, delete)
- [ ] Test hybrid search and text search if used

## Need Help?

- [API Reference](/api/methods/)
- [Qdrant Provider Guide](/providers/qdrant/)
- [GitHub Issues](https://github.com/stokry/vectra/issues)
