---
layout: page
title: Providers
permalink: /providers/
---

# Vector Database Providers

Vectra supports multiple vector database providers. Choose the one that best fits your needs:

## Supported Providers

| Provider | Type | Best For | Documentation |
|----------|------|----------|---|
| **Pinecone** | Managed Cloud | Production, Fully managed | [Guide]({{ site.baseurl }}/providers/pinecone) |
| **Qdrant** | Open Source | Self-hosted, High performance | [Guide]({{ site.baseurl }}/providers/qdrant) |
| **Weaviate** | Open Source | Semantic search, GraphQL | [Guide]({{ site.baseurl }}/providers/weaviate) |
| **PostgreSQL + pgvector** | SQL Database | SQL integration, ACID | [Guide]({{ site.baseurl }}/providers/pgvector) |

## Quick Comparison

### Pinecone
- ✅ Fully managed service
- ✅ Easy setup
- ✅ Scalable
- ❌ Cloud only
- ❌ Paid service

### Qdrant
- ✅ Open source
- ✅ Self-hosted
- ✅ High performance
- ✅ Multiple deployment options
- ❌ More configuration needed

### Weaviate
- ✅ Open source
- ✅ Semantic search
- ✅ GraphQL API
- ✅ Multi-model support
- ❌ More complex

### PostgreSQL + pgvector
- ✅ SQL database
- ✅ ACID transactions
- ✅ Existing infrastructure
- ✅ Affordable
- ❌ Not specialized for vectors

## Switching Providers

One of Vectra's key features is easy provider switching:

```ruby
# All it takes is changing one line!
client = Vectra::Client.new(provider: :qdrant)

# All your code remains the same
results = client.query(vector: [0.1, 0.2, 0.3])
```

See the [Getting Started Guide]({{ site.baseurl }}/guides/getting-started) for more information.
