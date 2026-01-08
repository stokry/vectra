---
layout: page
title: Providers
permalink: /providers/
---

# Vector Database Providers

Vectra supports multiple vector database providers. Choose the one that best fits your needs.

## Supported Providers

| Provider | Type | Best For |
|----------|------|----------|
| [**Pinecone**]({{ site.baseurl }}/providers/pinecone) | Managed Cloud | Production, Zero ops |
| [**Qdrant**]({{ site.baseurl }}/providers/qdrant) | Open Source | Self-hosted, Performance |
| [**Weaviate**]({{ site.baseurl }}/providers/weaviate) | Open Source | Semantic search, GraphQL |
| [**pgvector**]({{ site.baseurl }}/providers/pgvector) | PostgreSQL | SQL integration, ACID |

## Quick Comparison

<div class="tma-comparison-grid">
  <div class="tma-comparison-card">
    <h4>Pinecone</h4>
    <ul>
      <li class="pro">Fully managed service</li>
      <li class="pro">Easy setup</li>
      <li class="pro">Highly scalable</li>
      <li class="con">Cloud only</li>
      <li class="con">Paid service</li>
    </ul>
  </div>
  <div class="tma-comparison-card">
    <h4>Qdrant</h4>
    <ul>
      <li class="pro">Open source</li>
      <li class="pro">Self-hosted option</li>
      <li class="pro">High performance</li>
      <li class="pro">Cloud option available</li>
      <li class="con">More configuration</li>
    </ul>
  </div>
  <div class="tma-comparison-card">
    <h4>Weaviate</h4>
    <ul>
      <li class="pro">Open source</li>
      <li class="pro">Semantic search</li>
      <li class="pro">GraphQL API</li>
      <li class="pro">Multi-model support</li>
      <li class="con">More complex setup</li>
    </ul>
  </div>
  <div class="tma-comparison-card">
    <h4>pgvector</h4>
    <ul>
      <li class="pro">SQL database</li>
      <li class="pro">ACID transactions</li>
      <li class="pro">Use existing Postgres</li>
      <li class="pro">Very affordable</li>
      <li class="con">Not vector-specialized</li>
    </ul>
  </div>
</div>

## Switching Providers

One of Vectra's key features is easy provider switching:

```ruby
# Just change the provider - your code stays the same!
client = Vectra::Client.new(provider: :qdrant, host: 'localhost:6333')

# All operations work identically
client.upsert(vectors: [...])
results = client.query(vector: [...], top_k: 5)
```

## Next Steps

- [Getting Started Guide]({{ site.baseurl }}/guides/getting-started)
- [API Reference]({{ site.baseurl }}/api/overview)
