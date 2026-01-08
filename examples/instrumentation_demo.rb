#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo of Vectra instrumentation features
#
# Usage: ruby examples/instrumentation_demo.rb

require 'bundler/setup'
require 'vectra'

puts "=" * 80
puts "VECTRA INSTRUMENTATION DEMO"
puts "=" * 80
puts

# Configure Vectra with instrumentation
Vectra.configure do |config|
  config.provider = :pgvector
  config.host = ENV.fetch('DATABASE_URL', 'postgres://postgres:password@localhost/vectra_demo')
  config.instrumentation = true  # Enable instrumentation
  config.pool_size = 5
  config.batch_size = 100
  config.max_retries = 3
  config.retry_delay = 0.5
end

# Register custom instrumentation handler
puts "Registering custom instrumentation handler...\n"

Vectra.on_operation do |event|
  status = event.success? ? "✅ SUCCESS" : "❌ ERROR"
  duration_color = event.duration > 100 ? "\e[31m" : "\e[32m"  # Red if > 100ms, green otherwise
  reset_color = "\e[0m"

  puts "#{status} | #{event.operation.to_s.upcase.ljust(10)} | " \
       "#{event.provider}/#{event.index.ljust(15)} | " \
       "#{duration_color}#{event.duration.round(1)}ms#{reset_color}"

  if event.metadata.any?
    puts "         Metadata: #{event.metadata.inspect}"
  end

  if event.failure?
    puts "         Error: #{event.error.class} - #{event.error.message}"
  end

  puts
end

# Create client
client = Vectra::Client.new

puts "Creating test index...\n"

begin
  client.provider.delete_index(name: 'demo_index')
rescue Vectra::NotFoundError
  # Doesn't exist, that's fine
end

client.provider.create_index(name: 'demo_index', dimension: 3, metric: 'cosine')
sleep 0.5  # Give it a moment

puts "\n" + "=" * 80
puts "TESTING OPERATIONS"
puts "=" * 80
puts

# Test 1: Upsert
puts "1. UPSERT (3 vectors):"
client.upsert(
  index: 'demo_index',
  vectors: [
    { id: 'vec1', values: [0.1, 0.2, 0.3], metadata: { text: 'Hello' } },
    { id: 'vec2', values: [0.4, 0.5, 0.6], metadata: { text: 'World' } },
    { id: 'vec3', values: [0.7, 0.8, 0.9], metadata: { text: 'Test' } }
  ]
)

sleep 0.5

# Test 2: Query
puts "2. QUERY (top_k=2):"
results = client.query(
  index: 'demo_index',
  vector: [0.1, 0.2, 0.3],
  top_k: 2
)

sleep 0.5

# Test 3: Fetch
puts "3. FETCH (2 IDs):"
client.fetch(
  index: 'demo_index',
  ids: ['vec1', 'vec2']
)

sleep 0.5

# Test 4: Update
puts "4. UPDATE (metadata):"
client.update(
  index: 'demo_index',
  id: 'vec1',
  metadata: { text: 'Updated', processed: true }
)

sleep 0.5

# Test 5: Delete
puts "5. DELETE (1 ID):"
client.delete(
  index: 'demo_index',
  ids: ['vec3']
)

sleep 0.5

# Test 6: Bulk operations
puts "6. BULK UPSERT (100 vectors):"
bulk_vectors = 100.times.map do |i|
  { id: "bulk_#{i}", values: [rand, rand, rand], metadata: { index: i } }
end

client.upsert(index: 'demo_index', vectors: bulk_vectors)

sleep 0.5

# Test 7: Large query
puts "7. LARGE QUERY (top_k=50):"
client.query(
  index: 'demo_index',
  vector: [rand, rand, rand],
  top_k: 50
)

# Cleanup
puts "\n" + "=" * 80
puts "CLEANUP"
puts "=" * 80
puts

puts "Deleting test index..."
client.provider.delete_index(name: 'demo_index')

puts "\n✅ Demo complete!"
puts "\nYou can see:"
puts "  • Operation names (UPSERT, QUERY, FETCH, UPDATE, DELETE)"
puts "  • Provider and index"
puts "  • Duration in milliseconds (color-coded)"
puts "  • Metadata (vector counts, filters, etc.)"
puts "  • Success/error status"
puts "\nThis data can be sent to:"
puts "  • New Relic (require 'vectra/instrumentation/new_relic')"
puts "  • Datadog (require 'vectra/instrumentation/datadog')"
puts "  • Custom monitoring systems"
