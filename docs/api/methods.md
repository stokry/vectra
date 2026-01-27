---
layout: page
title: API Methods
permalink: /api/methods/
---

# API Methods Reference

Complete reference for all Vectra API methods.

> For a quick reference, see the [API Cheatsheet](/api/cheatsheet/).  
> For an overview, see the [API Overview](/api/overview/).  
> All methods link to source code on [GitHub](https://github.com/stokry/vectra/tree/main/lib/vectra).

## Client Methods

### `Vectra::Client.new(options)`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/client.rb#L88)

Initialize a new Vectra client.

**Parameters:**
- `provider` (Symbol) - Provider name: `:pinecone`, `:qdrant`, `:weaviate`, `:pgvector`, `:memory`
- `api_key` (String, optional) - API key for cloud providers
- `host` (String, optional) - Host URL for self-hosted providers
- `environment` (String, optional) - Environment/region (Pinecone)
- `index` (String, optional) - Default index name
- `namespace` (String, optional) - Default namespace

**Returns:** `Vectra::Client`

**Example:**
```ruby
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'http://localhost:6333',
  api_key: ENV['QDRANT_API_KEY']
)
```

In a Rails app that uses the `vectra:index` generator, if `config/vectra.yml` contains exactly one entry, `Vectra::Client.new` will automatically use that entry's `index` (and `namespace` if present) as its defaults. This allows you to omit `index:` in most calls (`upsert`, `query`, `text_search`, etc.).

---

### `client.upsert(index:, vectors:, namespace: nil)`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/client.rb#L114)

Upsert vectors into an index. If a vector with the same ID exists, it will be updated.

**Parameters:**
- `index` (String) - Index/collection name (uses client's default index when omitted)
- `vectors` (Array<Hash, Vector>) - Array of vector hashes or Vector objects
- `namespace` (String, optional) - Namespace

**Vector Hash Format:**
```ruby
{
  id: 'unique-id',              # Required
  values: [0.1, 0.2, 0.3],     # Required: Array of floats
  metadata: { key: 'value' }    # Optional: Hash of metadata
}
```

**Returns:** `Hash` with `:upserted_count`

**Example:**
```ruby
result = client.upsert(
  index: 'documents',
  vectors: [
    { id: 'doc-1', values: [0.1, 0.2, 0.3], metadata: { title: 'Hello' } },
    { id: 'doc-2', values: [0.4, 0.5, 0.6], metadata: { title: 'World' } }
  ]
)
# => { upserted_count: 2 }
```

---

### `client.query(index:, vector:, top_k: 10, namespace: nil, filter: nil, include_values: false, include_metadata: true)`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/client.rb#L164)

Search for similar vectors using cosine similarity.

**Parameters:**
- `index` (String) - Index/collection name (uses client's default index when omitted)
- `vector` (Array<Float>) - Query vector
- `top_k` (Integer) - Number of results (default: 10)
- `namespace` (String, optional) - Namespace
- `filter` (Hash, optional) - Metadata filter
- `include_values` (Boolean) - Include vector values in results (default: false)
- `include_metadata` (Boolean) - Include metadata in results (default: true)

**Returns:** `Vectra::QueryResult`

**Example:**
```ruby
results = client.query(
  index: 'documents',
  vector: [0.1, 0.2, 0.3],
  top_k: 5,
  filter: { category: 'docs' },
  include_metadata: true
)

results.each do |match|
  puts "#{match.id}: #{match.score} - #{match.metadata['title']}"
end
```

**QueryResult Methods:**
- `results.each` - Iterate over matches
- `results.size` - Number of matches
- `results.ids` - Array of match IDs
- `results.scores` - Array of similarity scores
- `results.first` - First match (highest score)

---

### `client.hybrid_search(index:, vector:, text:, alpha: 0.7, top_k: 10, namespace: nil, filter: nil, include_values: false, include_metadata: true)`

Combine semantic (vector) and keyword (text) search.

**Parameters:**
- `index` (String) - Index/collection name
- `vector` (Array<Float>) - Query vector for semantic search
- `text` (String) - Text query for keyword search
- `alpha` (Float) - Balance between semantic and keyword (0.0 = pure keyword, 1.0 = pure semantic, default: 0.7)
- `top_k` (Integer) - Number of results (default: 10)
- `namespace` (String, optional) - Namespace
- `filter` (Hash, optional) - Metadata filter
- `include_values` (Boolean) - Include vector values (default: false)
- `include_metadata` (Boolean) - Include metadata (default: true)

**Returns:** `Vectra::QueryResult`

**Provider Support:**
- ✅ Qdrant
- ✅ Weaviate
- ✅ pgvector
- ⚠️ Pinecone (limited support)

**Example:**
```ruby
results = client.hybrid_search(
  index: 'documents',
  vector: query_embedding,
  text: 'ruby vector search',
  alpha: 0.7,  # 70% semantic, 30% keyword
  top_k: 10
)
```

---

### `client.text_search(index:, text:, top_k: 10, namespace: nil, filter: nil, include_values: false, include_metadata: true)`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/client.rb#L529)

Text-only search (keyword search without requiring embeddings).

**Parameters:**
- `index` (String) - Index/collection name (uses client's default index when omitted)
- `text` (String) - Text query for keyword search
- `top_k` (Integer) - Number of results (default: 10)
- `namespace` (String, optional) - Namespace
- `filter` (Hash, optional) - Metadata filter
- `include_values` (Boolean) - Include vector values (default: false)
- `include_metadata` (Boolean) - Include metadata (default: true)

**Returns:** `Vectra::QueryResult`

**Provider Support:**
- ✅ Qdrant (BM25)
- ✅ Weaviate (BM25)
- ✅ pgvector (PostgreSQL full-text search)
- ✅ Memory (simple keyword matching - for testing only)
- ❌ Pinecone (not supported - use sparse vectors instead)

**Example:**
```ruby
# Keyword search for exact matches
results = client.text_search(
  index: 'products',
  text: 'iPhone 15 Pro',
  top_k: 10,
  filter: { category: 'electronics' }
)

results.each do |match|
  puts "#{match.id}: #{match.score} - #{match.metadata['title']}"
end
```

**Use Cases:**
- Product name search (exact matches)
- Function/class name search in documentation
- Keyword-based filtering when semantic search is not needed
- Faster search when embeddings are not available

---

### `client.fetch(index:, ids:, namespace: nil)`

Fetch vectors by their IDs.

**Parameters:**
- `index` (String) - Index/collection name (uses client's default index when omitted)
- `ids` (Array<String>) - Array of vector IDs
- `namespace` (String, optional) - Namespace

**Returns:** `Hash<String, Vectra::Vector>` - Hash mapping ID to Vector object

**Example:**
```ruby
vectors = client.fetch(
  index: 'documents',
  ids: ['doc-1', 'doc-2']
)

vectors['doc-1'].values   # => [0.1, 0.2, 0.3]
vectors['doc-1'].metadata # => { 'title' => 'Hello' }
```

---

### `client.update(index:, id:, metadata: nil, values: nil, namespace: nil)`

Update a vector's metadata or values.

**Parameters:**
- `index` (String) - Index/collection name (uses client's default index when omitted)
- `id` (String) - Vector ID
- `metadata` (Hash, optional) - New metadata (merged with existing)
- `values` (Array<Float>, optional) - New vector values
- `namespace` (String, optional) - Namespace

**Returns:** `Hash` with `:updated`

**Note:** Must provide either `metadata` or `values` (or both).

**Example:**
```ruby
client.update(
  index: 'documents',
  id: 'doc-1',
  metadata: { category: 'updated', status: 'published' }
)
```

---

### `client.delete(index:, ids: nil, namespace: nil, filter: nil, delete_all: false)`

Delete vectors.

**Parameters:**
- `index` (String) - Index/collection name (uses client's default index when omitted)
- `ids` (Array<String>, optional) - Vector IDs to delete
- `namespace` (String, optional) - Namespace
- `filter` (Hash, optional) - Delete by metadata filter
- `delete_all` (Boolean) - Delete all vectors in namespace (default: false)

**Returns:** `Hash` with `:deleted`

**Note:** Must provide `ids`, `filter`, or `delete_all: true`.

**Example:**
```ruby
# Delete by IDs
client.delete(index: 'documents', ids: ['doc-1', 'doc-2'])

# Delete by filter
client.delete(index: 'documents', filter: { category: 'old' })

# Delete all
client.delete(index: 'documents', delete_all: true)
```

---

### `client.stats(index:, namespace: nil)`

Get index statistics.

**Parameters:**
- `index` (String) - Index/collection name (uses client's default index when omitted)
- `namespace` (String, optional) - Namespace

**Returns:** `Hash` with statistics:
- `dimension` (Integer) - Vector dimension
- `total_vector_count` (Integer) - Total number of vectors
- `namespaces` (Hash, optional) - Namespace breakdown with vector counts

**Example:**
```ruby
stats = client.stats(index: 'documents')
# => { dimension: 1536, total_vector_count: 1000, namespaces: { "default" => { vector_count: 1000 } } }
```

---

### `client.create_index(name:, dimension:, metric: "cosine", **options)`

Create a new index/collection.

**Parameters:**
- `name` (String) - Index name
- `dimension` (Integer) - Vector dimension
- `metric` (String) - Distance metric: `"cosine"` (default), `"euclidean"`, `"dot_product"`
- `options` (Hash) - Provider-specific options (e.g., `on_disk: true` for Qdrant)

**Returns:** `Hash` with index information

**Note:** Not all providers support index creation. Raises `NotImplementedError` if provider doesn't support it (e.g., Memory, Weaviate).

**Example:**
```ruby
# Create index with default cosine metric
result = client.create_index(name: 'documents', dimension: 384)
# => { name: 'documents', dimension: 384, metric: 'cosine', status: 'ready' }

# Create with custom metric (Qdrant)
result = client.create_index(
  name: 'products',
  dimension: 1536,
  metric: 'euclidean',
  on_disk: true
)
```

---

### `client.delete_index(name:)`

Delete an index/collection.

**Parameters:**
- `name` (String) - Index name

**Returns:** `Hash` with `:deleted => true`

**Note:** Not all providers support index deletion. Raises `NotImplementedError` if provider doesn't support it (e.g., Memory, Weaviate).

**Example:**
```ruby
result = client.delete_index(name: 'old-index')
# => { deleted: true }
```

---

### `client.list_namespaces(index:)`

List all namespaces in an index.

**Parameters:**
- `index` (String) - Index/collection name

**Returns:** `Array<String>` - List of namespace names (excludes empty/default namespace)

**Example:**
```ruby
namespaces = client.list_namespaces(index: 'documents')
# => ["tenant-1", "tenant-2", "tenant-3"]

namespaces.each do |ns|
  stats = client.stats(index: 'documents', namespace: ns)
  puts "Namespace #{ns}: #{stats[:total_vector_count]} vectors"
end
```

---

## Health & Monitoring Methods

### `client.healthy?`

Quick health check - returns true if provider connection is healthy.

**Returns:** `Boolean`

**Example:**
```ruby
if client.healthy?
  client.upsert(...)
else
  Rails.logger.warn('Vectra provider is unhealthy')
end
```

---

### `client.ping`

Ping provider and get connection health status with latency.

**Returns:** `Hash` with:
- `healthy` (Boolean) - Health status
- `provider` (Symbol) - Provider name
- `latency_ms` (Float) - Latency in milliseconds

**Example:**
```ruby
status = client.ping
# => { healthy: true, provider: :qdrant, latency_ms: 23.4 }

puts "Latency: #{status[:latency_ms]}ms"
```

---

### `client.with_timeout(seconds) { ... }`

Temporarily override the client's request timeout inside a block.

**Parameters:**
- `seconds` (Float) - Temporary timeout in seconds

**Returns:** Block result

**Example (fast health check in Rails controller):**
```ruby
status = client.with_timeout(0.5) do |c|
  c.ping
end

render json: status, status: status[:healthy] ? :ok : :service_unavailable
```

After the block finishes (even if it raises), the previous `config.timeout` value is restored.

---

### `client.validate!(require_default_index: false, require_default_namespace: false, features: [])`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/client.rb#L647)

Validate the client configuration and (optionally) your defaults and provider feature support.

This is useful in boot-time checks (Rails initializers), health endpoints, and CI.

**Parameters:**
- `require_default_index` (Boolean) - Require `client.default_index` to be set
- `require_default_namespace` (Boolean) - Require `client.default_namespace` to be set
- `features` (Array<Symbol> or Symbol) - Provider features (methods) that must be supported (e.g. `:text_search`)

**Returns:** `Vectra::Client` (self)

**Raises:** `Vectra::ConfigurationError` when validation fails

**Example:**
```ruby
# Ensure client is configured
client.validate!

# Ensure calls can omit index:
client.validate!(require_default_index: true)

# Ensure provider supports text_search:
client.validate!(features: [:text_search])
```

---

### `client.with_defaults(index: ..., namespace: ...) { ... }`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/client.rb#L1006)

Temporarily override the client's **default index and/or namespace** inside a block.

Unlike `with_index_and_namespace`, this helper accepts keyword arguments and only overrides what you pass.

**Returns:** Block result

**Example:**
```ruby
client.with_defaults(index: "products", namespace: "tenant-2") do |c|
  c.upsert(vectors: [...]) # uses products/tenant-2
  c.query(vector: embedding, top_k: 10)
end

# Previous defaults are restored after the block.
```

---

### `client.valid?(require_default_index: false, require_default_namespace: false, features: [])`

Non-raising validation. Returns `true` if the client passes `validate!`, `false` otherwise. Accepts the same options as `validate!`.

**Returns:** `Boolean`

**Example:**
```ruby
next unless client.valid?
client.upsert(vectors: [...])

# With same options as validate!
client.valid?(require_default_index: true)
client.valid?(features: [:text_search])
```

---

### `client.for_tenant(tenant_id, namespace_prefix: "tenant_") { ... }`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/client.rb#L1022)

Multi-tenant block helper. Temporarily sets the default namespace to `"#{namespace_prefix}#{tenant_id}"`, yields the client, then restores the previous namespace. `tenant_id` can be a string, symbol, or anything responding to `to_s`.

**Parameters:**
- `tenant_id` (String, Symbol, #to_s) - Tenant identifier
- `namespace_prefix` (String) - Prefix for namespace (default: `"tenant_"`)

**Returns:** Block result

**Example:**
```ruby
client.for_tenant("acme", namespace_prefix: "tenant_") do |c|
  c.upsert(vectors: [...])
  c.query(vector: embedding, top_k: 10)
end
# All operations use namespace "tenant_acme"; previous default restored after block.
```

---

### `client.health_check`

Detailed health check with provider-specific information.

**Returns:** `Hash` with detailed health information

**Example:**
```ruby
health = client.health_check
# => { healthy: true, provider: :qdrant, version: '1.7.0', ... }
```

---

## Vector Helper Methods

### `Vectra::Vector.normalize(vector, type: :l2)`

Normalize a vector array (non-mutating).

**Parameters:**
- `vector` (Array<Float>) - Vector values to normalize
- `type` (Symbol) - Normalization type: `:l2` (default) or `:l1`

**Returns:** `Array<Float>` - Normalized vector

**Example:**
```ruby
embedding = openai_response['data'][0]['embedding']
normalized = Vectra::Vector.normalize(embedding, type: :l2)
client.upsert(vectors: [{ id: 'doc-1', values: normalized }])
```

---

### `vector.normalize!(type: :l2)`

Normalize vector in-place (mutates the vector).

**Parameters:**
- `type` (Symbol) - Normalization type: `:l2` (default) or `:l1`

**Returns:** `Self` (for method chaining)

**Example:**
```ruby
vector = Vectra::Vector.new(id: 'doc-1', values: embedding)
vector.normalize!  # L2 normalization
client.upsert(vectors: [vector])
```

---

## Batch Operations

### `Vectra::Batch.upsert(client:, index:, vectors:, batch_size: 100, namespace: nil, on_progress: nil)`

Upsert vectors in batches with progress callbacks.

**Parameters:**
- `client` (Vectra::Client) - Vectra client
- `index` (String) - Index/collection name
- `vectors` (Array<Hash, Vector>) - Vectors to upsert
- `batch_size` (Integer) - Batch size (default: 100)
- `namespace` (String, optional) - Namespace
- `on_progress` (Proc, optional) - Progress callback: `->(batch_index, total_batches, batch_count) { ... }`

**Returns:** `Hash` with `:upserted_count`

**Example:**
```ruby
Vectra::Batch.upsert(
  client: client,
  index: 'products',
  vectors: product_vectors,
  batch_size: 100,
  on_progress: ->(batch_index, total_batches, batch_count) do
    puts "Batch #{batch_index + 1}/#{total_batches} (#{batch_count} vectors)"
  end
)
```

---

### `batch.query_async(index:, vectors:, top_k: 10, namespace: nil, filter: nil, include_values: false, include_metadata: true, chunk_size: 10, on_progress: nil)`

Query multiple vectors concurrently (useful for recommendation engines).

**Parameters:**
- `index` (String) - Index/collection name
- `vectors` (Array<Array<Float>>) - Array of query vectors
- `top_k` (Integer) - Number of results per query (default: 10)
- `namespace` (String, optional) - Namespace
- `filter` (Hash, optional) - Metadata filter
- `include_values` (Boolean) - Include vector values in results (default: false)
- `include_metadata` (Boolean) - Include metadata in results (default: true)
- `chunk_size` (Integer) - Queries per chunk for progress tracking (default: 10)
- `on_progress` (Proc, optional) - Progress callback: `->(stats) { ... }`

**Returns:** `Array<QueryResult>` - One QueryResult per input vector

**Example:**
```ruby
batch = Vectra::Batch.new(client, concurrency: 4)

# Find similar items for multiple products
product_embeddings = products.map(&:embedding)
results = batch.query_async(
  index: 'products',
  vectors: product_embeddings,
  top_k: 5,
  on_progress: ->(stats) do
    puts "Processed #{stats[:processed]}/#{stats[:total]} queries (#{stats[:percentage]}%)"
  end
)

# Each result corresponds to one product
results.each_with_index do |result, i|
  puts "Similar to product #{i}: #{result.ids}"
end
```

---

## Query Builder (Chainable API)

### `client.query(index)`

Start a chainable query builder.

**Returns:** `Vectra::QueryBuilder`

**Example:**
```ruby
results = client
  .query('documents')
  .vector([0.1, 0.2, 0.3])
  .top_k(10)
  .filter(category: 'docs')
  .with_metadata
  .execute

results.each do |match|
  puts "#{match.id}: #{match.score}"
end
```

**QueryBuilder Methods:**
- `.vector(array)` - Set query vector
- `.top_k(integer)` - Set number of results
- `.filter(hash)` - Set metadata filter
- `.namespace(string)` - Set namespace
- `.with_metadata` - Include metadata in results
- `.with_values` - Include vector values in results
- `.execute` - Execute query and return QueryResult

---

## ActiveRecord Methods

### `has_vector(column_name, options)`

Define vector search on an ActiveRecord model.

**Parameters:**
- `column_name` (Symbol) - Column name (e.g., `:embedding`)
- `provider` (Symbol) - Provider name (default: from global config)
- `index` (String) - Index/collection name
- `dimension` (Integer) - Vector dimension
- `auto_index` (Boolean) - Auto-index on save (default: true)
- `metadata_fields` (Array<Symbol>) - Fields to include in metadata

**Example:**
```ruby
class Document < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding,
    provider: :qdrant,
    index: 'documents',
    dimension: 1536,
    auto_index: true,
    metadata_fields: [:title, :category]
end
```

---

### `Model.vector_search(embedding:, limit: 10, filter: nil)`

Search for similar records using vector similarity.

**Parameters:**
- `embedding` (Array<Float>) - Query vector
- `limit` (Integer) - Number of results (default: 10)
- `filter` (Hash, optional) - Metadata filter

**Returns:** `ActiveRecord::Relation`

**Example:**
```ruby
results = Document.vector_search(
  embedding: query_embedding,
  limit: 10,
  filter: { category: 'docs' }
)

results.each do |doc|
  puts doc.title
end
```

---

### `Model.reindex_vectors(scope: all, batch_size: 1000, on_progress: nil)`

Reindex all records for a model into the configured vector index.

**Parameters:**
- `scope` (ActiveRecord::Relation) - Records to reindex (default: `Model.all`)
- `batch_size` (Integer) - Number of records per batch (default: 1000)
- `on_progress` (Proc, optional) - Progress callback, receives a hash with `:processed` and `:total`

**Returns:** `Integer` - Number of records processed

**Example:**
```ruby
# Reindex all products with embeddings
processed = Product.reindex_vectors(
  scope: Product.where.not(embedding: nil),
  batch_size: 500
)

puts "Reindexed #{processed} products"
```

---

## Migration Tool

### `Vectra::Migration.new(source_client, target_client)`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/migration.rb)

Initialize a migration tool for copying vectors between providers.

**Parameters:**
- `source_client` (Vectra::Client) - Source provider client
- `target_client` (Vectra::Client) - Target provider client

**Returns:** `Vectra::Migration`

**Example:**
```ruby
source_client = Vectra::Client.new(provider: :memory)
target_client = Vectra::Client.new(provider: :qdrant, host: "http://localhost:6333")

migration = Vectra::Migration.new(source_client, target_client)
```

---

### `migration.migrate(source_index:, target_index:, source_namespace: nil, target_namespace: nil, batch_size: 1000, chunk_size: 100, on_progress: nil)`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/migration.rb#L60)

Migrate vectors from source to target index.

**Parameters:**
- `source_index` (String) - Source index name
- `target_index` (String) - Target index name
- `source_namespace` (String, nil) - Source namespace (optional)
- `target_namespace` (String, nil) - Target namespace (optional)
- `batch_size` (Integer) - Vectors per batch for fetching (default: 1000)
- `chunk_size` (Integer) - Vectors per chunk for upsert (default: 100)
- `on_progress` (Proc, nil) - Progress callback, receives hash with `:migrated`, `:total`, `:percentage`, `:batches_processed`, `:total_batches`

**Returns:** `Hash` - Migration result with `:migrated_count`, `:total_vectors`, `:batches`, `:errors`

**Example:**
```ruby
result = migration.migrate(
  source_index: "old-index",
  target_index: "new-index",
  source_namespace: "ns1",
  target_namespace: "ns2",
  on_progress: ->(stats) {
    puts "Progress: #{stats[:percentage]}% (#{stats[:migrated]}/#{stats[:total]})"
  }
)

puts "Migrated #{result[:migrated_count]} vectors in #{result[:batches]} batches"
puts "Errors: #{result[:errors].size}" if result[:errors].any?
```

---

### `migration.verify(source_index:, target_index:, source_namespace: nil, target_namespace: nil)`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/migration.rb#L165)

Verify migration by comparing vector counts between source and target.

**Parameters:**
- `source_index` (String) - Source index name
- `target_index` (String) - Target index name
- `source_namespace` (String, nil) - Source namespace (optional)
- `target_namespace` (String, nil) - Target namespace (optional)

**Returns:** `Hash` - Verification result with `:source_count`, `:target_count`, `:match`

**Example:**
```ruby
verification = migration.verify(
  source_index: "old-index",
  target_index: "new-index"
)

if verification[:match]
  puts "✅ Migration verified: #{verification[:source_count]} vectors"
else
  puts "❌ Mismatch: source=#{verification[:source_count]}, target=#{verification[:target_count]}"
end
```

---

## Middleware

### `Vectra::Middleware::RequestId`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/middleware/request_id.rb)

Request ID tracking middleware. Generates a unique request ID for each operation and propagates it through logs and instrumentation.

**Configuration:**
```ruby
# Global
Vectra::Client.use Vectra::Middleware::RequestId

# With custom prefix
Vectra::Client.use Vectra::Middleware::RequestId, prefix: "myapp"

# With custom generator
Vectra::Client.use Vectra::Middleware::RequestId,
  generator: ->(prefix) { "#{prefix}-#{Time.now.to_i}-#{SecureRandom.hex(8)}" }

# With callback
Vectra::Client.use Vectra::Middleware::RequestId,
  on_assign: ->(id) { Rails.logger.info("Request ID: #{id}") }
```

**Access request ID:**
```ruby
# In custom middleware
def after(request, response)
  request_id = request.metadata[:request_id]
  # Use request_id for tracing
end
```

---

### `Vectra::Middleware::DryRun`

[Source](https://github.com/stokry/vectra/blob/main/lib/vectra/middleware/dry_run.rb)

Dry run / explain mode middleware. Intercepts write operations and logs what would be executed instead of actually executing them.

**Configuration:**
```ruby
# Enable dry run mode
client = Vectra::Client.new(
  provider: :qdrant,
  middleware: [Vectra::Middleware::DryRun]
)

# Operations will be logged but not executed
client.upsert(index: "test", vectors: [...])

# With custom logger
Vectra::Client.use Vectra::Middleware::DryRun, logger: custom_logger

# With custom formatter
Vectra::Client.use Vectra::Middleware::DryRun,
  formatter: ->(request) { "Would execute: #{request.operation}" }

# With callback
Vectra::Client.use Vectra::Middleware::DryRun,
  on_dry_run: ->(plan) { puts "Plan: #{plan.inspect}" }
```

**Note:** Read operations (query, fetch, stats) pass through normally and are not intercepted.

---

## Error Handling

Vectra defines specific error types:

- `Vectra::Error` - Base error class
- `Vectra::NotFoundError` - Index or vector not found
- `Vectra::ValidationError` - Invalid parameters
- `Vectra::RateLimitError` - Rate limit exceeded
- `Vectra::ConnectionError` - Connection failed
- `Vectra::TimeoutError` - Request timeout
- `Vectra::AuthenticationError` - Authentication failed
- `Vectra::ConfigurationError` - Configuration error
- `Vectra::ProviderError` - Provider-specific error

**Example:**
```ruby
begin
  client.query(index: 'missing', vector: [0.1, 0.2, 0.3])
rescue Vectra::NotFoundError => e
  Rails.logger.warn("Index not found: #{e.message}")
rescue Vectra::RateLimitError => e
  Rails.logger.error("Rate limited: #{e.message}")
rescue Vectra::Error => e
  Rails.logger.error("Vectra error: #{e.message}")
end
```

---

## See Also

- [API Cheatsheet](/api/cheatsheet/) - Quick reference
- [API Overview](/api/overview/) - Overview and examples
- [Recipes & Patterns](/guides/recipes/) - Real-world examples
- [Rails Integration Guide](/guides/rails-integration/) - ActiveRecord integration
