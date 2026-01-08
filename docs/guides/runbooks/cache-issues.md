---
layout: page
title: "Runbook: Cache Issues"
permalink: /guides/runbooks/cache-issues/
---

# Runbook: Cache Issues

**Alert:** `VectraLowCacheHitRatio`  
**Severity:** Warning  
**Threshold:** Cache hit ratio <50% for 10 minutes

## Symptoms

- High cache miss rate
- Increased database load
- Higher latency than expected
- Stale data being returned

## Quick Diagnosis

```ruby
cache = Vectra::Cache.new
stats = cache.stats

puts "Size: #{stats[:size]} / #{stats[:max_size]}"
puts "TTL: #{stats[:ttl]} seconds"
puts "Keys: #{stats[:keys].count}"
```

```promql
# Prometheus: Check hit ratio
sum(vectra_cache_hits_total) / 
(sum(vectra_cache_hits_total) + sum(vectra_cache_misses_total))
```

## Investigation Steps

### 1. Check Cache Configuration

```ruby
# Current config
puts Vectra.configuration.cache_enabled    # Should be true
puts Vectra.configuration.cache_ttl        # Default: 300
puts Vectra.configuration.cache_max_size   # Default: 1000
```

### 2. Analyze Access Patterns

```ruby
# Check what's being cached
cache.stats[:keys].each do |key|
  parts = key.split(":")
  puts "Index: #{parts[0]}, Type: #{parts[1]}"
end

# Count by type
keys = cache.stats[:keys]
queries = keys.count { |k| k.include?(":q:") }
fetches = keys.count { |k| k.include?(":f:") }
puts "Query cache entries: #{queries}"
puts "Fetch cache entries: #{fetches}"
```

### 3. Check for Cache Thrashing

```ruby
# If max_size is too small, cache thrashes
# Sign: entries being evicted immediately after creation
# Solution: Increase max_size

stats = cache.stats
if stats[:size] >= stats[:max_size] * 0.9
  puts "WARNING: Cache near capacity - consider increasing max_size"
end
```

### 4. Check TTL Appropriateness

```ruby
# If TTL is too short, cache misses are high
# If TTL is too long, stale data is served

# Check data freshness requirements
# - Real-time data: TTL 30-60s
# - Semi-static data: TTL 300-600s
# - Static data: TTL 3600s+
```

## Resolution Steps

### Low Hit Ratio

#### Increase Cache Size

```ruby
cache = Vectra::Cache.new(
  ttl: 300,
  max_size: 5000  # Increase from 1000
)
cached_client = Vectra::CachedClient.new(client, cache: cache)
```

#### Adjust TTL

```ruby
# For high-churn data
cache = Vectra::Cache.new(ttl: 60)  # 1 minute

# For stable data  
cache = Vectra::Cache.new(ttl: 3600)  # 1 hour
```

#### Cache Warming

```ruby
# Pre-populate cache on startup
common_queries = load_common_queries()
common_queries.each do |q|
  cached_client.query(
    index: q[:index],
    vector: q[:vector],
    top_k: q[:top_k]
  )
end
```

### Stale Data

#### Reduce TTL

```ruby
cache = Vectra::Cache.new(ttl: 60)  # Reduce from 300
```

#### Implement Cache Invalidation

```ruby
# After upsert, invalidate affected cache
def upsert_with_invalidation(index:, vectors:)
  result = client.upsert(index: index, vectors: vectors)
  cached_client.invalidate_index(index)
  result
end
```

#### Use Cache-Aside Pattern

```ruby
def get_vector(id)
  # Check cache first
  cached = cache.get("vector:#{id}")
  return cached if cached

  # Fetch from source
  vector = client.fetch(index: "main", ids: [id])[id]
  
  # Cache with appropriate TTL
  cache.set("vector:#{id}", vector)
  vector
end
```

### Cache Thrashing

#### Increase Max Size

```ruby
# Rule of thumb: max_size = unique_queries_per_ttl * 1.5
# Example: 1000 unique queries per 5 min, max_size = 1500
cache = Vectra::Cache.new(
  ttl: 300,
  max_size: 1500
)
```

#### Implement Tiered Caching

```ruby
# Hot cache: Small, short TTL
hot_cache = Vectra::Cache.new(ttl: 60, max_size: 100)

# Warm cache: Large, longer TTL
warm_cache = Vectra::Cache.new(ttl: 600, max_size: 5000)

# Check hot first, then warm
def cached_query(...)
  hot_cache.fetch(key) do
    warm_cache.fetch(key) do
      client.query(...)
    end
  end
end
```

### Memory Issues

#### Monitor Memory Usage

```ruby
# Estimate cache memory usage
# Approximate: 1KB per cached query result
estimated_mb = cache.stats[:size] * 1.0 / 1000
puts "Estimated cache memory: #{estimated_mb} MB"
```

#### Implement LRU Eviction

```ruby
# Vectra::Cache already implements LRU
# If memory is still an issue, reduce max_size
cache = Vectra::Cache.new(max_size: 500)
```

## Prevention

### 1. Right-size Cache

```ruby
# Calculate based on query patterns
unique_queries_per_minute = 100
ttl_minutes = 5
buffer = 1.5

max_size = unique_queries_per_minute * ttl_minutes * buffer
# = 100 * 5 * 1.5 = 750
```

### 2. Monitor Cache Metrics

```promql
# Alert on low hit ratio
sum(rate(vectra_cache_hits_total[5m])) /
(sum(rate(vectra_cache_hits_total[5m])) + 
 sum(rate(vectra_cache_misses_total[5m]))) < 0.5
```

### 3. Implement Cache Warm-up

```ruby
# In application boot
Rails.application.config.after_initialize do
  VectraCacheWarmer.perform_async
end
```

### 4. Use Cache Namespacing

```ruby
# Separate caches for different use cases
search_cache = Vectra::Cache.new(ttl: 60)   # Fast invalidation
embed_cache = Vectra::Cache.new(ttl: 3600)  # Long-lived embeddings
```

## Escalation

| Time | Action |
|------|--------|
| 10 min | Adjust TTL/max_size |
| 30 min | Implement cache warming |
| 1 hour | Review access patterns |
| 2 hours | Consider Redis/Memcached |

## Related

- [Performance Guide]({{ site.baseurl }}/guides/performance)
- [Monitoring Guide]({{ site.baseurl }}/guides/monitoring)
