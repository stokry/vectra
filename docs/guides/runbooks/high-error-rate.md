---
layout: page
title: "Runbook: High Error Rate"
permalink: /guides/runbooks/high-error-rate/
---

# Runbook: High Error Rate

**Alert:** `VectraHighErrorRate`  
**Severity:** Critical  
**Threshold:** Error rate >5% for 5 minutes

## Symptoms

- Alert firing for high error rate
- Users reporting failed operations
- Increased latency alongside errors

## Quick Diagnosis

```bash
# Check recent errors in logs
grep -i "vectra.*error" /var/log/app.log | tail -50

# Check error breakdown by type
curl -s localhost:9090/api/v1/query?query=sum(vectra_errors_total)by(error_type) | jq
```

## Investigation Steps

### 1. Identify Error Type

```ruby
# In Rails console
Vectra::Client.new.stats(index: "your-index")
```

| Error Type | Likely Cause | Action |
|------------|--------------|--------|
| `AuthenticationError` | Invalid/expired API key | Check credentials |
| `RateLimitError` | Too many requests | Implement backoff |
| `ServerError` | Provider outage | Check provider status |
| `ConnectionError` | Network issues | Check connectivity |
| `ValidationError` | Bad request data | Check input validation |

### 2. Check Provider Status

- **Pinecone:** [status.pinecone.io](https://status.pinecone.io)
- **Qdrant:** Check self-hosted logs or cloud dashboard
- **pgvector:** `SELECT * FROM pg_stat_activity WHERE state = 'active';`

### 3. Check Application Logs

```bash
# Filter by error class
grep "Vectra::RateLimitError" /var/log/app.log | wc -l
grep "Vectra::ServerError" /var/log/app.log | wc -l
grep "Vectra::AuthenticationError" /var/log/app.log | wc -l
```

## Resolution Steps

### Authentication Errors

```ruby
# Verify API key is set
puts ENV['PINECONE_API_KEY'].nil? ? "MISSING" : "SET"

# Test connection
client = Vectra::Client.new
client.list_indexes
```

### Rate Limit Errors

```ruby
# Implement exponential backoff
Vectra.configure do |config|
  config.max_retries = 5
  config.retry_delay = 2  # Start with 2s delay
end

# Or use batch operations with concurrency limit
batch = Vectra::Batch.new(client, concurrency: 2)  # Reduce from 4
```

### Server Errors

1. Check provider status page
2. If provider is down, enable fallback or circuit breaker
3. Consider failover to backup provider

```ruby
# Simple circuit breaker
class VectraCircuitBreaker
  def self.call
    return cached_response if circuit_open?
    
    yield
  rescue Vectra::ServerError
    open_circuit!
    cached_response
  end
end
```

### Connection Errors

```bash
# Test network connectivity
curl -I https://api.pinecone.io/health

# Check DNS resolution
nslookup api.pinecone.io

# Check firewall rules
iptables -L -n | grep -i pinecone
```

## Prevention

1. **Set up retry logic:**
   ```ruby
   config.max_retries = 3
   config.retry_delay = 1
   ```

2. **Monitor error rate trends:**
   ```promql
   increase(vectra_errors_total[1h])
   ```

3. **Implement circuit breakers** for provider outages

4. **Cache frequently accessed data:**
   ```ruby
   cached_client = Vectra::CachedClient.new(client)
   ```

## Escalation

| Time | Action |
|------|--------|
| 5 min | Page on-call engineer |
| 15 min | Escalate to team lead |
| 30 min | Consider provider failover |
| 1 hour | Engage provider support |

## Related

- [High Latency Runbook]({{ site.baseurl }}/guides/runbooks/high-latency)
- [Monitoring Guide]({{ site.baseurl }}/guides/monitoring)
