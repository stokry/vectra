---
layout: page
title: "Runbook: High Latency"
permalink: /guides/runbooks/high-latency/
---

# Runbook: High Latency

**Alert:** `VectraHighLatency`  
**Severity:** Warning  
**Threshold:** P95 latency >2s for 5 minutes

## Symptoms

- Slow vector operations
- Request timeouts
- User-facing latency issues
- Queue backlog building up

## Quick Diagnosis

```promql
# Check current latency by operation
histogram_quantile(0.95, 
  sum(rate(vectra_request_duration_seconds_bucket[5m])) by (le, operation)
)
```

```ruby
# Test latency in console
require 'benchmark'

time = Benchmark.realtime do
  client.query(index: "test", vector: [0.1] * 384, top_k: 10)
end
puts "Query latency: #{(time * 1000).round}ms"
```

## Investigation Steps

### 1. Identify Slow Operations

```promql
# Which operations are slow?
topk(5, 
  histogram_quantile(0.95, 
    sum(rate(vectra_request_duration_seconds_bucket[5m])) by (le, operation)
  )
)
```

| Operation | Expected P95 | Alert Threshold |
|-----------|--------------|-----------------|
| query | <500ms | >2s |
| upsert (single) | <200ms | >1s |
| upsert (batch 100) | <2s | >5s |
| fetch | <100ms | >500ms |
| delete | <200ms | >1s |

### 2. Check Provider Status

```bash
# Test provider connectivity
curl -w "@curl-format.txt" -o /dev/null -s https://api.pinecone.io/health

# curl-format.txt:
# time_namelookup: %{time_namelookup}\n
# time_connect: %{time_connect}\n
# time_starttransfer: %{time_starttransfer}\n
# time_total: %{time_total}\n
```

### 3. Check Network Latency

```bash
# Ping provider endpoint
ping -c 10 api.pinecone.io

# Check for packet loss
mtr api.pinecone.io

# DNS resolution time
time nslookup api.pinecone.io
```

### 4. Check Vector Dimensions

```ruby
# Large vectors = slower operations
client.describe_index(index: "my-index")
# => { dimension: 1536, ... }

# Consider using smaller embeddings:
# - text-embedding-3-small: 512-1536 dims
# - text-embedding-ada-002: 1536 dims
# - all-MiniLM-L6-v2: 384 dims (faster!)
```

### 5. Check Index Size

```ruby
stats = client.stats(index: "my-index")
puts "Vector count: #{stats[:total_vector_count]}"
puts "Index fullness: #{stats[:index_fullness]}"

# Large indexes may need optimization
# - Pinecone: Check pod type
# - pgvector: Check IVFFlat parameters
# - Qdrant: Check HNSW parameters
```

## Resolution Steps

### Immediate: Increase Timeouts

```ruby
Vectra.configure do |config|
  config.timeout = 60       # Increase from 30
  config.open_timeout = 20  # Increase from 10
end
```

### Enable Caching

```ruby
cache = Vectra::Cache.new(ttl: 300, max_size: 1000)
cached_client = Vectra::CachedClient.new(client, cache: cache)

# Repeat queries will be instant
```

### Optimize Batch Operations

```ruby
# Use smaller batches for faster responses
batch = Vectra::Batch.new(client, concurrency: 2)

result = batch.upsert_async(
  index: "my-index",
  vectors: vectors,
  chunk_size: 50  # Smaller chunks = faster individual operations
)
```

### Reduce top_k

```ruby
# Fewer results = faster query
results = client.query(
  index: "my-index",
  vector: query_vec,
  top_k: 5  # Instead of 100
)
```

### Provider-Specific Optimizations

#### Pinecone

```ruby
# Use serverless for auto-scaling
# Or upgrade pod type for more capacity
```

#### pgvector

```sql
-- Check if index exists
SELECT indexname FROM pg_indexes WHERE tablename = 'your_table';

-- Create IVFFlat index for faster queries
CREATE INDEX ON your_table 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Increase probes for accuracy vs speed trade-off
SET ivfflat.probes = 10;  -- Default: 1
```

#### Qdrant

```ruby
# Optimize HNSW parameters
client.provider.create_index(
  name: "optimized",
  dimension: 384,
  metric: "cosine",
  hnsw_config: {
    m: 16,           # Connections per node
    ef_construct: 100 # Build-time accuracy
  }
)
```

### Connection Pooling (pgvector)

```ruby
# Warmup connections to avoid cold start latency
client.provider.warmup_pool(5)

# Increase pool size for parallel queries
Vectra.configure do |config|
  config.pool_size = 20
end
```

## Prevention

### 1. Monitor Latency Trends

```promql
# Alert on increasing latency trend
rate(vectra_request_duration_seconds_sum[1h]) /
rate(vectra_request_duration_seconds_count[1h]) > 1
```

### 2. Implement Request Timeouts

```ruby
# Fail fast instead of hanging
Vectra.configure do |config|
  config.timeout = 10  # Strict timeout
end
```

### 3. Use Async Operations

```ruby
# Don't block on upserts
Thread.new do
  batch.upsert_async(index: "bg-index", vectors: vectors)
end
```

### 4. Index Maintenance

```sql
-- pgvector: Reindex periodically
REINDEX INDEX your_ivfflat_index;

-- Analyze for query planner
ANALYZE your_table;
```

### 5. Geographic Optimization

```ruby
# Use closest region to your servers
# Pinecone: us-east-1, us-west-2, eu-west-1
# Qdrant Cloud: Select nearest region
```

## Benchmarking

```ruby
# Run benchmark to establish baseline
require 'benchmark'

results = Benchmark.bm do |x|
  x.report("query") do
    100.times { client.query(index: "test", vector: vec, top_k: 10) }
  end
  
  x.report("upsert") do
    client.upsert(index: "test", vectors: vectors_100)
  end
  
  x.report("fetch") do
    100.times { client.fetch(index: "test", ids: ["id1"]) }
  end
end
```

## Escalation

| Time | Action |
|------|--------|
| 5 min | Enable caching, increase timeouts |
| 15 min | Check provider status, optimize queries |
| 30 min | Scale up provider resources |
| 1 hour | Engage provider support |

## Related

- [High Error Rate Runbook]({{ site.baseurl }}/guides/runbooks/high-error-rate)
- [Performance Guide]({{ site.baseurl }}/guides/performance)
- [Monitoring Guide]({{ site.baseurl }}/guides/monitoring)
