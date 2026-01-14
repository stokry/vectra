---
layout: page
title: Recipes & Patterns
permalink: /guides/recipes/
---

# Recipes & Patterns

Real-world patterns and recipes for common use cases with Vectra.

## E-Commerce: Semantic Product Search with Filters

**Use Case:** Build a product search that understands user intent and supports filtering by category, price, and availability.

### Model Setup

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding,
    provider: :qdrant,
    index: 'products',
    dimension: 1536,
    metadata_fields: [:name, :category, :price, :in_stock, :brand]

  # Scope for filtering
  scope :in_category, ->(cat) { where(category: cat) }
  scope :in_price_range, ->(min, max) { where(price: min..max) }
  scope :available, -> { where(in_stock: true) }
end
```

### Search Service

```ruby
# app/services/product_search_service.rb
class ProductSearchService
  def self.search(query_text:, category: nil, min_price: nil, max_price: nil, limit: 10)
    # Generate embedding from query
    query_embedding = EmbeddingService.generate(query_text)

    # Build filter
    filter = {}
    filter[:category] = category if category.present?
    filter[:price] = { gte: min_price } if min_price
    filter[:price] = { lte: max_price } if max_price
    filter[:in_stock] = true # Always show only available products

    # Perform vector search
    results = Vectra::Client.new.query(
      index: 'products',
      vector: query_embedding,
      top_k: limit,
      filter: filter
    )

    # Map to Product records
    product_ids = results.map(&:id)
    Product.where(id: product_ids)
      .order("array_position(ARRAY[?]::bigint[], id)", product_ids)
  end
end
```

### Controller

```ruby
# app/controllers/products_controller.rb
class ProductsController < ApplicationController
  def search
    @products = ProductSearchService.search(
      query_text: params[:q],
      category: params[:category],
      min_price: params[:min_price],
      max_price: params[:max_price],
      limit: 20
    )
  end
end
```

### Usage

```ruby
# Search for "wireless headphones under $100"
ProductSearchService.search(
  query_text: "wireless headphones",
  max_price: 100.0,
  limit: 10
)
```

**Key Benefits:**
- Semantic understanding: "headphones" matches "earbuds", "earphones"
- Fast filtering with metadata
- Scales to millions of products

---

## Blog: Hybrid Search (Semantic + Keyword)

**Use Case:** Blog search that combines semantic understanding with exact keyword matching for best results.

### Model Setup

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding,
    provider: :pinecone,
    index: 'articles',
    dimension: 1536,
    metadata_fields: [:title, :author, :published_at, :tags]

  # Text content for keyword search
  def searchable_text
    "#{title} #{body}"
  end
end
```

### Hybrid Search Service

```ruby
# app/services/article_search_service.rb
class ArticleSearchService
  def self.hybrid_search(query:, tags: nil, author: nil, limit: 10, alpha: 0.7)
    client = Vectra::Client.new

    # Generate embedding
    query_embedding = EmbeddingService.generate(query)

    # Build filter
    filter = {}
    filter[:tags] = tags if tags.present?
    filter[:author] = author if author.present?

    # Hybrid search: 70% semantic, 30% keyword
    results = client.hybrid_search(
      index: 'articles',
      vector: query_embedding,
      text: query,
      alpha: alpha, # 0.7 = 70% semantic, 30% keyword
      filter: filter,
      top_k: limit
    )

    # Map to Article records
    article_ids = results.map(&:id)
    Article.where(id: article_ids)
      .order("array_position(ARRAY[?]::bigint[], id)", article_ids)
  end
end
```

### Usage

```ruby
# Search with hybrid approach
ArticleSearchService.hybrid_search(
  query: "ruby on rails performance optimization",
  tags: ["ruby", "performance"],
  alpha: 0.7 # Tune based on your content
)

# More keyword-focused (for exact matches)
ArticleSearchService.hybrid_search(
  query: "ActiveRecord query optimization",
  alpha: 0.3 # 30% semantic, 70% keyword
)
```

**Key Benefits:**
- Catches semantic intent ("performance" → "speed", "optimization")
- Preserves exact keyword matches ("ActiveRecord" stays exact)
- Tunable with `alpha` parameter

---

## Multi-Tenant SaaS: Namespace Isolation

**Use Case:** Separate vector data per tenant while using a single index.

### Model Setup

```ruby
# app/models/document.rb
class Document < ApplicationRecord
  include Vectra::ActiveRecord

  belongs_to :tenant

  has_vector :embedding,
    provider: :qdrant,
    index: 'documents',
    dimension: 1536,
    metadata_fields: [:tenant_id, :title, :category]

  # Override namespace to use tenant_id
  def vector_namespace
    "tenant_#{tenant_id}"
  end
end
```

### Tenant-Scoped Search

```ruby
# app/services/document_search_service.rb
class DocumentSearchService
  def self.search_for_tenant(tenant:, query:, limit: 10)
    query_embedding = EmbeddingService.generate(query)

    client = Vectra::Client.new
    results = client.query(
      index: 'documents',
      vector: query_embedding,
      namespace: "tenant_#{tenant.id}",
      top_k: limit,
      filter: { tenant_id: tenant.id } # Double protection
    )

    document_ids = results.map(&:id)
    tenant.documents.where(id: document_ids)
      .order("array_position(ARRAY[?]::bigint[], id)", document_ids)
  end
end
```

### Usage

```ruby
tenant = Tenant.find(1)
DocumentSearchService.search_for_tenant(
  tenant: tenant,
  query: "user documentation",
  limit: 10
)
```

**Key Benefits:**
- Complete tenant isolation
- Single index, multiple namespaces
- Efficient resource usage

---

## RAG Chatbot: Context Retrieval

**Use Case:** Retrieve relevant context chunks for a RAG (Retrieval-Augmented Generation) chatbot.

### Chunk Model

```ruby
# app/models/document_chunk.rb
class DocumentChunk < ApplicationRecord
  include Vectra::ActiveRecord

  belongs_to :document

  has_vector :embedding,
    provider: :weaviate,
    index: 'document_chunks',
    dimension: 1536,
    metadata_fields: [:document_id, :chunk_index, :source_url]

  # Store chunk text for context
  def context_text
    content
  end
end
```

### RAG Service

```ruby
# app/services/rag_service.rb
class RAGService
  def self.retrieve_context(query:, document_ids: nil, top_k: 5)
    query_embedding = EmbeddingService.generate(query)

    client = Vectra::Client.new

    # Build filter if searching specific documents
    filter = {}
    filter[:document_id] = document_ids if document_ids.present?

    # Retrieve relevant chunks
    results = client.query(
      index: 'document_chunks',
      vector: query_embedding,
      top_k: top_k,
      filter: filter,
      include_metadata: true
    )

    # Build context from chunks
    chunks = DocumentChunk.where(id: results.map(&:id))
    context = chunks.map do |chunk|
      {
        text: chunk.context_text,
        source: chunk.source_url,
        score: results.find { |r| r.id == chunk.id.to_s }&.score
      }
    end

    # Combine into single context string
    context.map { |c| c[:text] }.join("\n\n")
  end

  def self.generate_response(query:, context:)
    # Use your LLM (OpenAI, Anthropic, etc.)
    # prompt = "Context: #{context}\n\nQuestion: #{query}\n\nAnswer:"
    # LLMClient.complete(prompt)
  end
end
```

### Usage

```ruby
# Retrieve context for a question
context = RAGService.retrieve_context(
  query: "How do I configure authentication?",
  document_ids: [1, 2, 3], # Optional: limit to specific docs
  top_k: 5
)

# Generate response with context
response = RAGService.generate_response(
  query: "How do I configure authentication?",
  context: context
)
```

**Key Benefits:**
- Retrieves most relevant context chunks
- Supports document filtering
- Ready for LLM integration

---

## Zero-Downtime Provider Migration

**Use Case:** Migrate from one provider to another without downtime.

### Dual-Write Strategy

```ruby
# app/services/vector_migration_service.rb
class VectorMigrationService
  def self.migrate_provider(from_provider:, to_provider:, index:)
    from_client = Vectra::Client.new(provider: from_provider)
    to_client = Vectra::Client.new(provider: to_provider)

    # Create index in new provider
    to_client.provider.create_index(name: index, dimension: 1536)

    # Batch migrate vectors
    batch_size = 100
    offset = 0

    loop do
      # Fetch batch from old provider (if supported)
      # For most providers, you'll need to maintain a list of IDs
      vector_ids = get_vector_ids(from_client, index, offset, batch_size)
      break if vector_ids.empty?

      # Fetch vectors
      vectors = from_client.fetch(index: index, ids: vector_ids)

      # Write to new provider
      to_client.upsert(
        index: index,
        vectors: vectors.values.map do |v|
          {
            id: v.id,
            values: v.values,
            metadata: v.metadata
          }
        end
      )

      offset += batch_size
      puts "Migrated #{offset} vectors..."
    end
  end

  private

  def self.get_vector_ids(client, index, offset, limit)
    # Provider-specific: maintain your own ID list or use provider's list API
    # This is a simplified example
    []
  end
end
```

### Canary Deployment

```ruby
# config/initializers/vectra.rb
require 'vectra'

# Use feature flag for gradual migration
if ENV['VECTRA_USE_NEW_PROVIDER'] == 'true'
  Vectra.configure do |config|
    config.provider = :pinecone # New provider
    config.api_key = ENV['PINECONE_API_KEY']
  end
else
  Vectra.configure do |config|
    config.provider = :qdrant # Old provider
    config.host = ENV['QDRANT_HOST']
  end
end
```

### Dual-Write During Migration

```ruby
# app/models/concerns/vector_dual_write.rb
module VectorDualWrite
  extend ActiveSupport::Concern

  included do
    after_save :write_to_both_providers, if: :should_dual_write?
  end

  private

  def write_to_both_providers
    # Write to primary (new provider)
    primary_client.upsert(...)

    # Also write to secondary (old provider) during migration
    if ENV['VECTRA_DUAL_WRITE'] == 'true'
      secondary_client.upsert(...)
    end
  end

  def should_dual_write?
    ENV['VECTRA_DUAL_WRITE'] == 'true'
  end
end
```

**Migration Steps:**
1. Enable dual-write: `VECTRA_DUAL_WRITE=true`
2. Migrate existing data: `VectorMigrationService.migrate_provider(...)`
3. Verify new provider works
4. Switch reads: `VECTRA_USE_NEW_PROVIDER=true`
5. Disable dual-write after verification

**Key Benefits:**
- Zero downtime
- Gradual rollout
- Easy rollback

---

## Recommendation Engine: Similar Items

**Use Case:** Find similar products/articles based on user behavior or item characteristics.

### Similarity Service

```ruby
# app/services/similarity_service.rb
class SimilarityService
  def self.find_similar(item:, limit: 10, exclude_ids: [])
    client = Vectra::Client.new

    # Get item's embedding
    embedding = item.embedding
    return [] unless embedding.present?

    # Find similar items
    results = client.query(
      index: item.class.table_name,
      vector: embedding,
      top_k: limit + exclude_ids.size, # Get extra to account for exclusions
      filter: { id: { not_in: exclude_ids } } if exclude_ids.any?
    )

    # Map to records
    item_ids = results.map(&:id).reject { |id| exclude_ids.include?(id) }
    item.class.where(id: item_ids)
      .order("array_position(ARRAY[?]::bigint[], id)", item_ids)
      .limit(limit)
  end

  def self.find_similar_by_user(user:, limit: 10)
    # Get user's average embedding from liked/viewed items
    user_items = user.viewed_items.includes(:embedding)
    embeddings = user_items.map(&:embedding).compact

    return [] if embeddings.empty?

    # Average user's preference vector
    avg_embedding = embeddings.transpose.map { |vals| vals.sum / vals.size }

    # Find similar items
    client = Vectra::Client.new
    results = client.query(
      index: 'products',
      vector: avg_embedding,
      top_k: limit,
      filter: { id: { not_in: user.viewed_item_ids } }
    )

    Product.where(id: results.map(&:id))
  end
end
```

### Usage

```ruby
# Find similar products
product = Product.find(1)
SimilarityService.find_similar(
  item: product,
  limit: 5,
  exclude_ids: [product.id]
)

# Find recommendations based on user behavior
user = User.find(1)
SimilarityService.find_similar_by_user(user: user, limit: 10)
```

**Key Benefits:**
- Personalized recommendations
- Fast similarity search
- Scales to millions of items

---

## Performance Tips

### 1. Batch Operations

Always use batch operations for multiple vectors:

```ruby
# ❌ Slow: Individual upserts
vectors.each { |v| client.upsert(vectors: [v]) }

# ✅ Fast: Batch upsert
client.upsert(vectors: vectors)
```

### 2. Normalize Embeddings

Normalize embeddings for better cosine similarity:

```ruby
embedding = EmbeddingService.generate(text)
normalized = Vectra::Vector.normalize(embedding)
client.upsert(vectors: [{ id: 'doc-1', values: normalized }])
```

### 3. Use Metadata Filters

Filter in the vector database, not in Ruby:

```ruby
# ❌ Slow: Filter in Ruby
results = client.query(...)
filtered = results.select { |r| r.metadata[:category] == 'electronics' }

# ✅ Fast: Filter in database
results = client.query(
  vector: embedding,
  filter: { category: 'electronics' }
)
```

### 4. Connection Pooling

For pgvector, use connection pooling:

```ruby
Vectra.configure do |config|
  config.provider = :pgvector
  config.pool_size = 10 # Adjust based on your load
end
```

### 5. Caching Frequent Queries

Enable caching for repeated queries:

```ruby
Vectra.configure do |config|
  config.cache_enabled = true
  config.cache_ttl = 3600 # 1 hour
end
```

---

## Next Steps

- [Rails Integration Guide](/guides/rails-integration/) - Complete Rails setup
- [Performance Guide](/guides/performance/) - Optimization strategies
- [API Reference](/api/overview/) - Full API documentation
