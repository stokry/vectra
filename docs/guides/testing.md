---
layout: page
title: Testing Guide
permalink: /guides/testing/
---

# Testing Guide

How to test code that uses Vectra without running a real vector database.

Vectra ships with a **Memory provider** – an in-memory vector store designed for **RSpec/Minitest, local dev, and CI**.

> Not for production use. All data is stored in memory and lost when the process exits.

---

## 1. Configure Vectra for Tests

### Option A: Global Config (Rails)

```ruby
# config/initializers/vectra.rb
require 'vectra'

Vectra.configure do |config|
  if Rails.env.test?
    config.provider = :memory
  else
    config.provider = :qdrant
    config.host     = ENV.fetch('QDRANT_HOST', 'http://localhost:6333')
    config.api_key  = ENV['QDRANT_API_KEY']
  end
end
```

Then in your application code and tests:

```ruby
client = Vectra::Client.new
```

### Option B: Direct Construction in Tests

```ruby
require 'vectra'

RSpec.describe 'My vector code' do
  let(:client) { Vectra.memory }

  it 'searches using in-memory provider' do
    client.upsert(
      index: 'documents',
      vectors: [
        { id: 'doc-1', values: [0.1, 0.2, 0.3], metadata: { title: 'Hello' } }
      ]
    )

    results = client.query(index: 'documents', vector: [0.1, 0.2, 0.3], top_k: 5)
    expect(results.ids).to include('doc-1')
  end
end
```

---

## 2. Reset State Between Tests

The Memory provider exposes `clear!` to wipe all in-memory data.

```ruby
# spec/support/vectra_memory.rb
RSpec.configure do |config|
  config.before(:each, vectra: :memory) do
    Vectra::Providers::Memory.instance.clear!
  end
end
```

Usage:

```ruby
RSpec.describe SearchService, vectra: :memory do
  it 'returns expected results' do
    # state is clean here
  end
end
```

If you use global `config.provider = :memory` in test env, this hook ensures tests are isolated.

---

## 3. Testing Application Code (Service Example)

Assume you have a simple service that wraps Vectra:

```ruby
# app/services/search_service.rb
class SearchService
  def self.search(query:, limit: 10)
    client = Vectra::Client.new

    embedding = EmbeddingService.generate(query)

    client.query(
      index: 'documents',
      vector: embedding,
      top_k: limit,
      include_metadata: true
    )
  end
end
```

You can test it **without** any external DB:

```ruby
# spec/services/search_service_spec.rb
require 'rails_helper'

RSpec.describe SearchService, vectra: :memory do
  let(:client) { Vectra.memory }

  before do
    # Seed in-memory vectors
    client.upsert(
      index: 'documents',
      vectors: [
        { id: 'doc-1', values: [1.0, 0.0, 0.0], metadata: { title: 'Ruby Vectors' } },
        { id: 'doc-2', values: [0.0, 1.0, 0.0], metadata: { title: 'PostgreSQL' } }
      ]
    )

    # Stub client used inside SearchService to our memory client
    allow(Vectra::Client).to receive(:new).and_return(client)

    # Stub embedding service to return a deterministic vector
    allow(EmbeddingService).to receive(:generate).and_return([1.0, 0.0, 0.0])
  end

  it 'returns most relevant document first' do
    results = SearchService.search(query: 'ruby vectors', limit: 2)

    expect(results.first.metadata['title']).to eq('Ruby Vectors')
  end
end
```

---

## 4. Testing `has_vector` Models

Example model:

```ruby
# app/models/document.rb
class Document < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding,
    provider: :memory,
    index: 'documents',
    dimension: 3,
    metadata_fields: [:title]
end
```

### Model Spec

```ruby
# spec/models/document_spec.rb
require 'rails_helper'

RSpec.describe Document, vectra: :memory do
  it 'indexes on create and can be searched' do
    doc = Document.create!(
      title: 'Hello',
      embedding: [1.0, 0.0, 0.0]
    )

    results = Document.vector_search(
      embedding: [1.0, 0.0, 0.0],
      limit: 5
    )

    expect(results.map(&:id)).to include(doc.id)
  end
end
```

---

## 5. CI Considerations

- ✅ No external services needed (no Docker, no cloud credentials)
- ✅ Fast and deterministic tests
- ✅ Same Vectra API as real providers

Recommended CI pattern:

1. Use `provider: :memory` for the majority of tests.
2. Have a **small set of integration tests** (separate job) that hit a real provider (e.g. Qdrant in Docker) if needed.

---

## 6. Useful Links

- [Memory Provider Docs](/providers/memory/)
- [Recipes & Patterns](/guides/recipes/)
- [Rails Integration Guide](/guides/rails-integration/)
- [API Cheatsheet](/api/cheatsheet/)
