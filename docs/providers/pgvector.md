---
layout: page
title: PostgreSQL with pgvector
permalink: /providers/pgvector/
---

# PostgreSQL with pgvector Provider

[pgvector](https://github.com/pgvector/pgvector) is a PostgreSQL extension for vector data.

## Setup

### Prerequisites

```bash
# Install PostgreSQL with pgvector extension
# macOS with Homebrew
brew install postgresql

# Enable pgvector extension
psql -d your_database -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### Connect with Vectra

```ruby
client = Vectra::Client.new(
  provider: :pgvector,
  database: 'my_database',
  host: 'localhost',
  port: 5432,
  user: 'postgres',
  password: ENV['DB_PASSWORD']
)
```

## Features

- ✅ Upsert vectors
- ✅ Query/search
- ✅ Delete vectors
- ✅ SQL integration
- ✅ ACID transactions
- ✅ Complex queries
- ✅ Rails ActiveRecord integration
- ✅ Hybrid search (vector + full-text search)

## Example

```ruby
# Initialize client
client = Vectra::Client.new(
  provider: :pgvector,
  database: 'vectors_db',
  host: 'localhost'
)

# Upsert vectors
client.upsert(
  vectors: [
    { id: 'doc-1', values: [0.1, 0.2, 0.3], metadata: { title: 'Doc 1' } }
  ]
)

# Search using cosine distance
results = client.query(vector: [0.1, 0.2, 0.3], top_k: 5)

# Hybrid search (requires text column with tsvector index)
# First, create the index:
# CREATE INDEX idx_content_fts ON my_index USING gin(to_tsvector('english', content));
results = client.hybrid_search(
  index: 'my_index',
  vector: embedding,
  text: 'ruby programming',
  alpha: 0.7,
  text_column: 'content'  # default: 'content'
)
```

## ActiveRecord Integration

```ruby
class Document < ApplicationRecord
  include Vectra::ActiveRecord
  
  vector_search :embedding_vector
end

# Search
docs = Document.vector_search([0.1, 0.2, 0.3], limit: 10)
```

## Configuration Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `database` | String | Yes | Database name |
| `host` | String | Yes | PostgreSQL host |
| `port` | Integer | No | PostgreSQL port (default: 5432) |
| `user` | String | No | Database user |
| `password` | String | No | Database password |
| `schema` | String | No | Database schema |

## Documentation

- [pgvector GitHub](https://github.com/pgvector/pgvector)
- [pgvector Docs](https://github.com/pgvector/pgvector#readme)
