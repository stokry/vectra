---
layout: home
title: Vectra
---

# Welcome to Vectra Documentation

**Vectra** is a unified Ruby client for vector databases that allows you to write once and switch providers easily.

## Supported Vector Databases

- **Pinecone** - Managed vector database in the cloud
- **Qdrant** - Open-source vector database
- **Weaviate** - Open-source vector search engine
- **PostgreSQL with pgvector** - SQL database with vector support

## Quick Links

- [Installation Guide]({{ site.baseurl }}/guides/installation)
- [Getting Started]({{ site.baseurl }}/guides/getting-started)
- [API Reference]({{ site.baseurl }}/api/overview)
- [Examples]({{ site.baseurl }}/examples/basic-usage)
- [Contributing]({{ site.baseurl }}/community/contributing)

## Key Features

- 🔄 **Provider Agnostic** - Switch between different vector database providers with minimal code changes
- 🚀 **Easy Integration** - Works seamlessly with Rails and other Ruby frameworks
- 📊 **Vector Operations** - Create, search, update, and delete vectors
- 🔌 **Multiple Providers** - Support for leading vector database platforms
- 📈 **Instrumentation** - Built-in support for Datadog and New Relic monitoring
- 🗄️ **ActiveRecord Integration** - Native support for Rails models

## Get Started

```ruby
require 'vectra'

# Initialize client
client = Vectra::Client.new(provider: :pinecone, api_key: 'your-key')

# Upsert vectors
client.upsert(
  vectors: [
    { id: '1', values: [0.1, 0.2, 0.3], metadata: { text: 'example' } }
  ]
)

# Search
results = client.query(vector: [0.1, 0.2, 0.3], top_k: 5)
```

For more detailed examples, see [Basic Usage]({{ site.baseurl }}/examples/basic-usage).
