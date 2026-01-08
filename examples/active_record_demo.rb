#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo of Vectra ActiveRecord integration
#
# Usage: ruby examples/active_record_demo.rb

require 'bundler/setup'
require 'active_record'
require 'vectra'

puts "=" * 80
puts "VECTRA ACTIVERECORD INTEGRATION DEMO"
puts "=" * 80
puts

# Setup database connection
ActiveRecord::Base.establish_connection(
  adapter: 'postgresql',
  database: ENV.fetch('DATABASE_NAME', 'vectra_demo'),
  host: ENV.fetch('DATABASE_HOST', 'localhost'),
  username: ENV.fetch('DATABASE_USER', 'postgres'),
  password: ENV.fetch('DATABASE_PASSWORD', 'password')
)

# Configure Vectra
Vectra.configure do |config|
  config.provider = :pgvector
  config.host = ENV.fetch('DATABASE_URL', 'postgres://postgres:password@localhost/vectra_demo')
end

# Create documents table if not exists
ActiveRecord::Schema.define do
  unless ActiveRecord::Base.connection.table_exists?('documents')
    enable_extension 'vector'

    create_table :documents do |t|
      t.string :title
      t.text :content
      t.string :category
      t.string :status
      t.column :embedding, :vector, limit: 3  # 3-dimensional for demo
      t.timestamps
    end
  end
end

# Define Document model with vector search
class Document < ActiveRecord::Base
  include Vectra::ActiveRecord

  has_vector :embedding,
             dimension: 3,
             provider: :pgvector,
             index: 'documents',
             auto_index: true,
             metadata_fields: [:title, :category, :status]

  # Generate embedding before validation
  # In production, use OpenAI/Cohere/etc.
  before_validation :generate_embedding, if: -> { content.present? && embedding.nil? }

  private

  def generate_embedding
    # Simple deterministic embedding for demo
    # In production: self.embedding = OpenAI.embed(content)
    hash = content.hash.abs
    self.embedding = [
      (hash % 1000) / 1000.0,
      ((hash / 1000) % 1000) / 1000.0,
      ((hash / 1_000_000) % 1000) / 1000.0
    ]
  end
end

# Create pgvector index
puts "Creating vector index..."
begin
  Vectra::Client.new.provider.create_index(
    name: 'documents',
    dimension: 3,
    metric: 'cosine'
  )
  puts "✅ Index created\n"
rescue => e
  puts "⚠️  Index might already exist: #{e.message}\n"
end

puts "\n" + "=" * 80
puts "TESTING ACTIVERECORD INTEGRATION"
puts "=" * 80
puts

# Clean up existing data
Document.delete_all

# Test 1: Create document (auto-indexes)
puts "1. Creating documents (auto-indexes on save)...\n"

doc1 = Document.create!(
  title: 'Getting Started Guide',
  content: 'This guide will help you get started with our platform.',
  category: 'tutorial',
  status: 'published'
)
puts "   Created: #{doc1.title} (ID: #{doc1.id})"
puts "   Embedding: #{doc1.embedding.map { |v| v.round(3) }}"
puts "   ✅ Automatically indexed in Vectra\n\n"

doc2 = Document.create!(
  title: 'Advanced Features',
  content: 'Learn about advanced features and best practices.',
  category: 'tutorial',
  status: 'published'
)
puts "   Created: #{doc2.title} (ID: #{doc2.id})\n\n"

doc3 = Document.create!(
  title: 'API Reference',
  content: 'Complete API documentation for developers.',
  category: 'reference',
  status: 'published'
)
puts "   Created: #{doc3.title} (ID: #{doc3.id})\n\n"

sleep 0.5

# Test 2: Vector search
puts "2. Vector search (finds similar documents)...\n"

query_embedding = [0.5, 0.5, 0.5]
results = Document.vector_search(query_embedding, limit: 5)

puts "   Query: #{query_embedding.inspect}"
puts "   Found #{results.size} results:\n\n"

results.each_with_index do |doc, idx|
  puts "   #{idx + 1}. #{doc.title}"
  puts "      Score: #{doc.vector_score.round(3)}"
  puts "      Category: #{doc.category}"
  puts
end

# Test 3: Search with filters
puts "3. Vector search with metadata filter...\n"

results = Document.vector_search(
  query_embedding,
  limit: 10,
  filter: { category: 'tutorial' }
)

puts "   Filter: category='tutorial'"
puts "   Found #{results.size} results:\n"
results.each { |doc| puts "      • #{doc.title}" }
puts

# Test 4: Find similar documents
puts "4. Find similar to specific document...\n"

similar = doc1.similar(limit: 2)

puts "   Document: '#{doc1.title}'"
puts "   Similar documents:\n"
similar.each do |doc|
  puts "      • #{doc.title} (score: #{doc.vector_score.round(3)})"
end
puts

# Test 5: Update triggers re-indexing
puts "5. Update document (triggers re-indexing)...\n"

doc1.update!(content: 'Updated content about getting started.')
puts "   Updated: #{doc1.title}"
puts "   New embedding: #{doc1.embedding.map { |v| v.round(3) }}"
puts "   ✅ Automatically re-indexed\n\n"

# Test 6: Manual index control
puts "6. Manual index control...\n"

doc4 = Document.new(
  title: 'Draft Article',
  content: 'This is a draft article.',
  category: 'blog',
  status: 'draft'
)
doc4.save!(validate: false)  # Skip auto-index

puts "   Created without auto-index: #{doc4.title}"
puts "   Manually indexing..."

doc4.index_vector!
puts "   ✅ Manually indexed\n\n"

# Test 7: Delete removes from index
puts "7. Delete document (removes from index)...\n"

doc4.destroy!
puts "   ✅ Deleted and removed from vector index\n\n"

# Cleanup
puts "=" * 80
puts "SUMMARY"
puts "=" * 80
puts

puts "ActiveRecord Integration Features:"
puts "  ✅ Automatic indexing on create/update"
puts "  ✅ Automatic removal on delete"
puts "  ✅ Vector search with AR object loading"
puts "  ✅ Metadata filtering"
puts "  ✅ Find similar documents"
puts "  ✅ Manual index control"
puts "  ✅ Custom embedding generation"
puts

puts "Total documents in database: #{Document.count}"
puts "Total documents in vector index: (same, auto-synced)"
puts

puts "✅ Demo complete!"
puts "\nNext steps:"
puts "  • Replace embedding generation with real model (OpenAI, Cohere, etc.)"
puts "  • Add background job for async indexing"
puts "  • Use higher dimensions (384, 768, 1536)"
puts "  • Add score threshold filtering"
