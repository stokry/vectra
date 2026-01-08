# 🚀 NEW FEATURES in v0.2.0

## Overview

Version 0.2.0 adds **enterprise-grade features** for production use:

- 📊 **Instrumentation & Monitoring** - New Relic, Datadog, custom handlers
- 🎨 **Rails Generator** - `rails g vectra:install`
- 💎 **ActiveRecord Integration** - `has_vector` DSL for seamless Rails integration
- 🔄 **Automatic Retry Logic** - Resilience for transient database errors
- ⚡ **Performance Benchmarks** - Measure and optimize your setup

---

## 📊 Instrumentation & Monitoring

Track all vector operations in production.

### Quick Start

```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.instrumentation = true
end

# Custom handler
Vectra.on_operation do |event|
  Rails.logger.info "Vectra: #{event.operation} took #{event.duration}ms"

  # Send to monitoring
  StatsD.timing("vectra.#{event.operation}", event.duration)
  StatsD.increment("vectra.#{event.success? ? 'success' : 'error'}")
end
```

### New Relic Integration

```ruby
require 'vectra/instrumentation/new_relic'

Vectra.configure { |c| c.instrumentation = true }
Vectra::Instrumentation::NewRelic.setup!
```

Automatically tracks:
- `Custom/Vectra/pgvector/query/duration`
- `Custom/Vectra/pgvector/upsert/success`
- And more...

### Datadog Integration

```ruby
require 'vectra/instrumentation/datadog'

Vectra.configure { |c| c.instrumentation = true }
Vectra::Instrumentation::Datadog.setup!(
  host: ENV['DD_AGENT_HOST'],
  port: 8125
)
```

Metrics:
- `vectra.operation.duration` (timing)
- `vectra.operation.count` (counter)
- `vectra.operation.error` (counter)

### Event API

```ruby
Vectra.on_operation do |event|
  event.operation    # :query, :upsert, :fetch, :update, :delete
  event.provider     # :pgvector, :pinecone
  event.index        # 'documents'
  event.duration     # 123.45 (milliseconds)
  event.metadata     # { vector_count: 10, top_k: 5, ... }
  event.success?     # true/false
  event.error        # Exception or nil
end
```

---

## 🎨 Rails Generator

One command to set up Vectra in Rails.

### Usage

```bash
rails generate vectra:install --provider=pgvector --instrumentation=true
```

### What it creates:

1. **config/initializers/vectra.rb** - Configuration with smart defaults
2. **db/migrate/XXX_enable_pgvector_extension.rb** - Enables pgvector (if using PostgreSQL)
3. **Setup instructions** - Provider-specific next steps

### Options

```bash
--provider=NAME        # pinecone, pgvector, qdrant, weaviate (default: pgvector)
--database-url=URL     # PostgreSQL connection URL (for pgvector)
--api-key=KEY          # API key for the provider
--instrumentation      # Enable instrumentation
```

### Example

```bash
rails g vectra:install --provider=pgvector --instrumentation=true
rails db:migrate

# Creates initializer with:
# - Connection pooling (10 connections)
# - Batch operations (100 vectors/batch)
# - Instrumentation enabled
# - Logging to Rails.logger
```

---

## 💎 ActiveRecord Integration

Add vector search to any Rails model.

### Quick Start

```ruby
class Document < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding,
             dimension: 384,
             provider: :pgvector,
             index: 'documents',
             auto_index: true,
             metadata_fields: [:title, :category, :status]

  # Generate embeddings (use OpenAI, Cohere, etc.)
  before_validation :generate_embedding, if: :content_changed?

  def generate_embedding
    self.embedding = OpenAI::Client.new.embeddings(
      parameters: { model: 'text-embedding-3-small', input: content }
    ).dig('data', 0, 'embedding')
  end
end
```

### Usage

```ruby
# Create (automatically indexed)
doc = Document.create!(
  title: 'Getting Started',
  content: 'Learn how to...',
  category: 'tutorial'
)

# Vector search
query_vector = generate_embedding('how to get started')
results = Document.vector_search(query_vector, limit: 10)

results.each do |doc|
  puts "#{doc.title} - Score: #{doc.vector_score}"
end

# Find similar documents
similar = doc.similar(limit: 5)

# Search with filters
results = Document.vector_search(
  query_vector,
  limit: 10,
  filter: { category: 'tutorial', status: 'published' }
)

# Manual control
doc.index_vector!   # Force indexing
doc.delete_vector!  # Remove from index
```

### Features

- ✅ **Auto-indexing** - On create/update
- ✅ **Auto-deletion** - On destroy
- ✅ **Metadata sync** - Specified fields included in vector metadata
- ✅ **AR object loading** - Search returns ActiveRecord objects, not just vectors
- ✅ **Score access** - `doc.vector_score` available on results
- ✅ **Background jobs** - Disable auto-index for async processing

### Background Indexing

```ruby
class Document < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding, dimension: 384, auto_index: false

  after_commit :index_async, on: [:create, :update]

  def index_async
    IndexVectorJob.perform_later(id)
  end
end

# Job
class IndexVectorJob < ApplicationJob
  def perform(document_id)
    doc = Document.find(document_id)
    doc.index_vector!
  end
end
```

---

## 🔄 Automatic Retry Logic

Resilience for transient database errors.

### What it does

Automatically retries operations on:
- `PG::ConnectionBad`
- `PG::UnableToSend`
- `PG::TooManyConnections`
- `PG::SerializationFailure`
- `PG::DeadlockDetected`
- `ConnectionPool::TimeoutError`
- Any error with "timeout" or "connection" in message

### Configuration

```ruby
Vectra.configure do |config|
  config.max_retries = 3      # Default: 3
  config.retry_delay = 1.0    # Initial delay: 1 second
end
```

### How it works

- **Exponential backoff**: 1s, 2s, 4s, 8s, ...
- **Jitter**: ±25% randomness to prevent thundering herd
- **Max delay**: Capped at 30 seconds
- **Logging**: Each retry logged with delay and reason

### Already integrated

Retry logic is automatically used in:
- pgvector `execute()` method
- All database operations

No code changes needed - it just works!

---

## ⚡ Performance Benchmarks

Measure and optimize your setup.

### Run benchmarks

```bash
# Batch operations
DATABASE_URL=postgres://localhost/vectra_bench \
  ruby benchmarks/batch_operations_benchmark.rb

# Connection pooling
DATABASE_URL=postgres://localhost/vectra_bench \
  ruby benchmarks/connection_pooling_benchmark.rb
```

### What they measure

**Batch Operations:**
- Vector counts: 100, 500, 1K, 5K, 10K
- Batch sizes: 50, 100, 250, 500
- Metrics: avg time, vectors/sec, batch count

**Connection Pooling:**
- Pool sizes: 5, 10, 20
- Thread counts: 1, 2, 5, 10, 20
- Metrics: total time, ops/sec, pool availability

### Example output

```
1000 vectors:
  Batch size  50: 2.134s avg (468 vectors/sec, 20 batches)
  Batch size 100: 1.892s avg (529 vectors/sec, 10 batches)
  Batch size 250: 1.645s avg (608 vectors/sec, 4 batches)
  Batch size 500: 1.523s avg (657 vectors/sec, 2 batches)

Pool Size: 10
   1 threads: 5.21s total (9.6 ops/sec) Pool: 9/10 available
   5 threads: 5.34s total (46.8 ops/sec) Pool: 5/10 available
  10 threads: 5.67s total (88.2 ops/sec) Pool: 0/10 available
```

### Recommendations

Based on benchmarks:
- **Batch size**: 250-500 for best performance
- **Pool size**: Match your app server thread count
- **Monitoring**: Use instrumentation to track in production

---

## 📚 Documentation

New comprehensive guides:

- **USAGE_EXAMPLES.md** - 10 practical examples
  - E-commerce semantic search
  - RAG chatbot
  - Duplicate detection
  - Rails integration
  - Performance tips

- **IMPLEMENTATION_GUIDE.md** - Developer guide
  - Feature implementation
  - Testing strategies
  - Customization examples
  - Troubleshooting

---

## 🚀 Migration Guide

### From v0.1.x to v0.2.0

**No breaking changes!** v0.2.0 is fully backward compatible.

### New configuration options

```ruby
Vectra.configure do |config|
  # Existing options still work
  config.provider = :pgvector
  config.host = 'postgres://...'

  # NEW: Instrumentation (optional)
  config.instrumentation = false  # default

  # NEW: Already had these, now documented
  config.pool_size = 5           # Connection pool size
  config.pool_timeout = 5        # Seconds to wait for connection
  config.batch_size = 100        # Vectors per batch
  config.max_retries = 3         # Retry attempts
  config.retry_delay = 1         # Initial retry delay
end
```

### Enabling new features

```ruby
# 1. Enable instrumentation
Vectra.configure { |c| c.instrumentation = true }

# 2. Add handler (optional)
Vectra.on_operation { |event| puts event.operation }

# 3. Use ActiveRecord integration (opt-in)
class Document < ApplicationRecord
  include Vectra::ActiveRecord
  has_vector :embedding, dimension: 384
end
```

### No action required

These features work automatically:
- ✅ Retry logic (already integrated)
- ✅ Performance improvements (transparent)

---

## 📊 Performance Improvements

### Before v0.2.0

```ruby
# 10,000 individual operations
10_000.times { client.upsert(index: 'docs', vectors: [vec]) }
# ~50 seconds
```

### After v0.2.0

```ruby
# Batch operations (automatic)
client.upsert(index: 'docs', vectors: 10_000_vectors)
# ~5 seconds (10x faster!)
```

### Connection Pooling

```ruby
# Before: New connection per request
# After: Reuse from pool (5-10x faster in multi-threaded apps)

Vectra.configure do |config|
  config.pool_size = 20  # Match your app threads
end
```

---

## 🎯 Next Steps

1. **Update your gem:**
   ```bash
   bundle update vectra
   ```

2. **Enable instrumentation:**
   ```ruby
   Vectra.configure { |c| c.instrumentation = true }
   ```

3. **Try ActiveRecord integration:**
   ```ruby
   rails g vectra:install --provider=pgvector
   ```

4. **Run benchmarks:**
   ```bash
   ruby benchmarks/batch_operations_benchmark.rb
   ```

5. **Read examples:**
   - See USAGE_EXAMPLES.md for 10 practical examples
   - See IMPLEMENTATION_GUIDE.md for detailed docs

---

## 🤝 Contributing

We welcome contributions! See:
- CONTRIBUTING.md - Contribution guide
- IMPLEMENTATION_GUIDE.md - Feature implementation guide

---

## 📝 Changelog

See CHANGELOG.md for complete version history.

---

## ❓ Questions?

- GitHub Issues: https://github.com/stokry/vectra/issues
- Documentation: See README.md, USAGE_EXAMPLES.md
- Examples: See examples/ directory
