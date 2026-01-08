---
layout: page
title: Basic Usage
permalink: /examples/basic-usage/
---

# Basic Usage Examples

## Simple Search

```ruby
require 'vectra'

client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'
)

# Search for similar vectors
results = client.query(
  vector: [0.1, 0.2, 0.3],
  top_k: 5
)

puts results.matches.count
```

## Batch Operations

```ruby
# Upsert multiple vectors at once
vectors = [
  { id: '1', values: [0.1, 0.2, 0.3], metadata: { title: 'Doc 1' } },
  { id: '2', values: [0.2, 0.3, 0.4], metadata: { title: 'Doc 2' } },
  { id: '3', values: [0.3, 0.4, 0.5], metadata: { title: 'Doc 3' } }
]

client.upsert(vectors: vectors)

# Delete multiple vectors
client.delete(ids: ['1', '2', '3'])
```

## Rails Integration

```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.provider = :pgvector
  config.database = Rails.configuration.database_configuration[Rails.env]['database']
end

# app/models/document.rb
class Document < ApplicationRecord
  include Vectra::ActiveRecord
  
  vector_search :embedding
  
  def generate_embedding
    # Generate embedding using OpenAI, Cohere, etc.
    embedding_vector = generate_vector_from_text(content)
    self.embedding = embedding_vector
  end
end

# Usage
doc = Document.find(1)
similar_docs = doc.vector_search(limit: 10)
```

## With Metadata Filtering

```ruby
results = client.query(
  vector: [0.1, 0.2, 0.3],
  top_k: 10,
  include_metadata: true
)

results.matches.each do |match|
  puts "ID: #{match['id']}"
  puts "Score: #{match['score']}"
  puts "Metadata: #{match['metadata']}"
end
```

## Error Handling

```ruby
begin
  client.query(vector: [0.1, 0.2, 0.3])
rescue Vectra::ConnectionError => e
  puts "Connection failed: #{e.message}"
rescue Vectra::ValidationError => e
  puts "Invalid input: #{e.message}"
rescue => e
  puts "Unexpected error: #{e.message}"
end
```

See [Getting Started]({{ site.baseurl }}/guides/getting-started) for more examples.
