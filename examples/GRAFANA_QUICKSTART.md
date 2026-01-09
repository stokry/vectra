# Grafana Dashboard - Quick Start for Screenshots

**Get beautiful dashboard screenshots in 5 minutes!**

## Step-by-Step Guide

### 1. Install Dependencies

```bash
# Install prometheus-client gem
gem install prometheus-client

# Or add to Gemfile:
# gem 'prometheus-client'
```

### 2. Start Prometheus Exporter (Terminal 1)

```bash
cd /path/to/vectra
ruby examples/prometheus-exporter.rb
```

You should see:
```
🚀 Vectra Prometheus Exporter
📊 Metrics endpoint: http://localhost:9394/metrics
🌐 Web interface: http://localhost:9394
```

**Keep this running!**

### 3. Setup Grafana Cloud

1. Go to [grafana.com](https://grafana.com) and sign up (free)
2. Create a new organization
3. Go to **Connections** → **Data Sources**
4. Click **Add new data source**
5. Select **Prometheus**
6. Configure:
   - **Name:** `Prometheus` (or any name)
   - **URL:** `http://localhost:9394` (if using local)
   - OR use Grafana Cloud's Prometheus (recommended)
7. Click **Save & Test** (should show "Data source is working")

### 4. Import Dashboard

1. Go to **Dashboards** → **New** → **Import**
2. Click **Upload JSON file**
3. Select `examples/grafana-dashboard.json`
4. Select your Prometheus data source
5. Click **Import**

### 5. View Dashboard

- Dashboard will appear with all panels
- Wait 1-2 minutes for metrics to accumulate
- Refresh dashboard (F5) to see new data

### 6. Take Screenshots

**Option A: Browser Screenshot**
- Use browser dev tools (F12)
- Or use screenshot tool (Cmd+Shift+4 on Mac)

**Option B: Grafana Share**
- Click panel → **Share** → **Direct link rendered image**
- Or use **Export** → **Save as image**

## Best Panels for Screenshots

### 🎯 Top Recommendations:

1. **Request Rate by Operation** (Time Series)
   - Shows query, upsert, delete operations
   - Clean lines, professional look
   - Perfect for: Twitter, LinkedIn, blog posts

2. **Latency Distribution** (P50, P95, P99)
   - Three lines showing percentiles
   - Shows performance depth
   - Perfect for: Technical blog posts, documentation

3. **Operations Distribution** (Pie Chart)
   - Colorful, easy to understand
   - Shows operation breakdown
   - Perfect for: Overview posts, presentations

4. **Top Row Stats** (4 Stat Panels)
   - Total Requests, Error Rate, P95 Latency, Cache Hit Ratio
   - Shows key metrics at a glance
   - Perfect for: Hero images, feature highlights

## Tips for Best Screenshots

### Time Range
- Set to **"Last 15 minutes"** for demo screenshots
- Shows active, recent data

### Theme
- Use **Dark theme** (Settings → Preferences)
- Looks more professional

### Panel Settings
- Hide legend if too cluttered (Panel → Options → Legend)
- Add panel descriptions (Panel → Title → Description)

### Data Density
- Let exporter run for 2-3 minutes before screenshot
- More data = better visualization

## Troubleshooting

### No Data Showing?

1. **Check exporter is running:**
   ```bash
   curl http://localhost:9394/metrics | head -20
   ```
   Should show Prometheus metrics

2. **Check Grafana data source:**
   - Go to Data Sources
   - Click "Test" button
   - Should show "Data source is working"

3. **Check dashboard queries:**
   - Click panel → Edit
   - Check if query returns data
   - Try: `sum(vectra_requests_total)`

### Metrics Not Appearing?

- Exporter generates metrics every 0.5-2 seconds
- Wait 1-2 minutes for data to accumulate
- Refresh dashboard (F5)

## Next Steps

- Run comprehensive demo to generate real metrics:
  ```bash
  bundle exec ruby examples/comprehensive_demo.rb
  ```

- See [grafana-setup.md](grafana-setup.md) for production setup

- Check [monitoring guide](../docs/guides/monitoring.md) for full monitoring setup

## Example Screenshot Workflow

1. ✅ Start exporter: `ruby examples/prometheus-exporter.rb`
2. ✅ Import dashboard to Grafana
3. ✅ Wait 2 minutes for data
4. ✅ Set time range to "Last 15 minutes"
5. ✅ Take screenshot of "Request Rate by Operation" panel
6. ✅ Take screenshot of "Latency Distribution" panel
7. ✅ Take screenshot of full dashboard
8. ✅ Done! 🎉
