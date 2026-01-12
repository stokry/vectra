---
layout: home
title: Vectra
---

```ruby
require 'vectra'

# Initialize any provider with the same API
client = Vectra::Client.new(
  provider: :pinecone,     # or :qdrant, :weaviate, :pgvector
  api_key: ENV['API_KEY'],
  host: 'your-host.example.com'
)

# Store vectors with metadata
client.upsert(
  vectors: [
    { 
      id: 'doc-1', 
      values: [0.1, 0.2, 0.3, ...],  # Your embedding
      metadata: { title: 'Getting Started with AI' }
    }
  ]
)

# Search by similarity
results = client.query(
  vector: [0.1, 0.2, 0.3, ...],
  top_k: 10,
  filter: { category: 'tutorials' }
)

results.each do |match|
  puts "#{match['id']}: #{match['score']}"
end

# Hybrid search (semantic + keyword)
results = client.hybrid_search(
  index: 'docs',
  vector: embedding,
  text: 'ruby programming',
  alpha: 0.7  # 70% semantic, 30% keyword
)
```
