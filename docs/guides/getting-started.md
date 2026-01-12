---
layout: page
title: Getting Started
permalink: /guides/getting-started/
---

# Getting Started with Vectra

## Initialize a Client

```ruby
require 'vectra'

# Initialize with Pinecone
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'
)
```

## Basic Operations

### Upsert Vectors

```ruby
client.upsert(
  vectors: [
    {
      id: 'vec-1',
      values: [0.1, 0.2, 0.3],
      metadata: { title: 'Document 1' }
    },
    {
      id: 'vec-2',
      values: [0.2, 0.3, 0.4],
      metadata: { title: 'Document 2' }
    }
  ]
)
```

### Query (Search)

```ruby
# Classic API
results = client.query(
  vector: [0.1, 0.2, 0.3],
  top_k: 5,
  include_metadata: true
)

results.each do |match|
  puts "ID: #{match.id}, Score: #{match.score}"
end

# Chainable Query Builder
results = client
  .query("my-index")
  .vector([0.1, 0.2, 0.3])
  .top_k(5)
  .with_metadata
  .execute

results.each do |match|
  puts "ID: #{match.id}, Score: #{match.score}"
end
```

### Delete Vectors

```ruby
client.delete(ids: ['vec-1', 'vec-2'])
```

### Get Vector Stats

```ruby
stats = client.stats
puts "Index dimension: #{stats['dimension']}"
puts "Vector count: #{stats['vector_count']}"
```

## Configuration

Create a configuration file (Rails: `config/initializers/vectra.rb`):

```ruby
Vectra.configure do |config|
  config.provider = :pinecone
  config.api_key = ENV['PINECONE_API_KEY']
  config.environment = 'us-west-4'
end

# Later in your code:
client = Vectra::Client.new
```

## Next Steps

- [API Reference]({{ site.baseurl }}/api/overview)
- [Provider Guides]({{ site.baseurl }}/providers)
- [Examples]({{ site.baseurl }}/examples/basic-usage)
