---
layout: page
title: "Runbook: Pool Exhaustion"
permalink: /guides/runbooks/pool-exhausted/
---

# Runbook: Pool Exhaustion

**Alert:** `VectraPoolExhausted`  
**Severity:** Critical  
**Threshold:** 0 available connections for 1 minute

## Symptoms

- `Vectra::Pool::TimeoutError` exceptions
- Requests timing out waiting for connections
- Application threads blocked

## Quick Diagnosis

```ruby
# Check pool stats
client = Vectra::Client.new(provider: :pgvector, host: ENV['DATABASE_URL'])
puts client.provider.pool_stats
# => { available: 0, checked_out: 10, size: 10 }
```

```bash
# Check PostgreSQL connections
psql -c "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE '%vectra%';"
```

## Investigation Steps

### 1. Check Current Pool State

```ruby
stats = client.provider.pool_stats
puts "Available: #{stats[:available]}"
puts "Checked out: #{stats[:checked_out]}"
puts "Total size: #{stats[:size]}"
puts "Shutdown: #{stats[:shutdown]}"
```

### 2. Identify Connection Leaks

```ruby
# Look for connections not being returned
# Common causes:
# - Missing ensure blocks
# - Exceptions before checkin
# - Long-running operations

# Bad:
conn = pool.checkout
do_something(conn)  # If this raises, connection is leaked!
pool.checkin(conn)

# Good:
pool.with_connection do |conn|
  do_something(conn)
end  # Always returns connection
```

### 3. Check for Long-Running Queries

```sql
-- PostgreSQL: Find long-running queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query
FROM pg_stat_activity
WHERE state != 'idle'
AND query NOT LIKE '%pg_stat_activity%'
ORDER BY duration DESC;

-- Kill long-running query if needed
SELECT pg_terminate_backend(pid);
```

### 4. Check Application Thread Count

```ruby
# If using Puma/Sidekiq
# Ensure pool_size >= max_threads
puts "Thread count: #{Thread.list.count}"
puts "Pool size: #{client.config.pool_size}"
```

## Resolution Steps

### Immediate: Restart Connection Pool

```ruby
# Force pool restart
client.provider.shutdown_pool
# Pool will be recreated on next operation
```

### Increase Pool Size

```ruby
Vectra.configure do |config|
  config.provider = :pgvector
  config.host = ENV['DATABASE_URL']
  config.pool_size = 20      # Increase from default 5
  config.pool_timeout = 10   # Increase timeout
end
```

### Fix Connection Leaks

```ruby
# Always use with_connection block
client.provider.with_pooled_connection do |conn|
  # Your code here
  # Connection automatically returned
end

# Or ensure checkin in rescue
begin
  conn = pool.checkout
  do_work(conn)
ensure
  pool.checkin(conn) if conn
end
```

### Reduce Connection Hold Time

```ruby
# Break up long operations
large_dataset.each_slice(100) do |batch|
  client.provider.with_pooled_connection do |conn|
    process_batch(batch, conn)
  end
  # Connection returned between batches
end
```

### Add Connection Warmup

```ruby
# In application initializer
client = Vectra::Client.new(provider: :pgvector, host: ENV['DATABASE_URL'])
client.provider.warmup_pool(5)  # Pre-create 5 connections
```

## Prevention

### 1. Right-size Pool

```ruby
# Formula: pool_size = (max_threads * 1.5) + background_workers
# Example: Puma with 5 threads, 3 Sidekiq workers
pool_size = (5 * 1.5) + 3  # = 10.5, round to 12
```

### 2. Monitor Pool Usage

```promql
# Alert when pool is >80% utilized
vectra_pool_connections{state="checked_out"} 
/ vectra_pool_connections{state="available"} > 0.8
```

### 3. Implement Connection Timeout

```ruby
Vectra.configure do |config|
  config.pool_timeout = 5  # Fail fast instead of hanging
end
```

### 4. Use Connection Pool Metrics

```ruby
# Log pool stats periodically
every(60.seconds) do
  stats = client.provider.pool_stats
  logger.info "Pool: avail=#{stats[:available]} out=#{stats[:checked_out]}"
end
```

## PostgreSQL-Specific

### Check max_connections

```sql
SHOW max_connections;  -- Default: 100

-- Increase if needed (requires restart)
ALTER SYSTEM SET max_connections = 200;
```

### Monitor Connection Usage

```sql
SELECT 
  count(*) as total,
  count(*) FILTER (WHERE state = 'active') as active,
  count(*) FILTER (WHERE state = 'idle') as idle
FROM pg_stat_activity;
```

## Escalation

| Time | Action |
|------|--------|
| 1 min | Restart pool, page on-call |
| 5 min | Increase pool size, restart app |
| 15 min | Check for connection leaks |
| 30 min | Escalate to DBA |

## Related

- [High Error Rate Runbook]({{ site.baseurl }}/guides/runbooks/high-error-rate)
- [Performance Guide]({{ site.baseurl }}/guides/performance)
