#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple Prometheus Exporter for Vectra Demo
#
# This script exposes Prometheus metrics endpoint for Grafana dashboard.
# Run this alongside your demo to generate metrics.
#
# Prerequisites:
#   gem install prometheus-client
#
# Usage:
#   ruby examples/prometheus-exporter.rb
#   # Then run: bundle exec ruby examples/comprehensive_demo.rb
#
# Access metrics:
#   curl http://localhost:9394/metrics

begin
  require "webrick"
  require "prometheus/client"
  require "json"
rescue LoadError => e
  if e.message.include?("prometheus")
    puts "❌ Error: prometheus-client gem not found"
    puts
    puts "Install it with:"
    puts "  gem install prometheus-client"
    puts
    puts "Or add to Gemfile:"
    puts "  gem 'prometheus-client'"
    exit 1
  else
    raise
  end
end

# Create Prometheus registry
REGISTRY = Prometheus::Client.registry

# Define metrics
REQUESTS_TOTAL = REGISTRY.counter(
  :vectra_requests_total,
  docstring: "Total Vectra requests",
  labels: [:provider, :operation, :status]
)

REQUEST_DURATION = REGISTRY.histogram(
  :vectra_request_duration_seconds,
  docstring: "Request duration in seconds",
  labels: [:provider, :operation],
  buckets: [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
)

VECTORS_PROCESSED = REGISTRY.counter(
  :vectra_vectors_processed_total,
  docstring: "Total vectors processed",
  labels: [:provider, :operation]
)

CACHE_HITS = REGISTRY.counter(
  :vectra_cache_hits_total,
  docstring: "Cache hit count"
)

CACHE_MISSES = REGISTRY.counter(
  :vectra_cache_misses_total,
  docstring: "Cache miss count"
)

ERRORS_TOTAL = REGISTRY.counter(
  :vectra_errors_total,
  docstring: "Total errors",
  labels: [:provider, :error_type]
)

POOL_SIZE = REGISTRY.gauge(
  :vectra_pool_connections,
  docstring: "Connection pool size",
  labels: [:state]
)

# Simulate metrics for demo (in production, these come from Vectra)
def generate_demo_metrics
  providers = %w[pinecone qdrant pgvector]
  operations = %w[query upsert fetch delete update]
  
  loop do
    provider = providers.sample
    operation = operations.sample
    
    # Simulate requests
    REQUESTS_TOTAL.increment(
      labels: {
        provider: provider,
        operation: operation,
        status: rand > 0.05 ? "success" : "error"
      }
    )
    
    # Simulate latency
    duration = case operation
               when "query"
                 rand(0.01..0.1)
               when "upsert"
                 rand(0.05..0.3)
               else
                 rand(0.01..0.2)
               end
    
    REQUEST_DURATION.observe(
      duration,
      labels: { provider: provider, operation: operation }
    )
    
    # Simulate vectors processed
    if %w[upsert query].include?(operation)
      VECTORS_PROCESSED.increment(
        by: rand(1..100),
        labels: { provider: provider, operation: operation }
      )
    end
    
    # Simulate cache hits/misses
    if rand > 0.3
      CACHE_HITS.increment
    else
      CACHE_MISSES.increment
    end
    
    # Simulate errors
    if rand < 0.05
      ERRORS_TOTAL.increment(
        labels: {
          provider: provider,
          error_type: %w[RateLimitError ServerError ConnectionError].sample
        }
      )
    end
    
    # Simulate pool metrics (pgvector)
    if provider == "pgvector"
      POOL_SIZE.set(
        rand(3..8),
        labels: { state: "available" }
      )
      POOL_SIZE.set(
        rand(1..3),
        labels: { state: "checked_out" }
      )
    end
    
    sleep(rand(0.5..2.0))
  end
end

# Start metrics generation in background
Thread.new { generate_demo_metrics }

# Create HTTP server
server = WEBrick::HTTPServer.new(Port: 9394)

server.mount_proc("/metrics") do |_req, res|
  res.content_type = "text/plain; version=0.0.4"
  res.body = Prometheus::Client::Formats::Text.marshal(REGISTRY)
end

server.mount_proc("/") do |_req, res|
  res.content_type = "text/html"
  res.body = <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Vectra Prometheus Exporter</title>
      <style>
        body { font-family: system-ui; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #05df72; }
        .status { background: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        code { background: #f5f5f5; padding: 2px 6px; border-radius: 3px; }
        a { color: #05df72; text-decoration: none; }
        a:hover { text-decoration: underline; }
      </style>
    </head>
    <body>
      <h1>🚀 Vectra Prometheus Exporter</h1>
      <div class="status">
        <p><strong>Status:</strong> Running</p>
        <p><strong>Metrics Endpoint:</strong> <a href="/metrics"><code>/metrics</code></a></p>
        <p><strong>Port:</strong> 9394</p>
      </div>
      <h2>Available Metrics</h2>
      <ul>
        <li><code>vectra_requests_total</code> - Total requests by provider/operation</li>
        <li><code>vectra_request_duration_seconds</code> - Request latency histogram</li>
        <li><code>vectra_vectors_processed_total</code> - Vectors processed</li>
        <li><code>vectra_cache_hits_total</code> - Cache hits</li>
        <li><code>vectra_cache_misses_total</code> - Cache misses</li>
        <li><code>vectra_errors_total</code> - Error counts</li>
        <li><code>vectra_pool_connections</code> - Connection pool status</li>
      </ul>
      <h2>Next Steps</h2>
      <ol>
        <li>Configure Prometheus to scrape <code>http://localhost:9394/metrics</code></li>
        <li>Import Grafana dashboard from <code>examples/grafana-dashboard.json</code></li>
        <li>Run your Vectra demo to generate real metrics</li>
      </ol>
      <p><a href="/metrics">View Metrics →</a></p>
    </body>
    </html>
  HTML
end

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }

puts "=" * 60
puts "🚀 Vectra Prometheus Exporter"
puts "=" * 60
puts
puts "📊 Metrics endpoint: http://localhost:9394/metrics"
puts "🌐 Web interface: http://localhost:9394"
puts
puts "💡 This exporter generates demo metrics."
puts "   In production, use Vectra instrumentation instead."
puts
puts "Press Ctrl+C to stop..."
puts

server.start
