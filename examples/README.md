# Vectra Examples

This directory contains comprehensive examples demonstrating Vectra's capabilities.

## Prerequisites

### For Qdrant examples:
```bash
# Start Qdrant locally with Docker
docker run -p 6333:6333 qdrant/qdrant

# Or install Qdrant directly
brew install qdrant
qdrant
```

### For pgvector examples:
```bash
# Install PostgreSQL with pgvector
brew install postgresql pgvector

# Start PostgreSQL
brew services start postgresql

# Create database and enable extension
createdb vectra_demo
psql vectra_demo -c "CREATE EXTENSION vector;"
```

## Examples

### Rails Quickstart (with generator)

```bash
# Generate Vectra index for Product model
rails generate vectra:index Product embedding dimension:1536 provider:qdrant

# Run migrations (if pgvector)
rails db:migrate
```

Then in `app/models/product.rb`:

```ruby
class Product < ApplicationRecord
  include ProductVector  # generated concern with has_vector :embedding
end
```

### 1. **Comprehensive Demo** (`comprehensive_demo.rb`)

**⭐ START HERE** - Complete production-ready demonstration of all Vectra features.

```bash
bundle exec ruby examples/comprehensive_demo.rb
```

**What it demonstrates:**
- ✅ Basic CRUD operations (Create, Read, Update, Delete)
- ✅ Batch processing (50+ documents)
- ✅ **Async batch operations** (concurrent processing)
- ✅ **Streaming queries** (memory-efficient large result sets)
- ✅ Advanced queries with metadata filtering
- ✅ Update operations (metadata and vectors)
- ✅ Multiple delete strategies
- ✅ Cache performance (3-5x speedup)
- ✅ Error handling & resilience
- ✅ **Rate limiting** (proactive throttling)
- ✅ **Circuit breaker** (failover pattern)
- ✅ Multi-tenancy with namespaces
- ✅ Health monitoring & statistics
- ✅ **Structured JSON logging**
- ✅ **Audit logging** (compliance)
- ✅ **Error tracking** (Sentry, Honeybadger)

**Output preview:**
```
================================================================================
                       VECTRA COMPREHENSIVE DEMO
================================================================================

Provider: Qdrant
Host: http://localhost:6333
Index: documents
Dimension: 128

────────────────────────────────────────────────────────────────────────────────
│ 1. Basic CRUD Operations
────────────────────────────────────────────────────────────────────────────────

🏥 Checking system health...
   ✅ System healthy (3.21ms latency)

📦 Creating index 'documents'...
   ✅ Index created

📝 Inserting single document...
   ✅ Inserted 1 document

[... continues with 13 sections ...]

📊 Operations Summary:
   Total operations: 60+
   Cache hits: 2
   Errors handled: 3
   Retries: 0

🎯 Features Demonstrated:
   ✅ Basic CRUD operations
   ✅ Batch processing
   ✅ Async batch operations
   ✅ Streaming queries
   ✅ Advanced queries with filtering
   ✅ Update operations
   ✅ Delete operations
   ✅ Caching & performance
   ✅ Error handling
   ✅ Multi-tenancy (namespaces)
   ✅ Health monitoring
   ✅ Rate limiting
   ✅ Circuit breaker
   ✅ Monitoring & logging

✅ Demo completed successfully!
```

**Run with cleanup:**
```bash
bundle exec ruby examples/comprehensive_demo.rb --cleanup
```

---

### 2. **Blog Search Engine** (`blog_search_engine.rb`)

Simple semantic search engine for blog posts with caching.

```bash
bundle exec ruby examples/blog_search_engine.rb
```

**Features:**
- Blog post indexing with metadata
- Semantic search with category filtering
- Cache performance testing
- Simple embedding generation

**Best for:**
- Learning the basics
- Understanding semantic search
- Quick prototyping

---

## Running Examples

### Basic Usage

```bash
# Run with default settings (localhost:6333)
bundle exec ruby examples/comprehensive_demo.rb

# Specify custom host
bundle exec ruby examples/comprehensive_demo.rb http://your-qdrant-host:6333

# Run with cleanup
bundle exec ruby examples/comprehensive_demo.rb --cleanup
```

### Troubleshooting

**"Cannot connect to Qdrant"**
```bash
# Check if Qdrant is running
curl http://localhost:6333/health

# Start Qdrant if needed
docker run -p 6333:6333 qdrant/qdrant
```

**"Index already exists"**
```bash
# Run with cleanup flag
bundle exec ruby examples/comprehensive_demo.rb --cleanup
```

**Performance issues**
```bash
# Check Qdrant dashboard
open http://localhost:6333/dashboard
```

## Example Output Comparison

### Comprehensive Demo
- **Operations:** 60+ operations across 13 sections
- **Duration:** ~10-15 seconds
- **Documents:** 80+ indexed
- **Features shown:** ALL major features including:
  - Performance optimizations (async, streaming, caching)
  - Resilience patterns (rate limiting, circuit breaker)
  - Production monitoring (logging, audit, error tracking)

### Blog Search Engine
- **Operations:** ~10 operations
- **Duration:** ~2-3 seconds
- **Documents:** 5-8 indexed
- **Features shown:** Basic CRUD + caching

## Grafana Dashboard 📊

Create beautiful monitoring dashboards with Grafana - perfect for screenshots!

### Quick Start (5 minutes)

1. **Start Prometheus Exporter:**
   ```bash
   ruby examples/prometheus-exporter.rb
   ```

2. **Setup Grafana:**
   - Sign up at [grafana.com](https://grafana.com) (free)
   - Add Prometheus data source
   - Import `examples/grafana-dashboard.json`

3. **Take Screenshots:**
   - Wait 1-2 minutes for metrics
   - Use browser screenshot or Grafana's export feature
   - Perfect panels: Request Rate, Latency Distribution, Pie Charts

**See [GRAFANA_QUICKSTART.md](GRAFANA_QUICKSTART.md) for step-by-step guide.**

### Dashboard Features

- **12 Professional Panels:**
  - Request rate, error rate, latency metrics
  - Cache performance, connection pool status
  - Time series, pie charts, bar gauges
  - Color-coded thresholds

- **Perfect for Screenshots:**
  - Clean, modern design
  - Dark theme support
  - Multiple visualization types
  - Real-time data updates

See [grafana-setup.md](grafana-setup.md) for complete production setup.

## Next Steps

1. **Read the main README:** `../README.md`
2. **Check the documentation:** [vectra-docs.netlify.app](https://vectra-docs.netlify.app/)
3. **Explore the source code:** `../lib/vectra/`
4. **Try with different providers:** Pinecone, Weaviate, pgvector
5. **Build your own application!**

## New Features in Comprehensive Demo

The comprehensive demo now includes **4 additional sections** demonstrating production-ready features:

### Section 10: Async Batch Operations
- Concurrent batch upsert with configurable worker count
- Automatic chunking and error handling
- Performance metrics and throughput analysis

### Section 11: Streaming Large Queries
- Memory-efficient query processing
- Batch-by-batch result streaming
- Perfect for large result sets without memory overflow

### Section 12: Resilience Features
- **Rate Limiting**: Token bucket algorithm for smooth throttling
- **Circuit Breaker**: Automatic failover with state management
- Real-world resilience patterns

### Section 13: Monitoring & Logging
- **Structured JSON Logging**: Machine-readable log format
- **Audit Logging**: Compliance-ready audit trails
- **Error Tracking**: Sentry and Honeybadger integration
- Production monitoring setup

In addition to the classic API, the demo now also showcases the **chainable Query Builder** style:

```ruby
results = client
  .query("documents")
  .vector(embedding)
  .top_k(10)
  .filter(category: "ruby")
  .with_metadata
  .execute
```

## Tips for Production

### Performance
```ruby
# Use caching for frequently queried vectors
cache = Vectra::Cache.new(ttl: 600, max_size: 10000)
client = Vectra::CachedClient.new(base_client, cache: cache)

# Batch operations for efficiency
client.upsert(index: 'docs', vectors: large_batch)
```

### Error Handling
```ruby
begin
  client.query(index: 'docs', vector: embedding, top_k: 10)
rescue Vectra::NotFoundError => e
  # Handle missing index
rescue Vectra::ValidationError => e
  # Handle invalid input
rescue Vectra::ServerError => e
  # Handle server errors
end
```

### Monitoring
```ruby
# Regular health checks
health = client.health_check(include_stats: true)
puts "Latency: #{health.latency_ms}ms"
puts "Vector count: #{health.stats[:vector_count]}"
```

### Multi-tenancy
```ruby
# Isolate tenant data with namespaces
client.upsert(
  index: 'shared_index',
  vectors: tenant_vectors,
  namespace: "tenant-#{tenant_id}"
)

# Query only tenant's data
results = client.query(
  index: 'shared_index',
  vector: query_vec,
  namespace: "tenant-#{tenant_id}"
)
```

## Contributing

Found an issue or want to add a new example? [Open an issue](https://github.com/stokry/vectra/issues) or submit a PR!

## License

MIT - See [LICENSE](../LICENSE)
