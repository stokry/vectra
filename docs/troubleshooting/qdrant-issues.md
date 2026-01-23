---
layout: page
title: Qdrant Issues
permalink: /troubleshooting/qdrant-issues/
---

# Qdrant-Specific Issues

Common issues when using Qdrant with Vectra.

## Connection Issues

### `ConnectionError: Failed to connect`

**Cause:** Qdrant server not running or wrong host URL.

**Solution:**
```ruby
# Local Qdrant
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'http://localhost:6333'  # Default Qdrant port
)

# Cloud Qdrant
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'https://your-cluster.qdrant.io',
  api_key: ENV['QDRANT_API_KEY']
)

# Test connection
if client.healthy?
  puts "Connected"
else
  puts "Check if Qdrant is running: docker ps | grep qdrant"
end
```

## Collection vs Index

### Collection Not Found

**Cause:** Qdrant uses "collections" but Vectra calls them "indexes" for consistency.

**Solution:**
```ruby
# In Vectra, use 'index' parameter (maps to Qdrant collection)
client.upsert(index: 'my-collection', vectors: [...])

# List collections (shown as indexes)
collections = client.list_indexes
```

## Filter Syntax

### Complex Filters Not Working

**Cause:** Qdrant has complex filter syntax; Vectra simplifies it but may need adjustment.

**Solution:**
```ruby
# Simple filters (auto-converted)
filter: { category: 'docs' }  # ✅ Works

# Range filters
filter: { price: { gte: 10, lte: 100 } }  # ✅ Works

# Complex filters (may need Qdrant syntax)
filter: {
  must: [
    { key: 'category', match: { value: 'docs' } },
    { key: 'price', range: { gte: 10 } }
  ]
}  # ✅ Passed through as-is
```

## Namespace Implementation

### Namespace Not Isolating Data

**Cause:** Qdrant doesn't have native namespaces; Vectra uses metadata field `_namespace`.

**Solution:**
```ruby
# Vectra handles namespace via metadata
client.upsert(
  index: 'docs',
  vectors: [...],
  namespace: 'tenant-1'
)

# Query from namespace
results = client.query(
  index: 'docs',
  vector: emb,
  namespace: 'tenant-1'  # Automatically filtered
)
```

**Note:** Namespaces are implemented via metadata filtering, not native Qdrant feature.

## Hybrid Search

### Hybrid Search Performance

**Cause:** Qdrant hybrid search uses prefetch + rescore which may be slower.

**Solution:**
```ruby
# Hybrid search is supported
results = client.hybrid_search(
  index: 'docs',
  vector: emb,
  text: 'query',
  alpha: 0.7
)

# For better performance, tune alpha
# alpha closer to 1.0 = more vector, less text
```

## Text Search (BM25)

### Text Search Not Working

**Cause:** Collection must have text fields indexed for BM25.

**Solution:**
```ruby
# Text search requires text fields in metadata
client.upsert(
  index: 'docs',
  vectors: [{
    id: 'doc-1',
    values: embedding,
    metadata: {
      title: 'Document Title',  # Text field
      content: 'Document content...'  # Text field
    }
  }]
)

# Then search
results = client.text_search(
  index: 'docs',
  text: 'Document',
  top_k: 10
)
```

## ID Type Issues

### Integer vs String IDs

**Cause:** Qdrant supports both integer and string IDs; Vectra uses strings.

**Solution:**
```ruby
# Always use string IDs for consistency
client.upsert(vectors: [
  { id: '1', values: [...] },  # ✅
  { id: '2', values: [...] }
])

# Vectra converts internally if needed
```

## Local vs Cloud

### Local Qdrant Works, Cloud Doesn't

**Cause:** Cloud Qdrant requires API key and different host format.

**Solution:**
```ruby
# Local (no API key needed)
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'http://localhost:6333'
)

# Cloud (API key required)
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'https://your-cluster.qdrant.io',
  api_key: ENV['QDRANT_API_KEY']
)
```

## Getting Help

- [Qdrant Documentation](https://qdrant.tech/documentation/)
- [Common Errors](/troubleshooting/common-errors/)
- [GitHub Issues](https://github.com/stokry/vectra/issues)
