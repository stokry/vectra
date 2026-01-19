---
layout: page
title: API Methods
permalink: /api/methods/
---

# API Methods Reference

Complete reference for all Vectra API methods.

> For a quick reference, see the [API Cheatsheet](/api/cheatsheet/).  
> For an overview, see the [API Overview](/api/overview/).

## Client Methods

### `Vectra::Client.new(options)`

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
