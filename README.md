# Vectra client

<p align="center">
  <img src="docs/assets/readme-new.png" alt="Vectra – Unified Ruby client for vector databases" width="340">
</p>

<p align="center">
  <a href="https://rubygems.org/gems/vectra-client">
    <img src="https://badge.fury.io/rb/vectra-client.svg" alt="Gem Version">
  </a>
  <a href="https://github.com/stokry/vectra/actions">
    <img src="https://github.com/stokry/vectra/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
  <a href="https://codecov.io/gh/stokry/vectra">
    <img src="https://codecov.io/gh/stokry/vectra/branch/main/graph/badge.svg" alt="codecov">
  </a>
  <a href="https://opensource.org/licenses/MIT">
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT License">
  </a>
</p>

<p align="center">
  <strong>A unified Ruby client for vector databases.</strong><br>
  Write once, switch providers seamlessly.
</p>

<p align="center">
  📖 <strong>Documentation:</strong> <a href="https://vectra-docs.netlify.app/">vectra-docs.netlify.app</a>
</p>

## Supported Providers

| Provider | Type | Status |
|----------|------|--------|
| **Pinecone** | Managed Cloud | ✅ Supported |
| **Qdrant** | Open Source | ✅ Supported |
| **Weaviate** | Open Source | ✅ Supported |
| **pgvector** | PostgreSQL | ✅ Supported |
| **Memory** | In-Memory | ✅ Testing only |

## Installation

```ruby
gem 'vectra-client'
```

```bash
bundle install
```

## Quick Start

```ruby
require 'vectra'

# Initialize client (works with any provider)
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'
)

# Upsert vectors
client.upsert(
  vectors: [
    { id: 'doc-1', values: [0.1, 0.2, 0.3], metadata: { title: 'Hello' } },
    { id: 'doc-2', values: [0.4, 0.5, 0.6], metadata: { title: 'World' } }
  ]
)

# Search (classic API)
results = client.query(vector: [0.1, 0.2, 0.3], top_k: 5)
results.each { |match| puts "#{match.id}: #{match.score}" }

# Search (chainable Query Builder)
results = client
  .query('docs')
  .vector([0.1, 0.2, 0.3])
  .top_k(5)
  .with_metadata
  .execute

results.each do |match|
  puts "#{match.id}: #{match.score}"
end

# Normalize embeddings (for better cosine similarity)
embedding = openai_response['data'][0]['embedding']
normalized = Vectra::Vector.normalize(embedding)
client.upsert(vectors: [{ id: 'doc-1', values: normalized }])

# Delete
client.delete(ids: ['doc-1', 'doc-2'])

# Health check
if client.healthy?
  puts "Connection is healthy"
end

# Ping with latency
status = client.ping
puts "Provider: #{status[:provider]}, Latency: #{status[:latency_ms]}ms"

# Hybrid search (semantic + keyword)
# Supported by: Qdrant, Weaviate, Pinecone, pgvector
results = client.hybrid_search(
  index: 'docs',
  vector: embedding,
  text: 'ruby programming',
  alpha: 0.7  # 70% semantic, 30% keyword
)
```

## Provider Examples

```ruby
# Pinecone
client = Vectra.pinecone(api_key: ENV['PINECONE_API_KEY'], environment: 'us-west-4')

# Qdrant (local)
client = Vectra.qdrant(host: 'http://localhost:6333')

# Qdrant (cloud)
client = Vectra.qdrant(host: 'https://your-cluster.qdrant.io', api_key: ENV['QDRANT_API_KEY'])

# Weaviate
client = Vectra.weaviate(
  api_key: ENV['WEAVIATE_API_KEY'],
  host: 'https://your-weaviate-instance'
)

# pgvector (PostgreSQL)
client = Vectra.pgvector(connection_url: 'postgres://user:pass@localhost/mydb')

# Memory (in-memory, testing only)
client = Vectra.memory
```

## Architecture Overview

```mermaid
graph TB
    A[Vectra Client] --> B[Unified API]
    B --> C[Pinecone]
    B --> D[Qdrant]
    B --> E[Weaviate]
    B --> F[pgvector]
    B --> G[Memory]
    
    H[Production Patterns] --> I[Circuit Breaker]
    H --> J[Rate Limiter]
    H --> K[Retry Logic]
    H --> L[Instrumentation]
    
    A --> H
    
    style A fill:#05df72
    style B fill:#2ee889
    style H fill:#04b85e
```

## Features

- **🔌 Provider Agnostic** - Switch between 5 providers with one line change
- **🚀 Production Ready** - Ruby 3.2+, 95%+ test coverage, enterprise patterns
- **🛡️ Resilient** - Circuit breaker, rate limiter, retry logic with exponential backoff
- **📈 Observable** - Grafana dashboards, Prometheus metrics, 4 instrumentation backends
- **🏗️ Rails Ready** - ActiveRecord integration with `has_vector` DSL
- **🔍 Hybrid Search** - Semantic + keyword search across 4 providers
- **🧪 Testing** - Built-in mock provider for easy testing
- **⚡ Performance** - Connection pooling, caching, async batch operations

## 📊 Why Vectra?

| What You Get | Vectra | Others |
|--------------|--------|--------|
| **Providers** | 5 unified | 1 each |
| **Production Patterns** | ✅ 7 built-in | ❌ Manual |
| **Testing** | ✅ Mock provider | ❌ External DB |
| **Rails** | ✅ `has_vector` DSL | ⚠️ Manual |
| **Observability** | ✅ 4 backends | ❌ DIY |

[→ See full comparison](https://vectra-docs.netlify.app)

## Rails Integration

### Quick Start

```ruby
class Document < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding,
    provider: :qdrant,
    index: 'documents',
    dimension: 1536
end

# Auto-indexes on save
doc = Document.create!(title: 'Hello', embedding: [0.1, 0.2, ...])

# Search
Document.vector_search(embedding: query_vector, limit: 10)
```

### Rails Generator: vectra:index

Generate everything you need for a model with a single command:

```bash
rails generate vectra:index Product embedding dimension:1536 provider:qdrant
```

This will:

- **Create a pgvector migration** (only when `provider=pgvector`) adding `embedding` column
- **Generate a model concern** (`ProductVector`) with `has_vector :embedding`
- **Update the model** to include `ProductVector`
- **Append to `config/vectra.yml`** with index metadata (no API keys)

### Complete Rails Guide

For a complete step-by-step guide including:
- Setting up embeddings (OpenAI, Cohere)
- Processing 1000+ products
- Background jobs
- Hybrid search
- Performance optimization

👉 **[Read the complete Rails Integration Guide](https://vectra-docs.netlify.app/guides/rails-integration/)**

### Recipes & Patterns

Real-world patterns for common use cases:

- **E-Commerce Search** - Semantic product search with filters
- **Blog Hybrid Search** - Combine semantic + keyword matching
- **Multi-Tenant SaaS** - Namespace isolation per tenant
- **RAG Chatbot** - Context retrieval for LLMs
- **Zero-Downtime Migration** - Switch providers safely
- **Recommendation Engine** - Find similar items

👉 **[Browse all Recipes & Patterns](https://vectra-docs.netlify.app/guides/recipes/)**

## Production Patterns

Vectra includes 7 production-ready patterns out of the box:

- **Circuit Breaker** - Automatic failover when providers are down
- **Rate Limiter** - Token bucket algorithm to prevent API throttling
- **Retry Logic** - Exponential backoff with jitter
- **Connection Pooling** - Efficient connection management (pgvector)
- **Caching** - LRU cache with TTL for frequently queried vectors
- **Health Checks** - `healthy?`, `ping`, and `health_check` methods
- **Instrumentation** - Datadog, New Relic, Sentry, Honeybadger support

## Development

```bash
git clone https://github.com/stokry/vectra.git
cd vectra
bundle install
bundle exec rspec
bundle exec rubocop
```

## Contributing

Bug reports and pull requests welcome at [github.com/stokry/vectra](https://github.com/stokry/vectra).

## License

MIT License - see [LICENSE](LICENSE) file.
