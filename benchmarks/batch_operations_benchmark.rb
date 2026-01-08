# frozen_string_literal: true

require "bundler/setup"
require "vectra"
require "benchmark"

# Benchmark for batch operations
#
# Usage:
#   ruby benchmarks/batch_operations_benchmark.rb

puts "=" * 80
puts "VECTRA BATCH OPERATIONS BENCHMARK"
puts "=" * 80
puts

# Setup
DB_URL = ENV.fetch("DATABASE_URL", "postgres://postgres:password@localhost/vectra_benchmark")
DIMENSION = 384
ITERATIONS = 5

client = Vectra.pgvector(connection_url: DB_URL)

# Create test index
puts "Creating test index..."
begin
  client.provider.delete_index(name: "benchmark_test")
rescue Vectra::NotFoundError
  # Index doesn't exist, that's fine
end

client.provider.create_index(
  name: "benchmark_test",
  dimension: DIMENSION,
  metric: "cosine"
)

# Generate test vectors
def generate_vectors(count, dimension)
  count.times.map do |i|
    {
      id: "vec_#{i}",
      values: Array.new(dimension) { rand },
      metadata: { index: i, category: "cat_#{i % 10}" }
    }
  end
end

puts "\nRunning benchmarks (#{ITERATIONS} iterations each)..."
puts "-" * 80

# Test different vector counts
[100, 500, 1000, 5000, 10_000].each do |count|
  puts "\n#{count} vectors:"

  vectors = generate_vectors(count, DIMENSION)

  # Test different batch sizes
  [50, 100, 250, 500].each do |batch_size|
    next if batch_size > count

    client.config.batch_size = batch_size

    times = []
    ITERATIONS.times do
      time = Benchmark.realtime do
        client.upsert(index: "benchmark_test", vectors: vectors)
      end
      times << time
    end

    avg_time = times.sum / times.size
    vectors_per_sec = count / avg_time
    batches = (count.to_f / batch_size).ceil

    puts "  Batch size #{batch_size.to_s.rjust(3)}: " \
         "#{avg_time.round(3)}s avg " \
         "(#{vectors_per_sec.round(0)} vectors/sec, " \
         "#{batches} batches)"
  end
end

# Query benchmarks
puts "\n#{"=" * 80}"
puts "QUERY BENCHMARKS"
puts "=" * 80

query_vector = Array.new(DIMENSION) { rand }

puts "\nQuery performance (#{ITERATIONS} iterations):"
[10, 20, 50, 100].each do |top_k|
  times = []
  ITERATIONS.times do
    time = Benchmark.realtime do
      client.query(
        index: "benchmark_test",
        vector: query_vector,
        top_k: top_k
      )
    end
    times << time
  end

  avg_time = times.sum / times.size
  queries_per_sec = 1 / avg_time

  puts "  top_k=#{top_k.to_s.rjust(3)}: " \
       "#{(avg_time * 1000).round(1)}ms avg " \
       "(#{queries_per_sec.round(1)} queries/sec)"
end

# Cleanup
puts "\nCleaning up..."
client.provider.delete_index(name: "benchmark_test")
client.provider.shutdown!

puts "\n✅ Benchmark complete!"
