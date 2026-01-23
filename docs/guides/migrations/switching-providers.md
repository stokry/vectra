---
layout: page
title: Switching Providers
permalink: /guides/migrations/switching-providers/
---

# Switching Providers with Vectra

One of Vectra's key benefits is the ability to switch between providers without changing your application code. This guide shows you how.

## Why Switch Providers?

- **Cost optimization**: Move from managed (Pinecone) to self-hosted (Qdrant/pgvector)
- **Performance**: Switch to a provider better suited for your workload
- **Vendor lock-in**: Reduce dependency on a single provider
- **Testing**: Use in-memory provider for fast tests

## The Unified API

Vectra's unified API means your code stays the same:

```ruby
# Works with ANY provider
client.upsert(index: 'docs', vectors: [...])
client.query(index: 'docs', vector: emb, top_k: 10)
client.fetch(index: 'docs', ids: ['1', '2'])
client.delete(index: 'docs', ids: ['1', '2'])
```

## Step 1: Update Client Initialization

### From Pinecone to Qdrant

**Before:**
```ruby
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'
)
```

**After:**
```ruby
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'http://localhost:6333',
  api_key: ENV['QDRANT_API_KEY']  # Optional for local
)
```

### From Qdrant to pgvector

**Before:**
```ruby
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'http://localhost:6333'
)
```

**After:**
```ruby
client = Vectra::Client.new(
  provider: :pgvector,
  connection_url: ENV['DATABASE_URL']
)
```

### From Any Provider to Memory (Testing)

```ruby
client = Vectra::Client.new(provider: :memory)
# No configuration needed - perfect for tests
```

## Step 2: Migrate Your Data

### Option 1: Export/Import Script

```ruby
# Export from source provider
source_client = Vectra::Client.new(provider: :pinecone, ...)
target_client = Vectra::Client.new(provider: :qdrant, ...)

# Fetch all vectors from source
indexes = source_client.list_indexes
indexes.each do |index_info|
  index_name = index_info[:name]
  
  # Get all IDs (you may need to query or use stats)
  stats = source_client.stats(index: index_name)
  # Note: You'll need to implement ID enumeration based on provider
  
  # Fetch and re-insert
  vectors = source_client.fetch(index: index_name, ids: all_ids)
  target_client.upsert(index: index_name, vectors: vectors.values)
end
```

### Option 2: Dual-Write Pattern

Write to both providers during migration:

```ruby
def upsert_to_both(vectors)
  source_client.upsert(index: 'docs', vectors: vectors)
  target_client.upsert(index: 'docs', vectors: vectors)
rescue StandardError => e
  # Log error, but don't fail
  Rails.logger.error("Dual-write failed: #{e.message}")
end
```

### Option 3: Background Job Migration

```ruby
class MigrateVectorsJob < ApplicationJob
  def perform(index_name, batch_size: 1000)
    source = Vectra::Client.new(provider: :pinecone, ...)
    target = Vectra::Client.new(provider: :qdrant, ...)
    
    # Get all IDs (you'll need to implement this based on your data structure)
    # Option A: If you have IDs stored elsewhere (e.g., database)
    all_ids = YourModel.pluck(:vector_id)
    
    # Option B: Query with a dummy vector to get some IDs (limited)
    # Note: This won't get ALL IDs, just a sample
    sample_results = source.query(index: index_name, vector: Array.new(1536, 0), top_k: 1000)
    all_ids = sample_results.ids
    
    # Process in batches
    all_ids.each_slice(batch_size) do |id_batch|
      vectors = source.fetch(index: index_name, ids: id_batch)
      target.upsert(index: index_name, vectors: vectors.values)
    end
  end
end
```

## Step 3: Feature Compatibility

Not all providers support all features. Check compatibility:

| Feature | Pinecone | Qdrant | Weaviate | pgvector |
|---------|----------|--------|----------|----------|
| Vector search | ✅ | ✅ | ✅ | ✅ |
| Hybrid search | ⚠️ | ✅ | ✅ | ✅ |
| Text search | ❌ | ✅ | ✅ | ✅ |
| Metadata filtering | ✅ | ✅ | ✅ | ✅ |
| Namespaces | ✅ | ✅ | ✅ | ❌ |

### Handling Missing Features

```ruby
# Check if provider supports feature
if client.provider.respond_to?(:text_search)
  results = client.text_search(index: 'docs', text: 'query')
else
  # Fallback to vector search
  embedding = generate_embedding('query')
  results = client.query(index: 'docs', vector: embedding, top_k: 10)
end

# Or use validate!
client.validate!(features: [:text_search])
```

## Step 4: Update Configuration

### Environment Variables

```ruby
# config/initializers/vectra.rb
provider = ENV.fetch('VECTRA_PROVIDER', 'qdrant').to_sym

client = Vectra::Client.new(
  provider: provider,
  **case provider
  when :pinecone
    { api_key: ENV['PINECONE_API_KEY'], environment: ENV['PINECONE_ENV'] }
  when :qdrant
    { host: ENV['QDRANT_HOST'], api_key: ENV['QDRANT_API_KEY'] }
  when :pgvector
    { connection_url: ENV['DATABASE_URL'] }
  end
)
```

### Rails config/vectra.yml

```yaml
# Development: Qdrant local
development:
  provider: qdrant
  host: http://localhost:6333
  index: documents
  dimension: 1536

# Production: Pinecone
production:
  provider: pinecone
  api_key: <%= Rails.application.credentials.pinecone_api_key %>
  environment: us-west-4
  index: documents
  dimension: 1536

# Test: Memory
test:
  provider: memory
  index: documents
  dimension: 1536
```

## Step 5: Testing the Switch

### 1. Validate Configuration

```ruby
client.validate!
client.validate!(features: [:hybrid_search]) if needed
```

### 2. Test Basic Operations

```ruby
# Test upsert
result = client.upsert(index: 'test', vectors: [test_vector])
expect(result[:upserted_count]).to eq(1)

# Test query
results = client.query(index: 'test', vector: test_vector, top_k: 1)
expect(results.size).to eq(1)

# Test fetch
vectors = client.fetch(index: 'test', ids: ['test-id'])
expect(vectors['test-id']).to be_present
```

### 3. Test Feature-Specific Code

```ruby
# If using hybrid search
if client.provider.respond_to?(:hybrid_search)
  results = client.hybrid_search(
    index: 'test',
    vector: emb,
    text: 'query',
    alpha: 0.7
  )
  expect(results.size).to be > 0
end
```

## Step 6: Zero-Downtime Migration

### Phase 1: Dual-Write

```ruby
# Write to both providers
def upsert_safe(vectors)
  old_client.upsert(index: 'docs', vectors: vectors)
  new_client.upsert(index: 'docs', vectors: vectors)
end
```

### Phase 2: Verify

```ruby
# Compare results from both providers
old_results = old_client.query(index: 'docs', vector: emb, top_k: 10)
new_results = new_client.query(index: 'docs', vector: emb, top_k: 10)

# Log differences
if old_results.ids != new_results.ids
  Rails.logger.warn("Result mismatch detected")
end
```

### Phase 3: Switch Reads

```ruby
# Feature flag
if Feature.enabled?(:new_provider)
  client = new_client
else
  client = old_client
end
```

### Phase 4: Complete Migration

```ruby
# Once verified, switch fully
client = new_client
# Stop writing to old provider
```

## Common Pitfalls

### 1. ID Format Differences

Some providers use integers, others strings. Vectra normalizes to strings:

```ruby
# Always use string IDs
client.upsert(vectors: [{ id: '1', values: [...] }])
```

### 2. Namespace Support

pgvector doesn't support namespaces. Use separate indexes instead:

```ruby
# Instead of namespaces
client.upsert(index: 'docs-tenant-1', vectors: [...])

# Or use for_tenant helper
client.for_tenant('tenant-1') do |c|
  c.upsert(index: 'docs', vectors: [...])
end
```

### 3. Filter Syntax

Filters are automatically converted, but complex filters may need adjustment:

```ruby
# Simple filters work everywhere
filter: { category: 'docs' }

# Complex filters may need provider-specific syntax
# Check provider documentation
```

## Migration Checklist

- [ ] Choose target provider based on requirements
- [ ] Update client initialization
- [ ] Migrate data (export/import or dual-write)
- [ ] Verify feature compatibility
- [ ] Update configuration (env vars, YAML)
- [ ] Test all operations
- [ ] Test feature-specific code (hybrid search, text search)
- [ ] Plan zero-downtime migration if needed
- [ ] Monitor performance after switch
- [ ] Update documentation

## Need Help?

- [Provider Selection Guide](/providers/selection/)
- [API Reference](/api/methods/)
- [GitHub Issues](https://github.com/stokry/vectra/issues)
