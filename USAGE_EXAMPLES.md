# 💡 PRACTICAL USAGE EXAMPLES

Real-world examples of using Vectra in production applications.

## Table of Contents

- [Setup & Installation](#setup--installation)
- [E-Commerce Semantic Search](#e-commerce-semantic-search)
- [RAG Chatbot](#rag-chatbot-retrieval-augmented-generation)
- [Duplicate Detection](#duplicate-detection)
- [Rails ActiveRecord Integration](#rails-activerecord-integration)
- [Instrumentation & Monitoring](#instrumentation--monitoring)

---

## Setup & Installation

### Rails Application

```bash
# Add to Gemfile
gem 'vectra'
gem 'pg' #  For pgvector support

# Install
bundle install

# Run generator
rails generate vectra:install --provider=pgvector --instrumentation=true

# Run migrations
rails db:migrate
```

### Standalone Ruby

```bash
gem install vectra
```

---

## E-Commerce Semantic Search

Build intelligent product search that understands user intent beyond keywords.

### 1. Setup Service

```ruby
# app/services/product_search_service.rb
class ProductSearchService
  def initialize
    @vectra = Vectra.pgvector(
      connection_url: ENV['DATABASE_URL'],
      pool_size: 10,
      batch_size: 500
    )
    @embedding_client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
  end

  # Index all products (run once, or in background job)
  def index_all_products
    Product.find_in_batches(batch_size: 500) do |batch|
      index_products(batch)
    end
  end

  # Index batch of products
  def index_products(products)
    vectors = products.map do |product|
      # Combine multiple fields for better search
      search_text = [
        product.name,
        product.description,
        product.category,
        product.tags.join(', ')
      ].compact.join(' ')

      {
        id: "product_#{product.id}",
        values: generate_embedding(search_text),
        metadata: {
          name: product.name,
          price: product.price.to_f,
          category: product.category,
          in_stock: product.in_stock?,
          rating: product.average_rating,
          image_url: product.image_url
        }
      }
    end

    @vectra.upsert(index: 'products', vectors: vectors)
  end

  # Semantic search with filters
  def search(query, category: nil, min_price: nil, max_price: nil, in_stock_only: true, limit: 20)
    embedding = generate_embedding(query)

    # Build metadata filter
    filter = {}
    filter[:category] = category if category
    filter[:in_stock] = true if in_stock_only

    # Query vectors
    results = @vectra.query(
      index: 'products',
      vector: embedding,
      top_k: limit * 2,  # Fetch more for post-filtering
      filter: filter
    )

    # Post-filter by price (or add to SQL in future)
    results = results.select { |r| r.metadata['price'] >= min_price } if min_price
    results = results.select { |r| r.metadata['price'] <= max_price } if max_price

    # Transform to product objects
    results.first(limit).map do |match|
      {
        product_id: match.id.gsub('product_', '').to_i,
        similarity_score: match.score,
        name: match.metadata['name'],
        price: match.metadata['price'],
        category: match.metadata['category'],
        rating: match.metadata['rating'],
        image_url: match.metadata['image_url']
      }
    end
  end

  # Recommend similar products
  def similar_products(product_id, limit: 10)
    product = Product.find(product_id)
    search_text = "#{product.name} #{product.description}"

    search(search_text, category: product.category, limit: limit + 1)
      .reject { |p| p[:product_id] == product_id }
      .first(limit)
  end

  private

  def generate_embedding(text)
    response = @embedding_client.embeddings(
      parameters: {
        model: 'text-embedding-3-small',
        input: text.truncate(8000)  # OpenAI limit
      }
    )
    response.dig('data', 0, 'embedding')
  rescue => e
    Rails.logger.error("Embedding generation failed: #{e.message}")
    raise
  end
end
```

### 2. Controller

```ruby
# app/controllers/search_controller.rb
class SearchController < ApplicationController
  def index
    @query = params[:q]

    if @query.present?
      service = ProductSearchService.new
      @results = service.search(
        @query,
        category: params[:category],
        min_price: params[:min_price]&.to_f,
        max_price: params[:max_price]&.to_f,
        in_stock_only: params[:in_stock] != 'false',
        limit: 50
      )
    else
      @results = []
    end
  end
end
```

### 3. Background Job (Index Products)

```ruby
# app/jobs/index_products_job.rb
class IndexProductsJob < ApplicationJob
  queue_as :default

  def perform(*product_ids)
    products = Product.where(id: product_ids)
    ProductSearchService.new.index_products(products)
  end
end

# In Product model
class Product < ApplicationRecord
  after_commit :reindex_in_vectra, on: [:create, :update]

  private

  def reindex_in_vectra
    IndexProductsJob.perform_later(id)
  end
end
```

---

## RAG Chatbot (Retrieval Augmented Generation)

Build a chatbot that answers questions using your documentation.

### 1. Setup Service

```ruby
# app/services/rag_service.rb
class RagService
  CHUNK_SIZE = 512  # tokens per chunk
  OVERLAP = 50      # token overlap between chunks

  def initialize
    @vectra = Vectra.pgvector(connection_url: ENV['DATABASE_URL'])
    @openai = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
  end

  # Index documentation (run once or when docs update)
  def index_documentation
    Documentation.find_each do |doc|
      index_document(doc)
    end
  end

  # Index single document
  def index_document(doc)
    chunks = chunk_text(doc.content, max_tokens: CHUNK_SIZE)

    vectors = chunks.map.with_index do |chunk, idx|
      {
        id: "doc_#{doc.id}_chunk_#{idx}",
        values: generate_embedding(chunk),
        metadata: {
          doc_id: doc.id,
          title: doc.title,
          chunk_index: idx,
          total_chunks: chunks.size,
          text: chunk,
          url: doc.url,
          category: doc.category,
          last_updated: doc.updated_at.iso8601
        }
      }
    end

    @vectra.upsert(index: 'documentation', vectors: vectors)
  end

  # Answer question using RAG
  def answer_question(question, max_context_chunks: 5)
    # 1. Find relevant context
    question_embedding = generate_embedding(question)

    results = @vectra.query(
      index: 'documentation',
      vector: question_embedding,
      top_k: max_context_chunks,
      include_metadata: true
    )

    return no_context_response if results.empty?

    # 2. Build context from chunks
    context = results.map { |r| r.metadata['text'] }.join("\n\n---\n\n")
    sources = results.map do |r|
      {
        title: r.metadata['title'],
        url: r.metadata['url'],
        relevance: r.score
      }
    end.uniq { |s| s[:url] }

    # 3. Generate answer with GPT
    prompt = build_prompt(question, context)

    answer = @openai.chat(
      parameters: {
        model: 'gpt-4-turbo-preview',
        messages: [
          { role: 'system', content: system_message },
          { role: 'user', content: prompt }
        ],
        temperature: 0.3  # Lower = more deterministic
      }
    ).dig('choices', 0, 'message', 'content')

    {
      answer: answer,
      sources: sources,
      context_used: results.size
    }
  rescue => e
    Rails.logger.error("RAG answer failed: #{e.message}")
    {
      answer: "I'm sorry, I encountered an error while processing your question.",
      sources: [],
      error: e.message
    }
  end

  # Streaming version for real-time UI
  def answer_question_streaming(question, &block)
    # Similar to above, but use streaming:
    @openai.chat(
      parameters: {
        model: 'gpt-4-turbo-preview',
        messages: [...],
        stream: proc do |chunk, _bytesize|
          content = chunk.dig('choices', 0, 'delta', 'content')
          block.call(content) if content
        end
      }
    )
  end

  private

  def chunk_text(text, max_tokens: 512)
    # Simple sentence-based chunking
    # Production: use tiktoken for accurate token counting
    sentences = text.split(/(?<=[.!?])\s+/)
    chunks = []
    current_chunk = []
    current_length = 0

    sentences.each do |sentence|
      # Rough approximation: 1 token ≈ 4 characters
      sentence_tokens = sentence.length / 4

      if current_length + sentence_tokens > max_tokens && current_chunk.any?
        chunks << current_chunk.join(' ')
        # Keep last sentence for overlap
        current_chunk = [current_chunk.last]
        current_length = current_chunk.last.length / 4
      end

      current_chunk << sentence
      current_length += sentence_tokens
    end

    chunks << current_chunk.join(' ') if current_chunk.any?
    chunks
  end

  def build_prompt(question, context)
    <<~PROMPT
      Context from documentation:
      #{context}

      Question: #{question}

      Please answer the question based on the context provided above. If the context doesn't contain enough information to answer the question, say so clearly.
    PROMPT
  end

  def system_message
    <<~SYSTEM
      You are a helpful AI assistant that answers questions based on documentation.
      Use the provided context to answer questions accurately.
      If you're not sure or the context doesn't contain the answer, say so.
      Format your answers clearly with markdown when appropriate.
    SYSTEM
  end

  def no_context_response
    {
      answer: "I couldn't find relevant information in the documentation to answer your question.",
      sources: [],
      context_used: 0
    }
  end

  def generate_embedding(text)
    response = @openai.embeddings(
      parameters: {
        model: 'text-embedding-3-small',
        input: text.truncate(8000)
      }
    )
    response.dig('data', 0, 'embedding')
  end
end
```

### 2. Controller

```ruby
# app/controllers/chat_controller.rb
class ChatController < ApplicationController
  def ask
    question = params[:question]
    rag = RagService.new
    @result = rag.answer_question(question)

    render json: @result
  end

  # Streaming version
  def ask_streaming
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['X-Accel-Buffering'] = 'no'

    question = params[:question]
    rag = RagService.new

    rag.answer_question_streaming(question) do |chunk|
      response.stream.write("data: #{chunk}\n\n")
    end
  ensure
    response.stream.close
  end
end
```

---

## Duplicate Detection

Automatically detect duplicate support tickets, articles, or user submissions.

### Service

```ruby
# app/services/duplicate_detector.rb
class DuplicateDetector
  SIMILARITY_THRESHOLD = 0.92  # 92% similar = likely duplicate

  def initialize
    @vectra = Vectra.pgvector(connection_url: ENV['DATABASE_URL'])
    @openai = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
  end

  # Find potential duplicates
  def find_duplicates(ticket)
    embedding = generate_embedding(ticket.description)

    results = @vectra.query(
      index: 'support_tickets',
      vector: embedding,
      top_k: 20,
      filter: { status: ['open', 'in_progress'] }  # Only open tickets
    )

    # Filter by similarity threshold
    results
      .above_score(SIMILARITY_THRESHOLD)
      .reject { |match| match.id == "ticket_#{ticket.id}" }  # Exclude self
      .map do |match|
        {
          ticket_id: match.id.gsub('ticket_', '').to_i,
          similarity: (match.score * 100).round(1),
          title: match.metadata['title'],
          created_at: match.metadata['created_at'],
          status: match.metadata['status']
        }
      end
  end

  # Index ticket for future duplicate detection
  def index_ticket(ticket)
    @vectra.upsert(
      index: 'support_tickets',
      vectors: [{
        id: "ticket_#{ticket.id}",
        values: generate_embedding(ticket.description),
        metadata: {
          title: ticket.title,
          status: ticket.status,
          category: ticket.category,
          priority: ticket.priority,
          created_at: ticket.created_at.iso8601
        }
      }]
    )
  end

  # Update ticket status in index
  def update_ticket_status(ticket)
    @vectra.update(
      index: 'support_tickets',
      id: "ticket_#{ticket.id}",
      metadata: {
        status: ticket.status
      }
    )
  end

  private

  def generate_embedding(text)
    response = @openai.embeddings(
      parameters: {
        model: 'text-embedding-3-small',
        input: text.truncate(8000)
      }
    )
    response.dig('data', 0, 'embedding')
  end
end
```

### Model Integration

```ruby
# app/models/support_ticket.rb
class SupportTicket < ApplicationRecord
  after_create :index_in_vectra
  after_update :update_vectra_status, if: :saved_change_to_status?

  def check_duplicates
    DuplicateDetector.new.find_duplicates(self)
  end

  private

  def index_in_vectra
    DuplicateDetectorJob.perform_later(id, :index)
  end

  def update_vectra_status
    DuplicateDetectorJob.perform_later(id, :update_status)
  end
end
```

---

## Rails ActiveRecord Integration

Simplest way to add vector search to your Rails models.

### 1. Setup Model

```ruby
# app/models/document.rb
class Document < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding,
             dimension: 384,
             provider: :pgvector,
             index: 'documents',
             auto_index: true,  # Auto-index on save
             metadata_fields: [:title, :category, :status, :user_id]

  # Generate embedding before validation
  before_validation :generate_embedding, if: :content_changed?

  private

  def generate_embedding
    self.embedding = EmbeddingService.generate(content)
  end
end
```

### 2. Usage

```ruby
# Create document (automatically indexed)
doc = Document.create!(
  title: 'Getting Started Guide',
  content: 'This guide will help you...',
  category: 'tutorial',
  status: 'published'
)

# Search similar documents
query_vector = EmbeddingService.generate('how to get started')
results = Document.vector_search(query_vector, limit: 10)

# Each result has vector_score
results.each do |doc|
  puts "#{doc.title} - Score: #{doc.vector_score}"
end

# Find similar to a specific document
similar = doc.similar(limit: 5)

# Search with filters
results = Document.vector_search(
  query_vector,
  limit: 10,
  filter: { category: 'tutorial', status: 'published' }
)

# Manual control
doc.index_vector!   # Manually index
doc.delete_vector!  # Remove from index
```

---

## Instrumentation & Monitoring

Track performance and errors in production.

### New Relic Integration

```ruby
# config/initializers/vectra.rb
require 'vectra/instrumentation/new_relic'

Vectra.configure do |config|
  config.instrumentation = true
end

Vectra::Instrumentation::NewRelic.setup!
```

This automatically tracks:
- `Custom/Vectra/:provider/:operation/duration` - Operation latency
- `Custom/Vectra/:provider/:operation/calls` - Call counts
- `Custom/Vectra/:provider/:operation/success` - Success count
- `Custom/Vectra/:provider/:operation/error` - Error count
- `Custom/Vectra/:provider/:operation/results` - Result counts

### Datadog Integration

```ruby
# config/initializers/vectra.rb
require 'vectra/instrumentation/datadog'

Vectra.configure do |config|
  config.instrumentation = true
end

Vectra::Instrumentation::Datadog.setup!(
  host: ENV['DD_AGENT_HOST'] || 'localhost',
  port: ENV['DD_DOGSTATSD_PORT']&.to_i || 8125
)
```

Metrics sent to Datadog:
- `vectra.operation.duration` (timing)
- `vectra.operation.count` (counter)
- `vectra.operation.results` (gauge)
- `vectra.operation.error` (counter)

Tags: `provider`, `operation`, `index`, `status`, `error_type`

### Custom Instrumentation

```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.instrumentation = true
end

# Log to Rails logger
Vectra.on_operation do |event|
  Rails.logger.info(
    "Vectra: #{event.operation} on #{event.provider}/#{event.index} " \
    "took #{event.duration}ms (#{event.success? ? 'success' : 'error'})"
  )

  if event.failure?
    Rails.logger.error("Vectra error: #{event.error.class} - #{event.error.message}")
  end

  # Send to custom metrics service
  MetricsService.timing("vectra.#{event.operation}", event.duration)
  MetricsService.increment("vectra.#{event.success? ? 'success' : 'error'}")
end

# Track slow operations
Vectra.on_operation do |event|
  if event.duration > 1000  # > 1 second
    SlackNotifier.notify(
      "Slow Vectra operation: #{event.operation} took #{event.duration}ms",
      channel: '#performance-alerts'
    )
  end
end
```

---

## Performance Tips

### 1. Connection Pooling (pgvector)

```ruby
Vectra.configure do |config|
  config.pool_size = 20        # Match your app server threads
  config.pool_timeout = 5      # Seconds to wait for connection
  config.batch_size = 500      # Larger batches = fewer DB calls
end
```

### 2. Batch Operations

```ruby
# ❌ Bad: Individual inserts
products.each do |product|
  service.index_products([product])
end

# ✅ Good: Batch inserts
products.in_batches(of: 500) do |batch|
  service.index_products(batch)
end
```

### 3. Background Jobs

```ruby
# ❌ Bad: Synchronous indexing in request
def create
  @product = Product.create!(product_params)
  ProductSearchService.new.index_products([@product])  # Blocks request!
  redirect_to @product
end

# ✅ Good: Async indexing
def create
  @product = Product.create!(product_params)
  IndexProductJob.perform_later(@product.id)
  redirect_to @product
end
```

### 4. Caching Embeddings

```ruby
# Cache expensive embedding generations
def generate_embedding(text)
  cache_key = "embedding:#{Digest::MD5.hexdigest(text)}"

  Rails.cache.fetch(cache_key, expires_in: 1.week) do
    @openai.embeddings(parameters: { model: 'text-embedding-3-small', input: text })
      .dig('data', 0, 'embedding')
  end
end
```

---

## Troubleshooting

### High Memory Usage

```ruby
# Use find_in_batches for large datasets
Product.find_in_batches(batch_size: 100) do |batch|
  service.index_products(batch)
  GC.start  # Force garbage collection between batches
end
```

### Connection Pool Exhausted

```ruby
# Increase pool size or reduce parallelism
Vectra.configure do |config|
  config.pool_size = 50  # Increase if needed
  config.pool_timeout = 10  # Wait longer
end

# Check pool stats
client.provider.pool_stats
# => { size: 50, available: 45, pending: 0 }
```

### Slow Queries

```ruby
# Add indexes in PostgreSQL
CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);  # Tune based on data size

# Monitor with instrumentation
Vectra.on_operation do |event|
  if event.operation == :query && event.duration > 500
    Rails.logger.warn("Slow query: #{event.duration}ms on #{event.index}")
  end
end
```
