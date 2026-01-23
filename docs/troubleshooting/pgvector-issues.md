---
layout: page
title: pgvector Issues
permalink: /troubleshooting/pgvector-issues/
---

# pgvector-Specific Issues

Common issues when using PostgreSQL with pgvector extension via Vectra.

## Extension Not Installed

### `PG::UndefinedFunction: function vector() does not exist`

**Cause:** pgvector extension not installed in database.

**Solution:**
```sql
-- Install extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Verify
SELECT * FROM pg_extension WHERE extname = 'vector';
```

Or use Rails migration:
```ruby
class EnablePgvectorExtension < ActiveRecord::Migration[7.0]
  def change
    enable_extension 'vector'
  end
end
```

## Connection Issues

### `PG::ConnectionBad: could not connect to server`

**Cause:** Database connection string incorrect or database not running.

**Solution:**
```ruby
# Check connection URL
client = Vectra::Client.new(
  provider: :pgvector,
  connection_url: ENV['DATABASE_URL']  # postgres://user:pass@host/db
)

# Or use separate params (if supported)
client = Vectra.pgvector(
  connection_url: 'postgres://localhost/mydb'
)

# Test connection
if client.healthy?
  puts "Connected"
else
  puts "Check database is running and connection string is correct"
end
```

## Table Creation

### `NotFoundError: Index 'xyz' not found`

**Cause:** Table doesn't exist. Vectra auto-creates tables, but may fail.

**Solution:**
```ruby
# Create index explicitly
client.create_index(
  name: 'documents',
  dimension: 1536,
  metric: 'cosine'
)

# Or create manually
# Vectra creates tables with structure:
# - id TEXT PRIMARY KEY
# - embedding vector(dimension)
# - metadata JSONB
# - namespace TEXT
# - created_at TIMESTAMP
```

## Namespace Limitation

### Namespaces Not Supported

**Cause:** pgvector provider uses a `namespace` column but doesn't provide true namespace isolation like other providers.

**Solution:**
```ruby
# Use separate indexes (tables) for different tenants
client.upsert(index: 'docs-tenant-1', vectors: [...])

# Or use for_tenant helper
client.for_tenant('tenant-1') do |c|
  c.upsert(index: 'docs', vectors: [...])
  # Namespace stored in metadata/column but not isolated
end
```

**Note:** pgvector doesn't have native namespace support. Use separate tables/indexes for true isolation.

## Index Performance

### Slow Queries

**Cause:** Missing or incorrect vector index.

**Solution:**
```sql
-- Check if index exists
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'your_index_name';

-- Create index if missing
CREATE INDEX ON your_index_name
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);  -- Adjust based on data size
```

Vectra should create indexes automatically, but you may need to tune `lists` parameter.

## Dimension Mismatch

### `ERROR: vector dimension mismatch`

**Cause:** Vector dimension doesn't match table column dimension.

**Solution:**
```ruby
# Check table dimension
index_info = client.describe_index(index: 'docs')
required_dim = index_info[:dimension]

# Ensure vectors match
vectors = [
  { id: '1', values: Array.new(required_dim, 0.1) }
]
```

## Full-Text Search

### Text Search Not Working

**Cause:** Text column not specified or not indexed.

**Solution:**
```ruby
# Specify text column (default: 'content')
results = client.text_search(
  index: 'docs',
  text: 'query',
  top_k: 10,
  text_column: 'content'  # Column with text data
)

# Ensure metadata has text field
client.upsert(
  index: 'docs',
  vectors: [{
    id: 'doc-1',
    values: embedding,
    metadata: {
      content: 'Document text here...'  # Used for text search
    }
  }]
)
```

## JSONB Metadata

### Metadata Queries Not Working

**Cause:** JSONB queries need proper syntax.

**Solution:**
```ruby
# Simple filters work
filter: { category: 'docs' }  # ✅

# Nested JSONB
filter: { 'author.name': 'John' }  # ✅ Auto-converted

# Complex JSONB queries may need raw SQL
# Vectra handles most cases automatically
```

## Connection Pooling

### Connection Pool Exhausted

**Cause:** Too many concurrent connections.

**Solution:**
```ruby
# Vectra manages connections, but you can configure pool
Vectra.configure do |config|
  config.pool_size = 10  # Adjust based on needs
  config.pool_timeout = 5
end
```

## Getting Help

- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [Common Errors](/troubleshooting/common-errors/)
- [GitHub Issues](https://github.com/stokry/vectra/issues)
