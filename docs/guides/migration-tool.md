---
layout: page
title: Migration Tool
permalink: /guides/migration-tool/
---

# Migration Tool

The `Vectra::Migration` tool provides utilities for copying vectors between providers, enabling zero-downtime migrations and provider switching.

---

## Overview

The migration tool uses existing Vectra features:
- **Streaming** to fetch all vectors from source
- **Batch operations** (`Batch.upsert_async`) to efficiently write to target
- **Progress tracking** for monitoring large migrations

**Supported scenarios:**
- Memory → Qdrant (testing to production)
- Pinecone → Qdrant (vendor migration)
- Qdrant → pgvector (self-hosted migration)
- Any provider → Any provider

---

## Basic Usage

### Simple Migration

```ruby
require 'vectra'

# Setup clients
source_client = Vectra::Client.new(provider: :memory)
target_client = Vectra::Client.new(
  provider: :qdrant,
  host: "http://localhost:6333"
)

# Create migration tool
migration = Vectra::Migration.new(source_client, target_client)

# Migrate vectors
result = migration.migrate(
  source_index: "source-index",
  target_index: "target-index"
)

puts "Migrated #{result[:migrated_count]} vectors"
puts "Batches: #{result[:batches]}"
puts "Errors: #{result[:errors].size}" if result[:errors].any?
```

### With Progress Tracking

```ruby
result = migration.migrate(
  source_index: "products",
  target_index: "products",
  on_progress: ->(stats) {
    percentage = stats[:percentage]
    migrated = stats[:migrated]
    total = stats[:total]
    batches = stats[:batches_processed]
    total_batches = stats[:total_batches]
    
    puts "[#{percentage}%] Migrated #{migrated}/#{total} vectors " \
         "(batch #{batches}/#{total_batches})"
  }
)
```

### With Custom Batch Sizes

```ruby
# Fetch 500 vectors at a time, upsert in chunks of 50
result = migration.migrate(
  source_index: "large-index",
  target_index: "large-index",
  batch_size: 500,    # Vectors per fetch batch
  chunk_size: 50      # Vectors per upsert chunk
)
```

---

## Namespace Migration

Migrate vectors between different namespaces:

```ruby
result = migration.migrate(
  source_index: "products",
  target_index: "products",
  source_namespace: "tenant-1",
  target_namespace: "tenant-2"
)
```

---

## Verification

After migration, verify that all vectors were copied:

```ruby
verification = migration.verify(
  source_index: "old-index",
  target_index: "new-index"
)

if verification[:match]
  puts "✅ Migration verified: #{verification[:source_count]} vectors"
else
  puts "❌ Mismatch detected!"
  puts "  Source: #{verification[:source_count]} vectors"
  puts "  Target: #{verification[:target_count]} vectors"
end
```

**Verification with namespaces:**

```ruby
verification = migration.verify(
  source_index: "products",
  target_index: "products",
  source_namespace: "tenant-1",
  target_namespace: "tenant-2"
)
```

---

## Real-World Examples

### Example 1: Testing to Production

```ruby
# Development: Memory provider
dev_client = Vectra::Client.new(provider: :memory)

# Production: Qdrant
prod_client = Vectra::Client.new(
  provider: :qdrant,
  host: ENV['QDRANT_HOST'],
  api_key: ENV['QDRANT_API_KEY']
)

migration = Vectra::Migration.new(dev_client, prod_client)

# Migrate test data to production
result = migration.migrate(
  source_index: "test-products",
  target_index: "products",
  on_progress: ->(stats) {
    Rails.logger.info("Migration progress: #{stats[:percentage]}%")
  }
)

if result[:errors].any?
  Rails.logger.error("Migration errors: #{result[:errors]}")
else
  Rails.logger.info("✅ Migrated #{result[:migrated_count]} vectors")
end
```

### Example 2: Provider Migration (Pinecone → Qdrant)

```ruby
# Old provider: Pinecone
pinecone_client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'
)

# New provider: Qdrant
qdrant_client = Vectra::Client.new(
  provider: :qdrant,
  host: ENV['QDRANT_HOST'],
  api_key: ENV['QDRANT_API_KEY']
)

migration = Vectra::Migration.new(pinecone_client, qdrant_client)

# Migrate all indexes
indexes = pinecone_client.list_indexes.map { |idx| idx[:name] }

indexes.each do |index_name|
  puts "Migrating #{index_name}..."
  
  result = migration.migrate(
    source_index: index_name,
    target_index: index_name,
    on_progress: ->(stats) {
      print "\r#{stats[:percentage]}% (#{stats[:migrated]}/#{stats[:total]})"
    }
  )
  
  puts "\n✅ #{index_name}: #{result[:migrated_count]} vectors"
  
  # Verify
  verification = migration.verify(
    source_index: index_name,
    target_index: index_name
  )
  
  unless verification[:match]
    puts "⚠️  Warning: Count mismatch for #{index_name}"
  end
end
```

### Example 3: Zero-Downtime Migration

```ruby
# Strategy: Dual-write during migration, then switch

# Source: Old provider
old_client = Vectra::Client.new(provider: :pinecone, ...)

# Target: New provider
new_client = Vectra::Client.new(provider: :qdrant, ...)

migration = Vectra::Migration.new(old_client, new_client)

# Step 1: Migrate existing data
puts "Migrating existing vectors..."
result = migration.migrate(
  source_index: "products",
  target_index: "products",
  on_progress: ->(stats) {
    puts "Progress: #{stats[:percentage]}%"
  }
)

# Step 2: Verify
verification = migration.verify(
  source_index: "products",
  target_index: "products"
)

unless verification[:match]
  raise "Migration verification failed!"
end

# Step 3: Enable dual-write (in your application code)
# - Write to both old and new providers
# - Read from old provider (or both for comparison)

# Step 4: After verification period, switch to new provider
# - Update application config to use new_client
# - Remove dual-write logic
```

---

## Error Handling

The migration tool continues processing even if individual batches fail:

```ruby
result = migration.migrate(
  source_index: "products",
  target_index: "products"
)

if result[:errors].any?
  puts "⚠️  Migration completed with #{result[:errors].size} errors:"
  result[:errors].each do |error|
    puts "  - #{error.class}: #{error.message}"
  end
  
  # Retry failed batches or handle manually
else
  puts "✅ Migration completed successfully"
end
```

---

## Performance Tips

1. **Batch Size**: Larger `batch_size` reduces fetch overhead but uses more memory
2. **Chunk Size**: Smaller `chunk_size` provides better progress granularity
3. **Concurrency**: Migration uses `Batch.upsert_async` which handles concurrency automatically
4. **Progress Callbacks**: Use lightweight callbacks to avoid slowing down migration

**Recommended settings:**

```ruby
# For small indexes (< 10K vectors)
migration.migrate(
  source_index: "small",
  target_index: "small",
  batch_size: 1000,
  chunk_size: 100
)

# For large indexes (> 100K vectors)
migration.migrate(
  source_index: "large",
  target_index: "large",
  batch_size: 5000,   # Larger batches
  chunk_size: 500     # Larger chunks
)
```

---

## Limitations

1. **Provider-Specific Features**: Some provider-specific features may not migrate (e.g., custom indexes, special metadata formats)
2. **Large Indexes**: Very large indexes (> 1M vectors) may take significant time
3. **Memory Usage**: Migration loads batches into memory; monitor memory usage for very large migrations
4. **Network**: Migration performance depends on network speed between source and target

---

## See Also

- [API Methods](/api/methods/) - Complete API reference
- [Switching Providers](/guides/migrations/switching-providers/) - Provider migration guide
- [Batch Operations](/api/methods/#batch-operations) - Understanding batch processing
- [Recipes & Patterns](/guides/recipes/) - Real-world examples
