# Vectra

[![Gem Version](https://badge.fury.io/rb/vectra-client.svg)](https://rubygems.org/gems/vectra-client)
[![CI](https://github.com/stokry/vectra/actions/workflows/ci.yml/badge.svg)](https://github.com/stokry/vectra/actions)
[![codecov](https://codecov.io/gh/stokry/vectra/branch/main/graph/badge.svg)](https://codecov.io/gh/stokry/vectra)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**A unified Ruby client for vector databases.** Write once, switch providers seamlessly.

📖 **Documentation:** [vectra-docs.netlify.app](https://vectra-docs.netlify.app/)

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

# Search
results = client.query(vector: [0.1, 0.2, 0.3], top_k: 5)
results.each { |match| puts "#{match.id}: #{match.score}" }

# Delete
client.delete(ids: ['doc-1', 'doc-2'])
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

## Features

- **Provider Agnostic** - Switch providers with one line change
- **Production Ready** - Ruby 3.2+, 95%+ test coverage
- **Resilient** - Retry logic with exponential backoff
- **Observable** - Datadog & New Relic instrumentation
- **Rails Ready** - ActiveRecord integration with `has_vector` DSL

## Rails Integration

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
