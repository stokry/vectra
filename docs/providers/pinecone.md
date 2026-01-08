---
layout: page
title: Pinecone
permalink: /providers/pinecone/
---

# Pinecone Provider

[Pinecone](https://www.pinecone.io/) is a managed vector database in the cloud.

## Setup

1. Create a Pinecone account at https://www.pinecone.io/
2. Create an index and get your API key
3. Set up Vectra:

```ruby
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  index_name: 'my-index',
  environment: 'us-west-4'
)
```

## Features

- ✅ Upsert vectors
- ✅ Query/search
- ✅ Delete vectors
- ✅ Fetch vectors by ID
- ✅ Index statistics
- ✅ Metadata filtering
- ✅ Namespace support

## Example

```ruby
# Initialize client
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'
)

# Upsert vectors
client.upsert(
  vectors: [
    { id: 'doc-1', values: [0.1, 0.2, 0.3], metadata: { title: 'Page 1' } },
    { id: 'doc-2', values: [0.2, 0.3, 0.4], metadata: { title: 'Page 2' } }
  ]
)

# Search
results = client.query(vector: [0.1, 0.2, 0.3], top_k: 5)
results.matches.each do |match|
  puts "#{match['id']}: #{match['score']}"
end
```

## Configuration Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `api_key` | String | Yes | Your Pinecone API key |
| `environment` | String | Yes | Pinecone environment (e.g., 'us-west-4') |
| `index_name` | String | No | Index name (if not set globally) |

## Documentation

- [Pinecone Docs](https://docs.pinecone.io/)
- [Pinecone API Reference](https://docs.pinecone.io/reference/api/)
