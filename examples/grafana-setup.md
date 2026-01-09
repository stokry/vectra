# Grafana Dashboard Setup for Vectra

Complete guide to set up a beautiful Grafana dashboard for monitoring Vectra vector database operations.

## Prerequisites

1. **Grafana Account** - Sign up at [grafana.com](https://grafana.com) or use self-hosted Grafana
2. **Prometheus** - For metrics collection (or use Grafana Cloud's Prometheus)
3. **Vectra with Instrumentation** - Enable metrics in your application

## Quick Setup for Screenshots (3 minutes)

**Perfect for creating dashboard screenshots!**

### Option 1: Use Demo Exporter (Easiest)

1. **Start Prometheus Exporter:**
   ```bash
   ruby examples/prometheus-exporter.rb
   ```
   This generates demo metrics automatically.

2. **Setup Grafana Cloud (or local):**
   - Sign up at [grafana.com](https://grafana.com) (free tier available)
   - Create a Prometheus data source pointing to `http://localhost:9394`
   - Or use Grafana Cloud's built-in Prometheus

3. **Import Dashboard:**
   - Go to Dashboards → Import
   - Upload `examples/grafana-dashboard.json`
   - Select your Prometheus data source
   - Click "Import"

4. **Take Screenshots:**
   - Dashboard will populate with demo data
   - Wait 1-2 minutes for metrics to accumulate
   - Use Grafana's built-in screenshot feature or browser screenshot

### Option 2: Full Production Setup

## Full Setup (5 minutes)

### Step 1: Enable Vectra Metrics

Add to your Rails initializer or application:

```ruby
# config/initializers/vectra_metrics.rb
require "prometheus/client"

module VectraMetrics
  REGISTRY = Prometheus::Client.registry

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
end

# Register instrumentation
Vectra::Instrumentation.register(:prometheus) do |event|
  labels = {
    provider: event[:provider],
    operation: event[:operation]
  }

  status = event[:error] ? "error" : "success"
  VectraMetrics::REQUESTS_TOTAL.increment(labels: labels.merge(status: status))

  if event[:duration]
    VectraMetrics::REQUEST_DURATION.observe(event[:duration], labels: labels)
  end

  if event[:metadata]&.dig(:vector_count)
    VectraMetrics::VECTORS_PROCESSED.increment(
      by: event[:metadata][:vector_count],
      labels: labels
    )
  end

  if event[:error]
    VectraMetrics::ERRORS_TOTAL.increment(
      labels: labels.merge(error_type: event[:error].class.name)
    )
  end
end
```

### Step 2: Expose Prometheus Endpoint

For Rails, add to `config/routes.rb`:

```ruby
# config/routes.rb
require "rack/prometheus"

Rails.application.routes.draw do
  # ... your routes ...
  
  # Prometheus metrics endpoint
  get "/metrics", to: proc { |env|
    [
      200,
      { "Content-Type" => "text/plain" },
      [Prometheus::Client::Formats::Text.marshal(VectraMetrics::REGISTRY)]
    ]
  }
end
```

Or use `rack-prometheus` gem:

```ruby
# Gemfile
gem "rack-prometheus"

# config/application.rb
config.middleware.use Rack::Prometheus::Middleware
```

### Step 3: Configure Prometheus

Create `prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "vectra"
    static_configs:
      - targets: ["localhost:3000"]  # Your Rails app
    metrics_path: "/metrics"
```

### Step 4: Import Dashboard to Grafana

1. **Login to Grafana** (grafana.com or your instance)

2. **Add Prometheus Data Source:**
   - Go to Configuration → Data Sources
   - Add Prometheus
   - URL: `http://localhost:9090` (or your Prometheus URL)
   - Click "Save & Test"

3. **Import Dashboard:**
   - Go to Dashboards → Import
   - Click "Upload JSON file"
   - Select `grafana-dashboard.json`
   - Select your Prometheus data source
   - Click "Import"

4. **View Dashboard:**
   - Dashboard will appear with all panels
   - Run your Vectra demo to generate metrics
   - Watch real-time data populate!

## Dashboard Panels

The dashboard includes 12 panels:

### Top Row (Stats)
1. **Total Requests** - Requests per second
2. **Error Rate** - Error percentage with color coding
3. **P95 Latency** - 95th percentile latency
4. **Cache Hit Ratio** - Cache performance

### Middle Row (Time Series)
5. **Request Rate by Operation** - Query, upsert, delete, etc.
6. **Latency Distribution** - P50, P95, P99 percentiles
7. **Vectors Processed** - Throughput by operation
8. **Errors by Type** - Error breakdown

### Bottom Row (Visualizations)
9. **Connection Pool Status** - pgvector pool metrics
10. **Request Rate by Provider** - Bar chart by provider
11. **Operations Distribution** - Pie chart
12. **Provider Distribution** - Pie chart

## Generating Demo Data

Run the comprehensive demo to generate metrics:

```bash
# Run demo (generates metrics)
bundle exec ruby examples/comprehensive_demo.rb

# Or run your application
rails server
```

## Screenshot Tips for Social Media

### Best Panels for Screenshots

1. **Request Rate by Operation** ⭐
   - Shows activity over time
   - Clean, professional look
   - Perfect for Twitter/LinkedIn

2. **Latency Distribution (P50, P95, P99)** ⭐
   - Shows performance metrics
   - Multiple lines = impressive
   - Great for technical posts

3. **Operations Distribution (Pie Chart)** ⭐
   - Clean, colorful visualization
   - Easy to understand
   - Perfect for overview posts

4. **Top Row Stats** ⭐
   - 4 stat panels side-by-side
   - Shows key metrics at a glance
   - Great for hero images

### Time Ranges for Screenshots

- **Last 15 minutes** - Shows recent activity (best for demos)
- **Last 1 hour** - Shows trends (good for posts)
- **Last 6 hours** - Shows daily patterns (for analysis posts)

### Grafana Screenshot Features

1. **Built-in Screenshot:**
   - Click panel → Share → Direct link rendered image
   - Or use browser screenshot (Cmd+Shift+4 on Mac)

2. **Full Dashboard Screenshot:**
   - Use browser developer tools
   - Or Grafana's export feature

3. **Panel Screenshots:**
   - Right-click panel → Inspect
   - Use browser screenshot tool

### Customization for Better Screenshots

1. **Change Theme:**
   - Settings → Preferences → Theme
   - Dark theme looks more professional

2. **Adjust Time Range:**
   - Use "Last 15 minutes" for demo screenshots
   - Shows active data

3. **Hide Legend (if needed):**
   - Panel → Options → Legend → Hide
   - Cleaner look for some panels

4. **Add Title/Description:**
   - Panel → Title → Add description
   - Makes screenshots self-explanatory

## Troubleshooting

### No Data Showing

1. **Check Prometheus is scraping:**
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```

2. **Check metrics endpoint:**
   ```bash
   curl http://localhost:3000/metrics | grep vectra
   ```

3. **Verify instrumentation:**
   ```ruby
   # In Rails console
   Vectra::Instrumentation.enabled?  # Should be true
   ```

### Missing Metrics

- Ensure `config.instrumentation = true` in Vectra config
- Check Prometheus is scraping your app
- Verify labels match dashboard queries

## Advanced: Grafana Cloud Setup

If using Grafana Cloud:

1. **Create Prometheus data source:**
   - Use Grafana Cloud's Prometheus URL
   - Add API key for authentication

2. **Push metrics:**
   ```ruby
   # Use prometheus/client_ruby with push gateway
   require "prometheus/client/push"
   
   Prometheus::Client::Push.new(
     job: "vectra",
     gateway: "https://prometheus-us-central1.grafana.net"
   ).add(VectraMetrics::REGISTRY)
   ```

## Next Steps

- [Monitoring Guide](../docs/guides/monitoring.md) - Full monitoring setup
- [Performance Guide](../docs/guides/performance.md) - Optimization tips
- [Examples](../examples/) - More demo code
