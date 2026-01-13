---
layout: page
title: Rails Integration Guide
permalink: /guides/rails-integration/
---

# Rails Integration Guide

Complete step-by-step guide to integrate Vectra into your Rails application with vector search capabilities.

## Overview

This guide will walk you through:
1. Installing Vectra in a Rails app
2. Setting up a Product model with vector search
3. Generating embeddings for 1000 products
4. Performing vector searches
5. Using all Vectra features

## Step 1: Installation

### Add Vectra to your Gemfile

```ruby
# Gemfile
gem 'vectra-client'
```

```bash
bundle install
```

### Run the Install Generator

```bash
rails generate vectra:install
```

This creates:
- `config/initializers/vectra.rb` - Configuration file
- `db/migrate/XXXXXX_enable_pgvector_extension.rb` - pgvector extension (if using pgvector)

## Step 2: Configure Vectra

### Option A: Using pgvector (PostgreSQL)

```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.provider = :pgvector
  config.host = Rails.application.config.database_configuration[Rails.env]['database']
  # Or use connection URL:
  # config.host = ENV['DATABASE_URL']
end
```

### Option B: Using Qdrant

```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.provider = :qdrant
  config.host = ENV.fetch('QDRANT_HOST', 'http://localhost:6333')
  config.api_key = ENV['QDRANT_API_KEY'] # Optional for local instances
end
```

### Option C: Using Pinecone

```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.provider = :pinecone
  config.api_key = ENV['PINECONE_API_KEY']
  config.environment = ENV['PINECONE_ENVIRONMENT'] # e.g., 'us-west-4'
end
```

## Step 3: Create Product Model with Vector Search

### Generate the Model and Migration

```bash
rails generate model Product name:string description:text price:decimal category:string
rails generate vectra:index Product embedding dimension:1536 provider:qdrant
```

This will:
- Create a migration for the `embedding` column (if `provider=pgvector`)
- Generate `app/models/concerns/product_vector.rb` with `has_vector` configuration
- Update `app/models/product.rb` to include the concern
- Add configuration to `config/vectra.yml`

### Run Migrations

```bash
rails db:migrate
```

### Manual Setup (Alternative)

If you prefer manual setup:

```ruby
# db/migrate/XXXXXX_create_products.rb
class CreateProducts < ActiveRecord::Migration[7.0]
  def change
    create_table :products do |t|
      t.string :name
      t.text :description
      t.decimal :price
      t.string :category
      # For pgvector, add vector column:
      # t.column :embedding, :vector, limit: 1536
      t.timestamps
    end
  end
end
```

```ruby
# app/models/concerns/product_vector.rb
module ProductVector
  extend ActiveSupport::Concern

  included do
    include Vectra::ActiveRecord

    has_vector :embedding,
               provider: :qdrant,
               index: 'products',
               dimension: 1536,
               auto_index: true,
               metadata_fields: [:name, :category, :price]
  end
end
```

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  include ProductVector

  # Generate embedding before validation
  before_validation :generate_embedding, if: -> { description.present? && embedding.nil? }

  private

  def generate_embedding
    # Use OpenAI, Cohere, or any embedding service
    self.embedding = generate_embedding_from_text(description)
  end

  def generate_embedding_from_text(text)
    # Example with OpenAI (install 'ruby-openai' gem)
    # client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
    # response = client.embeddings(
    #   parameters: {
    #     model: 'text-embedding-3-small',
    #     input: text
    #   }
    # )
    # response.dig('data', 0, 'embedding')
    
    # For demo purposes, use a simple hash-based embedding
    # In production, use a real embedding service!
    hash = text.hash.abs
    Array.new(1536) { |i| ((hash * (i + 1)) % 1000) / 1000.0 }
  end
end
```

## Step 4: Generate Embeddings for Products

### Using OpenAI (Recommended)

First, add the OpenAI gem:

```ruby
# Gemfile
gem 'ruby-openai'
```

```bash
bundle install
```

Then create a service:

```ruby
# app/services/embedding_service.rb
class EmbeddingService
  def self.generate(text)
    client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
    response = client.embeddings(
      parameters: {
        model: 'text-embedding-3-small', # 1536 dimensions
        input: text
      }
    )
    
    embedding = response.dig('data', 0, 'embedding')
    Vectra::Vector.normalize(embedding) # Normalize for better cosine similarity
  end
end
```

Update your Product model:

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  include ProductVector

  before_validation :generate_embedding, if: -> { description.present? && embedding.nil? }

  private

  def generate_embedding
    self.embedding = EmbeddingService.generate(description)
  end
end
```

### Using Cohere

```ruby
# Gemfile
gem 'cohere-rb'
```

```ruby
# app/services/embedding_service.rb
class EmbeddingService
  def self.generate(text)
    client = Cohere::Client.new(api_key: ENV['COHERE_API_KEY'])
    response = client.embed(
      texts: [text],
      model: 'embed-english-v3.0',
      input_type: 'search_document'
    )
    
    embedding = response.dig('embeddings', 0)
    Vectra::Vector.normalize(embedding)
  end
end
```

### Batch Processing for 1000 Products

Create a rake task to process all products:

```ruby
# lib/tasks/vectra.rake
namespace :vectra do
  desc "Generate embeddings for all products without embeddings"
  task generate_embeddings: :environment do
    products = Product.where(embedding: nil).where.not(description: nil)
    total = products.count
    
    puts "Generating embeddings for #{total} products..."
    
    products.find_each.with_index do |product, index|
      begin
        product.generate_embedding!
        product.save!
        
        if (index + 1) % 100 == 0
          puts "Processed #{index + 1}/#{total} products..."
        end
      rescue => e
        puts "Error processing product #{product.id}: #{e.message}"
      end
    end
    
    puts "✅ Completed! Generated embeddings for #{Product.where.not(embedding: nil).count} products"
  end
  
  desc "Re-index all products in vector database"
  task reindex: :environment do
    products = Product.where.not(embedding: nil)
    total = products.count
    
    puts "Re-indexing #{total} products..."
    
    products.find_each.with_index do |product, index|
      begin
        product.index_vector!
        
        if (index + 1) % 100 == 0
          puts "Indexed #{index + 1}/#{total} products..."
        end
      rescue => e
        puts "Error indexing product #{product.id}: #{e.message}"
      end
    end
    
    puts "✅ Completed! Re-indexed #{total} products"
  end
end
```

Run the task:

```bash
rails vectra:generate_embeddings
```

## Step 5: Create the Vector Index

### For Qdrant/Pinecone/Weaviate

```ruby
# rails console
client = Vectra::Client.new
client.provider.create_index(
  name: 'products',
  dimension: 1536,
  metric: 'cosine'
)
```

### For pgvector

The index is created automatically via migration, but you can also create it manually:

```ruby
# db/migrate/XXXXXX_add_vector_index_to_products.rb
class AddVectorIndexToProducts < ActiveRecord::Migration[7.0]
  def change
    add_index :products, :embedding, 
              using: :ivfflat, 
              with: { lists: 100 },
              opclass: :vector_cosine_ops
  end
end
```

## Step 6: Using Vector Search

### Basic Search

```ruby
# In your controller or service
class ProductsController < ApplicationController
  def search
    query_text = params[:query]
    
    # Generate embedding for search query
    query_embedding = EmbeddingService.generate(query_text)
    
    # Search for similar products
    results = Product.vector_search(query_embedding, limit: 10)
    
    render json: results.map { |p| 
      { 
        id: p.id, 
        name: p.name, 
        score: p.vector_score,
        price: p.price 
      } 
    }
  end
end
```

### Search with Metadata Filters

```ruby
# Search only in specific category
results = Product.vector_search(
  query_embedding,
  limit: 10,
  filter: { category: 'electronics' }
)

# Search with price range (if using Qdrant/Weaviate)
results = Product.vector_search(
  query_embedding,
  limit: 10,
  filter: { 
    category: 'electronics',
    price: { gte: 100, lte: 500 }
  }
)
```

### Hybrid Search (Semantic + Keyword)

```ruby
# Search combining semantic similarity and keyword matching
query_embedding = EmbeddingService.generate(params[:query])

results = Product.vectra_client.hybrid_search(
  index: 'products',
  vector: query_embedding,
  text: params[:query],
  alpha: 0.7, # 70% semantic, 30% keyword
  top_k: 10
)

# Convert results to Product objects
product_ids = results.map(&:id)
products = Product.where(id: product_ids).index_by(&:id)
results_with_products = results.map do |result|
  product = products[result.id]
  product&.vector_score = result.score
  product
end.compact
```

### Find Similar Products

```ruby
# Find products similar to a specific product
product = Product.find(params[:id])
similar = Product.similar_to(product, limit: 5)

similar.each do |p|
  puts "#{p.name} (similarity: #{p.vector_score})"
end
```

## Step 7: Advanced Features

### Background Job for Embedding Generation

```ruby
# app/jobs/generate_embedding_job.rb
class GenerateEmbeddingJob < ApplicationJob
  queue_as :default

  def perform(product_id)
    product = Product.find(product_id)
    return if product.embedding.present?
    
    product.generate_embedding!
    product.save!
  end
end
```

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  include ProductVector

  after_create :enqueue_embedding_generation, if: -> { description.present? }

  private

  def enqueue_embedding_generation
    GenerateEmbeddingJob.perform_later(id)
  end
end
```

### Batch Upsert for Performance

```ruby
# app/services/product_indexer.rb
class ProductIndexer
  def self.batch_index(products)
    vectors = products.map do |product|
      {
        id: product.id.to_s,
        values: product.embedding,
        metadata: {
          name: product.name,
          category: product.category,
          price: product.price.to_f
        }
      }
    end
    
    client = Vectra::Client.new
    client.upsert(
      index: 'products',
      vectors: vectors
    )
  end
end

# Usage
products = Product.where.not(embedding: nil).limit(100)
ProductIndexer.batch_index(products)
```

### Using Callbacks for Progress Tracking

```ruby
# Batch upsert with progress callback
client = Vectra::Client.new

client.upsert(
  index: 'products',
  vectors: vectors,
  on_progress: ->(progress) {
    puts "Progress: #{progress[:processed]}/#{progress[:total]} (#{progress[:percentage]}%)"
  }
)
```

## Step 8: Complete Example: Products Controller

```ruby
# app/controllers/products_controller.rb
class ProductsController < ApplicationController
  def index
    @products = Product.all.page(params[:page])
  end

  def show
    @product = Product.find(params[:id])
    @similar = Product.similar_to(@product, limit: 4)
  end

  def search
    query = params[:q]
    return render json: [] if query.blank?
    
    # Generate embedding for query
    query_embedding = EmbeddingService.generate(query)
    
    # Vector search
    results = Product.vector_search(
      query_embedding,
      limit: 20,
      filter: params[:category].present? ? { category: params[:category] } : nil
    )
    
    render json: {
      query: query,
      results: results.map { |p|
        {
          id: p.id,
          name: p.name,
          description: p.description,
          price: p.price,
          category: p.category,
          similarity_score: p.vector_score.round(4)
        }
      }
    }
  end

  def create
    @product = Product.new(product_params)
    
    if @product.save
      # Embedding is generated automatically via before_validation
      # and indexed automatically via after_save (auto_index: true)
      render json: @product, status: :created
    else
      render json: @product.errors, status: :unprocessable_entity
    end
  end

  private

  def product_params
    params.require(:product).permit(:name, :description, :price, :category)
  end
end
```

## Step 9: Testing

```ruby
# spec/models/product_spec.rb
RSpec.describe Product, type: :model do
  describe 'vector search' do
    let!(:product1) do
      Product.create!(
        name: 'Laptop',
        description: 'High-performance laptop for developers',
        price: 1299.99,
        category: 'electronics',
        embedding: Array.new(1536) { rand }
      )
    end

    let!(:product2) do
      Product.create!(
        name: 'Desktop PC',
        description: 'Powerful desktop computer for gaming',
        price: 1999.99,
        category: 'electronics',
        embedding: Array.new(1536) { rand }
      )
    end

    it 'finds similar products' do
      query_vector = product1.embedding
      results = Product.vector_search(query_vector, limit: 5)
      
      expect(results).to include(product1)
      expect(results.first.vector_score).to be > 0
    end

    it 'filters by category' do
      query_vector = product1.embedding
      results = Product.vector_search(
        query_vector,
        limit: 10,
        filter: { category: 'electronics' }
      )
      
      expect(results.all? { |p| p.category == 'electronics' }).to be true
    end
  end
end
```

## Step 10: Performance Tips

### 1. Use Connection Pooling (pgvector)

```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.provider = :pgvector
  config.pool_size = 10 # Connection pool size
end
```

### 2. Enable Caching

```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.cache_enabled = true
  config.cache_ttl = 3600 # 1 hour
end
```

### 3. Batch Operations

Always use batch operations when processing multiple products:

```ruby
# Good: Batch upsert
Product.where.not(embedding: nil).find_in_batches(batch_size: 100) do |batch|
  vectors = batch.map { |p| { id: p.id.to_s, values: p.embedding } }
  Vectra::Client.new.upsert(index: 'products', vectors: vectors)
end

# Bad: Individual upserts
Product.where.not(embedding: nil).each do |product|
  Vectra::Client.new.upsert(
    index: 'products',
    vectors: [{ id: product.id.to_s, values: product.embedding }]
  )
end
```

## Summary

You now have a complete Rails application with:
- ✅ Vector search for products
- ✅ Automatic embedding generation
- ✅ Automatic indexing on save
- ✅ Search with metadata filters
- ✅ Hybrid search (semantic + keyword)
- ✅ Batch processing for 1000+ products
- ✅ Background jobs for async processing

## Next Steps

- [API Reference]({{ site.baseurl }}/api/overview)
- [Provider Guides]({{ site.baseurl }}/providers)
- [Performance Optimization]({{ site.baseurl }}/guides/performance)
