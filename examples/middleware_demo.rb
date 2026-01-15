#!/usr/bin/env ruby
# frozen_string_literal: true

# Middleware System Demo
#
# This script demonstrates the new middleware system in Vectra.
# Run with: ruby examples/middleware_demo.rb

require_relative "../lib/vectra"

# Configure global middleware
puts "🎯 Configuring global middleware..."
Vectra::Client.use Vectra::Middleware::Logging
Vectra::Client.use Vectra::Middleware::Retry, max_attempts: 3
Vectra::Client.use Vectra::Middleware::CostTracker, on_cost: ->(event) {
  puts "💰 Cost: $#{event[:cost_usd].round(6)} for #{event[:operation]}"
}

# Create client
puts "\n📦 Creating client with Memory provider..."
client = Vectra::Client.new(
  provider: :memory,
  index: "demo"
)

# Example 1: Upsert with middleware
puts "\n🔄 Example 1: Upsert with middleware stack"
puts "=" * 50
client.upsert(
  index: "demo",
  vectors: [
    { id: "doc-1", values: [0.1, 0.2, 0.3], metadata: { title: "Ruby" } },
    { id: "doc-2", values: [0.4, 0.5, 0.6], metadata: { title: "Python" } }
  ]
)

# Example 2: Query with middleware
puts "\n🔍 Example 2: Query with middleware stack"
puts "=" * 50
results = client.query(
  index: "demo",
  vector: [0.1, 0.2, 0.3],
  top_k: 2
)
puts "Found #{results.size} results"

# Example 3: Per-client middleware
puts "\n🎨 Example 3: Per-client middleware (PII Redaction)"
puts "=" * 50
pii_client = Vectra::Client.new(
  provider: :memory,
  index: "sensitive",
  middleware: [Vectra::Middleware::PIIRedaction]
)

pii_client.upsert(
  index: "sensitive",
  vectors: [
    {
      id: "user-1",
      values: [0.1, 0.2, 0.3],
      metadata: {
        email: "user@example.com",
        phone: "555-1234",
        note: "Contact at user@example.com"
      }
    }
  ]
)

# Fetch to see redacted data
fetched = pii_client.fetch(index: "sensitive", ids: ["user-1"])
puts "Original email: user@example.com"
puts "Redacted: #{fetched["user-1"].metadata[:email]}"
puts "Redacted note: #{fetched["user-1"].metadata[:note]}"

# Example 4: Custom middleware
puts "\n🛠️  Example 4: Custom middleware"
puts "=" * 50

class TimingMiddleware < Vectra::Middleware::Base
  def before(request)
    puts "⏱️  Starting #{request.operation}..."
  end

  def after(request, response)
    duration = response.metadata[:duration_ms] || 0
    puts "✅ Completed in #{duration.round(2)}ms"
  end
end

custom_client = Vectra::Client.new(
  provider: :memory,
  index: "custom",
  middleware: [TimingMiddleware]
)

custom_client.upsert(
  index: "custom",
  vectors: [{ id: "test", values: [1, 2, 3] }]
)

puts "\n✨ Demo complete!"
