---
layout: page
title: Migrating from pinecone-ruby
permalink: /guides/migrations/from-pinecone-ruby/
---

# Migrating from pinecone-ruby to vectra-client

This guide helps you migrate from the official `pinecone-ruby` gem to `vectra-client`.

## Why Migrate?

- **Multi-provider support**: Switch between Pinecone, Qdrant, Weaviate, pgvector without code changes
- **Production patterns**: Built-in middleware, retry logic, circuit breakers
- **Better testing**: In-memory provider for fast tests
- **ActiveRecord integration**: `has_vector` DSL for Rails apps

## Step 1: Update Gemfile

```ruby
# Remove
gem 'pinecone-ruby'

# Add
gem 'vectra-client'
```

Then run:
```bash
bundle install
```

## Step 2: Update Client Initialization

### Before (pinecone-ruby)

```ruby
require 'pinecone'

client = Pinecone::Client.new(
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'
)
```

### After (vectra-client)

```ruby
require 'vectra'

client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'
)
```

## Step 3: Update Method Calls

### Upsert

**Before:**
```ruby
index = client.index('my-index')
index.upsert(
  vectors: [
    { id: 'vec1', values: [0.1, 0.2, 0.3], metadata: { title: 'Hello' } }
  ],
  namespace: 'default'
)
```

**After:**
```ruby
client.upsert(
  index: 'my-index',
  vectors: [
    { id: 'vec1', values: [0.1, 0.2, 0.3], metadata: { title: 'Hello' } }
  ],
  namespace: 'default'
)
```

### Query

**Before:**
```ruby
index = client.index('my-index')
results = index.query(
  vector: [0.1, 0.2, 0.3],
  top_k: 10,
  namespace: 'default',
  filter: { category: 'docs' }
)
```

**After:**
```ruby
results = client.query(
  index: 'my-index',
  vector: [0.1, 0.2, 0.3],
  top_k: 10,
  namespace: 'default',
  filter: { category: 'docs' }
)
```

### Fetch

**Before:**
```ruby
index = client.index('my-index')
vectors = index.fetch(ids: ['vec1', 'vec2'], namespace: 'default')
```

**After:**
```ruby
vectors = client.fetch(
  index: 'my-index',
  ids: ['vec1', 'vec2'],
  namespace: 'default'
)
```

### Delete

**Before:**
```ruby
index = client.index('my-index')
index.delete(ids: ['vec1', 'vec2'], namespace: 'default')
```

**After:**
```ruby
client.delete(
  index: 'my-index',
  ids: ['vec1', 'vec2'],
  namespace: 'default'
)
```

## Step 4: Index Management

### List Indexes

**Before:**
```ruby
indexes = client.list_indexes
```

**After:**
```ruby
indexes = client.list_indexes
# Returns Array<Hash> with index details
```

### Create Index

**Before:**
```ruby
client.create_index(
  name: 'my-index',
  dimension: 1536,
  metric: 'cosine'
)
```

**After:**
```ruby
client.create_index(
  name: 'my-index',
  dimension: 1536,
  metric: 'cosine'
)
```

### Describe Index

**Before:**
```ruby
index_info = client.describe_index('my-index')
```

**After:**
```ruby
index_info = client.describe_index(index: 'my-index')
```

## Step 5: Response Format Differences

### Query Results

**Before (pinecone-ruby):**
```ruby
results.matches.each do |match|
  puts match['id']
  puts match['score']
  puts match['metadata']
end
```

**After (vectra-client):**
```ruby
results.each do |match|
  puts match.id        # String
  puts match.score     # Float
  puts match.metadata  # Hash
end

# Or use helper methods
results.ids     # Array of IDs
results.scores  # Array of scores
results.first   # First match
```

### Fetch Results

**Before:**
```ruby
vectors = index.fetch(ids: ['vec1'])
vectors['vec1']['values']
```

**After:**
```ruby
vectors = client.fetch(index: 'my-index', ids: ['vec1'])
vectors['vec1'].values  # Vectra::Vector object
```

## Step 6: Error Handling

Vectra uses the same error classes where possible, but wraps them in `Vectra::` namespace:

- `Pinecone::ApiError` → `Vectra::Error` (or specific subclasses)
- `Pinecone::ConfigurationError` → `Vectra::ConfigurationError`
- `Pinecone::NotFoundError` → `Vectra::NotFoundError`

## Step 7: Advanced Features

### Default Index/Namespace

Vectra supports default index and namespace:

```ruby
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4',
  index: 'my-index',      # Default index
  namespace: 'default'    # Default namespace
)

# Now you can omit index/namespace:
client.upsert(vectors: [...])
client.query(vector: emb, top_k: 10)
```

### Middleware

Add logging, retry, cost tracking:

```ruby
Vectra::Client.use Vectra::Middleware::Logging
Vectra::Client.use Vectra::Middleware::Retry, max_attempts: 5
```

### Multi-tenant Support

```ruby
client.for_tenant("acme") do |c|
  c.upsert(vectors: [...])
  c.query(vector: emb, top_k: 10)
end
```

## Migration Checklist

- [ ] Update `Gemfile` (remove `pinecone-ruby`, add `vectra-client`)
- [ ] Update client initialization
- [ ] Replace `client.index('name')` pattern with direct method calls
- [ ] Update query result iteration (use `match.id` instead of `match['id']`)
- [ ] Update fetch result access (use `.values` instead of `['values']`)
- [ ] Test all operations (upsert, query, fetch, delete)
- [ ] Update error handling if needed
- [ ] Consider using default index/namespace for cleaner code

## Need Help?

- [API Reference](/api/methods/)
- [Pinecone Provider Guide](/providers/pinecone/)
- [GitHub Issues](https://github.com/stokry/vectra/issues)
