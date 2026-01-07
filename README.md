# Vectra

[![Gem Version](https://badge.fury.io/rb/vectra.svg)](https://badge.fury.io/rb/vectra)
[![CI](https://github.com/stokry/vectra/actions/workflows/ci.yml/badge.svg)](https://github.com/stokry/vectra/actions)
[![codecov](https://codecov.io/gh/stokry/vectra/branch/main/graph/badge.svg)](https://codecov.io/gh/stokry/vectra)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.0-4baaaa.svg)](CODE_OF_CONDUCT.md)

**Vectra** is a unified Ruby client for vector databases. Write once, switch providers seamlessly.

## Features

- 🔌 **Unified API** - One interface for multiple vector databases
- 🚀 **Modern Ruby** - Built for Ruby 3.2+ with modern patterns
- 🔄 **Automatic Retries** - Built-in retry logic with exponential backoff
- 📊 **Rich Results** - Enumerable query results with filtering capabilities
- 🛡️ **Type Safety** - Comprehensive validation and meaningful errors
- 📝 **Well Documented** - Extensive YARD documentation

## Supported Providers

| Provider | Status | Version |
|----------|--------|---------|
| [Pinecone](https://pinecone.io) | ✅ Fully Supported | v0.1.0 |
| [PostgreSQL + pgvector](https://github.com/pgvector/pgvector) | ✅ Fully Supported | v0.1.1 |
| [Qdrant](https://qdrant.tech) | 🚧 Planned | v0.2.0 |
| [Weaviate](https://weaviate.io) | 🚧 Planned | v0.3.0 |

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'vectra'
```

And then execute:

```bash
bundle install
```

Or install it yourself:

```bash
gem install vectra
```

### Provider-Specific Dependencies

For **pgvector** support, add the `pg` gem:

```ruby
gem 'pg', '~> 1.5'
```

## Quick Start

### Configuration

```ruby
require 'vectra'

# Global configuration
Vectra.configure do |config|
  config.provider = :pinecone
  config.api_key = ENV['PINECONE_API_KEY']
  config.environment = 'us-east-1'  # or config.host = 'your-index-host.pinecone.io'
end

# Create a client
client = Vectra::Client.new
```

Or use per-client configuration:

```ruby
# Shortcut for Pinecone
client = Vectra.pinecone(
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-east-1'
)

# Shortcut for pgvector (PostgreSQL)
client = Vectra.pgvector(
  connection_url: 'postgres://user:password@localhost/mydb'
)

# Generic client with options
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-east-1',
  timeout: 60,
  max_retries: 5
)
```

### Basic Operations

#### Upsert Vectors

```ruby
client.upsert(
  index: 'my-index',
  vectors: [
    { id: 'vec1', values: [0.1, 0.2, 0.3], metadata: { text: 'Hello world' } },
    { id: 'vec2', values: [0.4, 0.5, 0.6], metadata: { text: 'Ruby is great' } }
  ]
)
# => { upserted_count: 2 }
```

#### Query Vectors

```ruby
results = client.query(
  index: 'my-index',
  vector: [0.1, 0.2, 0.3],
  top_k: 5,
  include_metadata: true
)

# Iterate over results
results.each do |match|
  puts "ID: #{match.id}, Score: #{match.score}"
  puts "Metadata: #{match.metadata}"
end

# Access specific results
results.first          # First match
results.ids            # All matching IDs
results.scores         # All scores
results.max_score      # Highest score

# Filter by score
high_quality = results.above_score(0.8)
```

#### Query with Filters

```ruby
results = client.query(
  index: 'my-index',
  vector: [0.1, 0.2, 0.3],
  top_k: 10,
  filter: { category: 'programming', language: 'ruby' }
)
```

#### Fetch Vectors by ID

```ruby
vectors = client.fetch(index: 'my-index', ids: ['vec1', 'vec2'])

vectors['vec1'].values    # [0.1, 0.2, 0.3]
vectors['vec1'].metadata  # { 'text' => 'Hello world' }
```

#### Update Vector Metadata

```ruby
client.update(
  index: 'my-index',
  id: 'vec1',
  metadata: { category: 'updated', processed: true }
)
```

#### Delete Vectors

```ruby
# Delete by IDs
client.delete(index: 'my-index', ids: ['vec1', 'vec2'])

# Delete by filter
client.delete(index: 'my-index', filter: { category: 'old' })

# Delete all (use with caution!)
client.delete(index: 'my-index', delete_all: true)
```

### Working with Vectors

```ruby
# Create a Vector object
vector = Vectra::Vector.new(
  id: 'my-vector',
  values: [0.1, 0.2, 0.3],
  metadata: { text: 'Example' }
)

vector.dimension        # => 3
vector.metadata?        # => true
vector.to_h             # Convert to hash

# Calculate similarity
other = Vectra::Vector.new(id: 'other', values: [0.1, 0.2, 0.3])
vector.cosine_similarity(other)    # => 1.0 (identical)
vector.euclidean_distance(other)   # => 0.0
```

### Index Management

```ruby
# List all indexes
indexes = client.list_indexes
indexes.each { |idx| puts idx[:name] }

# Describe an index
info = client.describe_index(index: 'my-index')
puts info[:dimension]  # => 384
puts info[:metric]     # => "cosine"

# Get index statistics
stats = client.stats(index: 'my-index')
puts stats[:total_vector_count]
```

### Namespaces

Namespaces allow you to partition vectors within an index:

```ruby
# Upsert to a namespace
client.upsert(
  index: 'my-index',
  namespace: 'production',
  vectors: [...]
)

# Query within a namespace
client.query(
  index: 'my-index',
  namespace: 'production',
  vector: [0.1, 0.2, 0.3],
  top_k: 5
)
```

### pgvector (PostgreSQL)

pgvector uses PostgreSQL tables as indexes. Each "index" is a table with a vector column.

#### Setup PostgreSQL with pgvector

```bash
# Using Docker
docker run -d --name pgvector \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  pgvector/pgvector:pg16
```

#### Create an Index (Table)

```ruby
client = Vectra.pgvector(connection_url: 'postgres://postgres:password@localhost/postgres')

# Create a new index with cosine similarity
client.provider.create_index(
  name: 'documents',
  dimension: 384,
  metric: 'cosine'  # or 'euclidean', 'inner_product'
)
```

#### Supported Metrics

| Metric | Description | pgvector Operator |
|--------|-------------|-------------------|
| `cosine` | Cosine similarity (default) | `<=>` |
| `euclidean` | Euclidean distance | `<->` |
| `inner_product` | Inner product / dot product | `<#>` |

#### Table Structure

Vectra creates tables with the following structure:

```sql
CREATE TABLE documents (
  id TEXT PRIMARY KEY,
  embedding vector(384),
  metadata JSONB DEFAULT '{}',
  namespace TEXT DEFAULT '',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- IVFFlat index for fast similarity search
CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops);
```

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `provider` | Vector database provider (`:pinecone`, `:pgvector`, `:qdrant`, `:weaviate`) | Required |
| `api_key` | API key for authentication (password for pgvector) | Required* |
| `environment` | Environment/region (Pinecone) | - |
| `host` | Direct host URL or PostgreSQL connection URL | - |
| `timeout` | Request timeout in seconds | 30 |
| `open_timeout` | Connection timeout in seconds | 10 |
| `max_retries` | Maximum retry attempts | 3 |
| `retry_delay` | Initial retry delay in seconds | 1 |
| `logger` | Logger instance for debugging | nil |

*For pgvector, `api_key` is used as the PostgreSQL password.

## Error Handling

Vectra provides specific error classes for different failure scenarios:

```ruby
begin
  client.query(index: 'my-index', vector: [0.1, 0.2], top_k: 5)
rescue Vectra::AuthenticationError => e
  puts "Authentication failed: #{e.message}"
rescue Vectra::RateLimitError => e
  puts "Rate limited. Retry after #{e.retry_after} seconds"
rescue Vectra::NotFoundError => e
  puts "Resource not found: #{e.message}"
rescue Vectra::ValidationError => e
  puts "Invalid request: #{e.message}"
rescue Vectra::ServerError => e
  puts "Server error (#{e.status_code}): #{e.message}"
rescue Vectra::Error => e
  puts "General error: #{e.message}"
end
```

## Logging

Enable debug logging to see request details:

```ruby
require 'logger'

Vectra.configure do |config|
  config.provider = :pinecone
  config.api_key = ENV['PINECONE_API_KEY']
  config.environment = 'us-east-1'
  config.logger = Logger.new($stdout)
end
```

## Best Practices

### Batch Upserts

For large datasets, batch your upserts:

```ruby
vectors = large_dataset.each_slice(100).map do |batch|
  client.upsert(index: 'my-index', vectors: batch)
end
```

### Connection Reuse

Create a single client instance and reuse it:

```ruby
# Good: Reuse the client
client = Vectra::Client.new(...)
client.query(...)
client.upsert(...)

# Avoid: Creating new clients for each operation
Vectra::Client.new(...).query(...)
Vectra::Client.new(...).upsert(...)
```

### Error Recovery

Implement retry logic for transient failures:

```ruby
def query_with_retry(client, **params, retries: 3)
  client.query(**params)
rescue Vectra::RateLimitError => e
  if retries > 0
    sleep(e.retry_after || 1)
    retry(retries: retries - 1)
  else
    raise
  end
end
```

## Development

After checking out the repo:

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop

# Generate documentation
bundle exec rake docs
```

## Roadmap

### v0.1.0
- ✅ Pinecone provider
- ✅ Basic CRUD operations
- ✅ Configuration system
- ✅ Error handling with retries
- ✅ Comprehensive tests

### v0.1.1 (Current)
- ✅ pgvector (PostgreSQL) provider
- ✅ Multiple similarity metrics (cosine, euclidean, inner product)
- ✅ Namespace support for pgvector
- ✅ IVFFlat index creation

### v0.2.0
- 🚧 Qdrant provider
- 🚧 Enhanced error handling
- 🚧 Connection pooling

### v0.3.0
- 🚧 Weaviate provider
- 🚧 Batch operations
- 🚧 Performance optimizations

### v1.0.0
- 🚧 Rails integration
- 🚧 ActiveRecord-like DSL
- 🚧 Background job support
- 🚧 Full documentation

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/stokry/vectra.

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Acknowledgments

Inspired by the simplicity of Ruby database gems and the need for a unified vector database interface.
