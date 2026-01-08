# frozen_string_literal: true

require "bundler/setup"
require "vectra"
require "benchmark"

# Benchmark for connection pooling under concurrent load
#
# Usage:
#   ruby benchmarks/connection_pooling_benchmark.rb

puts "=" * 80
puts "VECTRA CONNECTION POOLING BENCHMARK"
puts "=" * 80
puts

DB_URL = ENV.fetch("DATABASE_URL", "postgres://postgres:password@localhost/vectra_benchmark")
DIMENSION = 384
THREAD_COUNTS = [1, 2, 5, 10, 20].freeze
OPERATIONS_PER_THREAD = 50

# Test different pool sizes
[5, 10, 20].each do |pool_size|
  puts "\n#{"=" * 80}"
  puts "Pool Size: #{pool_size}"
  puts "=" * 80

  client = Vectra.pgvector(
    connection_url: DB_URL,
    pool_size: pool_size,
    pool_timeout: 10
  )

  # Create test index
  begin
    client.provider.create_index(name: "benchmark_pool", dimension: DIMENSION)
  rescue StandardError
    # Already exists
  end

  # Pre-populate some data
  vectors = 100.times.map do |i|
    {
      id: "vec_#{i}",
      values: Array.new(DIMENSION) { rand },
      metadata: { index: i }
    }
  end
  client.upsert(index: "benchmark_pool", vectors: vectors)

  THREAD_COUNTS.each do |thread_count|
    # Skip if threads > pool size (will timeout)
    next if thread_count > pool_size + 5

    total_time = Benchmark.realtime do
      threads = thread_count.times.map do |_thread_idx|
        Thread.new do
          query_vector = Array.new(DIMENSION) { rand }

          OPERATIONS_PER_THREAD.times do
            client.query(
              index: "benchmark_pool",
              vector: query_vector,
              top_k: 10
            )
          end
        end
      end

      threads.each(&:join)
    end

    total_operations = thread_count * OPERATIONS_PER_THREAD
    ops_per_sec = total_operations / total_time

    # Get pool stats
    stats = client.provider.pool_stats

    puts "  #{thread_count.to_s.rjust(2)} threads: " \
         "#{total_time.round(2)}s total " \
         "(#{ops_per_sec.round(1)} ops/sec) " \
         "Pool: #{stats[:available]}/#{stats[:size]} available"
  end

  # Cleanup
  client.provider.shutdown!
end

puts "\n✅ Benchmark complete!"
puts "\nKey takeaways:"
puts "  • Pool size should match max concurrent threads"
puts "  • More threads than pool size causes waiting/timeouts"
puts "  • Monitor pool_stats in production for optimal sizing"
