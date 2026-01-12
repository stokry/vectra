---
layout: page
title: Performance & Optimization
permalink: /guides/performance/
---

# Performance & Optimization

Vectra provides several performance optimization features for high-throughput applications.

## Async Batch Operations

Process large vector sets concurrently with automatic chunking:

```ruby
require 'vectra'

client = Vectra::Client.new(provider: :pinecone, api_key: ENV['PINECONE_API_KEY'])

# Create a batch processor with 4 concurrent workers
batch = Vectra::Batch.new(client, concurrency: 4)

# Async upsert with automatic chunking
vectors = 10_000.times.map { |i| { id: "vec_#{i}", values: Array.new(384) { rand } } }

result = batch.upsert_async(
  index: 'my-index',
  vectors: vectors,
  chunk_size: 100,
  on_progress: proc { |stats|
    progress = stats[:percentage]
    processed = stats[:processed]
    total = stats[:total]
    chunk = stats[:current_chunk] + 1
    total_chunks = stats[:total_chunks]
    
    puts "Progress: #{progress}% (#{processed}/#{total})"
    puts "  Chunk #{chunk}/#{total_chunks} | Success: #{stats[:success_count]}, Failed: #{stats[:failed_count]}"
  }
)

puts "Upserted: #{result[:upserted_count]} vectors in #{result[:chunks]} chunks"
puts "Errors: #{result[:errors].size}" if result[:errors].any?
```

### Progress Tracking

Monitor batch operations in real-time with progress callbacks:

```ruby
batch.upsert_async(
  index: 'my-index',
  vectors: large_vector_array,
  chunk_size: 100,
  on_progress: proc { |stats|
    # stats contains:
    # - processed: number of processed vectors
    # - total: total number of vectors
    # - percentage: progress percentage (0-100)
    # - current_chunk: current chunk index (0-based)
    # - total_chunks: total number of chunks
    # - success_count: number of successful chunks
    # - failed_count: number of failed chunks
    
    puts "Progress: #{stats[:percentage]}% (#{stats[:processed]}/#{stats[:total]})"
  }
)
```

### Batch Delete

```ruby
ids = 1000.times.map { |i| "vec_#{i}" }

result = batch.delete_async(
  index: 'my-index',
  ids: ids,
  chunk_size: 100
)
```

### Batch Fetch

```ruby
ids = ['vec_1', 'vec_2', 'vec_3']

vectors = batch.fetch_async(
  index: 'my-index',
  ids: ids,
  chunk_size: 50
)
```

## Streaming Results

For large query result sets, use streaming to reduce memory usage:

```ruby
stream = Vectra::Streaming.new(client, page_size: 100)

# Stream with a block
stream.query_each(
  index: 'my-index',
  vector: query_vector,
  total: 1000
) do |match|
  process_match(match)
end

# Or use lazy enumerator
results = stream.query_stream(
  index: 'my-index',
  vector: query_vector,
  total: 1000
)

# Only fetches what you need
results.take(50).each { |m| puts m.id }
```

## Caching Layer

Cache frequently queried vectors to reduce database load:

```ruby
# Create cache with 5-minute TTL
cache = Vectra::Cache.new(ttl: 300, max_size: 1000)

# Wrap client with caching
cached_client = Vectra::CachedClient.new(client, cache: cache)

# First query hits the database
result1 = cached_client.query(index: 'idx', vector: vec, top_k: 10)

# Second identical query returns cached result
result2 = cached_client.query(index: 'idx', vector: vec, top_k: 10)

# Invalidate cache when data changes
cached_client.invalidate_index('idx')

# Clear all cache
cached_client.clear_cache
```

### Cache Statistics

```ruby
stats = cache.stats
puts "Cache size: #{stats[:size]}/#{stats[:max_size]}"
puts "TTL: #{stats[:ttl]} seconds"
```

## Connection Pooling (pgvector)

For pgvector, use connection pooling with warmup:

```ruby
# Configure pool size
Vectra.configure do |config|
  config.provider = :pgvector
  config.host = ENV['DATABASE_URL']
  config.pool_size = 10
  config.pool_timeout = 5
end

client = Vectra::Client.new

# Warmup connections at startup
client.provider.warmup_pool(5)

# Check pool stats
stats = client.provider.pool_stats
puts "Available connections: #{stats[:available]}"
puts "Checked out: #{stats[:checked_out]}"

# Shutdown pool when done
client.provider.shutdown_pool
```

## Configuration Options

```ruby
Vectra.configure do |config|
  # Provider settings
  config.provider = :pinecone
  config.api_key = ENV['PINECONE_API_KEY']
  
  # Timeouts
  config.timeout = 30
  config.open_timeout = 10
  
  # Retry settings
  config.max_retries = 3
  config.retry_delay = 1
  
  # Batch operations
  config.batch_size = 100
  config.async_concurrency = 4
  
  # Connection pooling (pgvector)
  config.pool_size = 10
  config.pool_timeout = 5
  
  # Caching
  config.cache_enabled = true
  config.cache_ttl = 300
  config.cache_max_size = 1000
end
```

## Benchmarking

Run the included benchmarks:

```bash
# Batch operations benchmark
bundle exec ruby benchmarks/batch_operations_benchmark.rb

# Connection pooling benchmark
bundle exec ruby benchmarks/connection_pooling_benchmark.rb
```

## Best Practices

1. **Batch Size**: Use batch sizes of 100-500 for optimal throughput
2. **Concurrency**: Set concurrency to 2-4x your CPU cores
3. **Connection Pool**: Size pool to expected concurrent requests + 20%
4. **Cache TTL**: Set TTL based on data freshness requirements
5. **Warmup**: Always warmup connections in production

## Next Steps

- [API Reference]({{ site.baseurl }}/api/overview)
- [Provider Guides]({{ site.baseurl }}/providers)
