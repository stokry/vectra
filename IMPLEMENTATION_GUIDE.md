# 🚀 VECTRA IMPLEMENTATION GUIDE

Step-by-step guide to implementing new features in your Vectra gem.

## Table of Contents

1. [Instrumentation & Monitoring](#1-instrumentation--monitoring)
2. [Rails Generator](#2-rails-generator)
3. [ActiveRecord Integration](#3-activerecord-integration)
4. [Retry Logic for pgvector](#4-retry-logic-for-pgvector)
5. [Performance Benchmarks](#5-performance-benchmarks)
6. [Testing New Features](#6-testing-new-features)

---

## 1. Instrumentation & Monitoring

### What was added:

- **Core:** `lib/vectra/instrumentation.rb` - Event system for tracking operations
- **New Relic:** `lib/vectra/instrumentation/new_relic.rb`
- **Datadog:** `lib/vectra/instrumentation/datadog.rb`

### How to use:

#### Enable instrumentation in configuration:

```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.instrumentation = true
end
```

#### New Relic:

```ruby
require 'vectra/instrumentation/new_relic'
Vectra::Instrumentation::NewRelic.setup!
```

Automatically tracks:
- `Custom/Vectra/pgvector/query/duration`
- `Custom/Vectra/pgvector/upsert/success`
- etc.

#### Datadog:

```ruby
require 'vectra/instrumentation/datadog'
Vectra::Instrumentation::Datadog.setup!(
  host: 'localhost',
  port: 8125
)
```

Sends metrics:
- `vectra.operation.duration` (timing)
- `vectra.operation.count` (counter)
- `vectra.operation.error` (counter)

#### Custom instrumentation:

```ruby
Vectra.on_operation do |event|
  puts "#{event.operation} took #{event.duration}ms"

  if event.failure?
    Sentry.capture_exception(event.error)
  end

  # event.operation  => :query, :upsert, etc.
  # event.provider   => :pgvector, :pinecone
  # event.index      => 'documents'
  # event.duration   => 123.45 (ms)
  # event.metadata   => { result_count: 10, vector_count: 1 }
  # event.error      => Exception or nil
end
```

### Integration into providers:

To add instrumentation to a provider operation, wrap it:

```ruby
# In provider method:
def upsert(index:, vectors:, namespace: nil)
  Instrumentation.instrument(
    operation: :upsert,
    provider: provider_name,
    index: index,
    metadata: { vector_count: vectors.size }
  ) do
    # Actual upsert logic
    perform_upsert(index, vectors, namespace)
  end
end
```

---

## 2. Rails Generator

### What was added:

- **Generator:** `lib/generators/vectra/install_generator.rb`
- **Templates:**
  - `lib/generators/vectra/templates/vectra.rb` - Initializer template
  - `lib/generators/vectra/templates/enable_pgvector_extension.rb` - Migration template

### How to use:

```bash
# Basic install
rails generate vectra:install

# With options
rails generate vectra:install --provider=pgvector --instrumentation=true
rails generate vectra:install --provider=pinecone --api-key=xxx
```

### What it does:

1. Creates `config/initializers/vectra.rb`
2. For pgvector: Creates migration to enable `vector` extension
3. Shows setup instructions based on provider

### Customization:

To add a new provider to generator:

1. Add to `templates/vectra.rb`:

```erb
<%- elsif options[:provider] == 'my_provider' -%>
# My Provider credentials
config.api_key = Rails.application.credentials.dig(:my_provider, :api_key)
config.host = Rails.application.credentials.dig(:my_provider, :host)
<%- end -%>
```

2. Add instructions in `install_generator.rb`:

```ruby
def show_my_provider_instructions
  say "  2. Add to credentials:", :yellow
  say "     my_provider:", :cyan
  say "       api_key: your_api_key_here", :cyan
end
```

---

## 3. ActiveRecord Integration

### What was added:

- **Module:** `lib/vectra/active_record.rb`

### How to use:

#### 1. Include in model:

```ruby
class Document < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding,
             dimension: 384,
             provider: :pgvector,
             index: 'documents',
             auto_index: true,  # Auto-sync on save
             metadata_fields: [:title, :category, :status]
end
```

#### 2. Generate embeddings:

```ruby
class Document < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :embedding, dimension: 384

  before_validation :generate_embedding, if: :content_changed?

  private

  def generate_embedding
    self.embedding = EmbeddingService.generate(content)
  end
end
```

#### 3. Search:

```ruby
# Vector search (loads AR objects)
query_vector = EmbeddingService.generate('search query')
results = Document.vector_search(query_vector, limit: 10)

# With filters
results = Document.vector_search(
  query_vector,
  limit: 10,
  filter: { status: 'published' },
  score_threshold: 0.8
)

# Each result has .vector_score
results.each do |doc|
  puts "#{doc.title} - Score: #{doc.vector_score}"
end

# Find similar to specific document
similar_docs = doc.similar(limit: 5, filter: { category: doc.category })

# Similar without loading AR objects (just vector results)
results = Document.vector_search(query_vector, limit: 10, load_records: false)
# Returns Vectra::QueryResult instead
```

#### 4. Manual control:

```ruby
# Disable auto-index:
has_vector :embedding, dimension: 384, auto_index: false

# Manual operations:
doc.index_vector!   # Index this record
doc.delete_vector!  # Remove from index
```

### How it works:

1. **Callbacks:** Hooks into `after_save` and `after_destroy`
2. **Vector ID:** Generates ID as `{table_name}_{record_id}`
3. **Metadata:** Extracts specified fields into vector metadata
4. **Search:** Queries Vectra, then loads AR records by ID

### Advanced usage:

#### Custom index name:

```ruby
has_vector :embedding, dimension: 384, index: "custom_index_#{Rails.env}"
```

#### Multiple vector attributes:

```ruby
class Product < ApplicationRecord
  include Vectra::ActiveRecord

  has_vector :title_embedding, dimension: 384, index: 'products_title'
  has_vector :desc_embedding, dimension: 384, index: 'products_desc'
end

# Search either:
Product.vector_search(query_vector, limit: 10)  # Uses first defined
```

#### Background indexing:

```ruby
has_vector :embedding, dimension: 384, auto_index: false

after_commit :index_async, on: [:create, :update]

def index_async
  IndexVectorJob.perform_later(self.class.name, id)
end

# Job:
class IndexVectorJob < ApplicationJob
  def perform(model_class, record_id)
    model = model_class.constantize.find(record_id)
    model.index_vector!
  end
end
```

---

## 4. Retry Logic for pgvector

### What was added:

- **Module:** `lib/vectra/retry.rb`

### How to use:

#### In pgvector provider:

```ruby
# lib/vectra/providers/pgvector/connection.rb
module Vectra
  module Providers
    class Pgvector < Base
      include Retry  # Add this

      module Connection
        def execute(sql, params = [])
          # Wrap with retry
          with_retry(max_attempts: 3) do
            connection.exec_params(sql, params)
          end
        rescue PG::Error => e
          handle_pg_error(e)
        end
      end
    end
  end
end
```

#### Custom retry config:

```ruby
with_retry(
  max_attempts: 5,
  base_delay: 1.0,    # Start with 1s
  max_delay: 30.0,    # Cap at 30s
  backoff_factor: 2,  # 1s, 2s, 4s, 8s, 16s, 30s
  jitter: true        # Add ±25% randomness
) do
  perform_operation
end
```

### Retryable errors:

Automatically retries:
- `PG::ConnectionBad`
- `PG::UnableToSend`
- `PG::TooManyConnections`
- `PG::SerializationFailure`
- `PG::DeadlockDetected`
- `ConnectionPool::TimeoutError`
- Any error with "timeout" or "connection" in message

### How it works:

1. **Exponential backoff:** `delay = base_delay * (2 ^ attempt)`
2. **Jitter:** Adds randomness to prevent thundering herd
3. **Max delay:** Caps at 30s by default
4. **Logging:** Logs each retry attempt with delay

---

## 5. Performance Benchmarks

### What was added:

- `benchmarks/batch_operations_benchmark.rb`
- `benchmarks/connection_pooling_benchmark.rb`

### How to run:

```bash
# Batch operations
DATABASE_URL=postgres://localhost/vectra_benchmark \
  ruby benchmarks/batch_operations_benchmark.rb

# Connection pooling
DATABASE_URL=postgres://localhost/vectra_benchmark \
  ruby benchmarks/connection_pooling_benchmark.rb
```

### What they measure:

#### Batch operations:
- **Vector counts:** 100, 500, 1K, 5K, 10K
- **Batch sizes:** 50, 100, 250, 500
- **Metrics:** avg time, vectors/sec, batches count

Example output:
```
1000 vectors:
  Batch size  50: 2.134s avg (468 vectors/sec, 20 batches)
  Batch size 100: 1.892s avg (529 vectors/sec, 10 batches)
  Batch size 250: 1.645s avg (608 vectors/sec, 4 batches)
  Batch size 500: 1.523s avg (657 vectors/sec, 2 batches)
```

#### Connection pooling:
- **Pool sizes:** 5, 10, 20
- **Thread counts:** 1, 2, 5, 10, 20
- **Metrics:** total time, ops/sec, pool availability

Example output:
```
Pool Size: 10
   1 threads: 5.21s total (9.6 ops/sec) Pool: 9/10 available
   5 threads: 5.34s total (46.8 ops/sec) Pool: 5/10 available
  10 threads: 5.67s total (88.2 ops/sec) Pool: 0/10 available
```

### Creating custom benchmarks:

```ruby
# benchmarks/my_custom_benchmark.rb
require 'bundler/setup'
require 'vectra'
require 'benchmark'

client = Vectra.pgvector(connection_url: ENV['DATABASE_URL'])

# Setup
client.provider.create_index(name: 'test', dimension: 384)

# Benchmark
time = Benchmark.realtime do
  # Your code here
end

puts "Took: #{time.round(2)}s"

# Cleanup
client.provider.delete_index(name: 'test')
```

---

## 6. Testing New Features

### Instrumentation tests:

```ruby
# spec/vectra/instrumentation_spec.rb
RSpec.describe Vectra::Instrumentation do
  before { described_class.clear_handlers! }

  it "calls handlers on operations" do
    events = []
    Vectra.on_operation { |event| events << event }

    Vectra::Instrumentation.instrument(
      operation: :test,
      provider: :pgvector,
      index: 'test_index'
    ) do
      sleep 0.1
    end

    expect(events.size).to eq(1)
    expect(events.first.operation).to eq(:test)
    expect(events.first.duration).to be >= 100
    expect(events.first.success?).to be true
  end

  it "captures errors" do
    events = []
    Vectra.on_operation { |event| events << event }

    expect {
      Vectra::Instrumentation.instrument(
        operation: :test,
        provider: :pgvector,
        index: 'test'
      ) do
        raise StandardError, "Test error"
      end
    }.to raise_error(StandardError)

    expect(events.first.failure?).to be true
    expect(events.first.error.message).to eq("Test error")
  end
end
```

### ActiveRecord integration tests:

```ruby
# spec/vectra/active_record_spec.rb
RSpec.describe Vectra::ActiveRecord do
  before do
    # Create test model
    stub_const('TestDocument', Class.new(ApplicationRecord) do
      self.table_name = 'documents'
      include Vectra::ActiveRecord

      has_vector :embedding,
                 dimension: 384,
                 index: 'test_docs',
                 metadata_fields: [:title, :category]
    end)
  end

  it "auto-indexes on create" do
    expect_any_instance_of(Vectra::Client).to receive(:upsert)

    TestDocument.create!(
      title: 'Test',
      embedding: Array.new(384) { rand }
    )
  end

  it "searches vectors" do
    query_vector = Array.new(384) { rand }

    allow_any_instance_of(Vectra::Client).to receive(:query).and_return(
      Vectra::QueryResult.from_response(matches: [
        { id: 'test_docs_1', score: 0.95, metadata: {} }
      ])
    )

    results = TestDocument.vector_search(query_vector, limit: 10)
    expect(results.size).to be > 0
  end
end
```

### Retry logic tests:

```ruby
# spec/vectra/retry_spec.rb
RSpec.describe Vectra::Retry do
  let(:config) { double(max_retries: 3, retry_delay: 0.01, logger: nil) }
  let(:test_class) do
    Class.new do
      include Vectra::Retry
      attr_accessor :config
    end
  end

  subject { test_class.new.tap { |obj| obj.config = config } }

  it "retries on connection errors" do
    attempts = 0
    allow(subject).to receive(:sleep)

    result = subject.with_retry do
      attempts += 1
      raise PG::ConnectionBad, "Connection failed" if attempts < 3
      "success"
    end

    expect(attempts).to eq(3)
    expect(result).to eq("success")
  end

  it "stops after max attempts" do
    attempts = 0
    allow(subject).to receive(:sleep)

    expect {
      subject.with_retry(max_attempts: 3) do
        attempts += 1
        raise PG::ConnectionBad, "Connection failed"
      end
    }.to raise_error(PG::ConnectionBad)

    expect(attempts).to eq(3)
  end

  it "doesn't retry non-retryable errors" do
    attempts = 0

    expect {
      subject.with_retry do
        attempts += 1
        raise ArgumentError, "Invalid argument"
      end
    }.to raise_error(ArgumentError)

    expect(attempts).to eq(1)
  end
end
```

---

## Rollout Checklist

### Phase 1: Core Features (v0.2.0)
- [x] Instrumentation hooks
- [x] Rails generator
- [x] ActiveRecord integration
- [x] Retry logic
- [x] Performance benchmarks
- [ ] Update README with new features
- [ ] Write migration guide
- [ ] Add YARD docs to new classes
- [ ] Update CHANGELOG

### Phase 2: Testing (before v0.2.0 release)
- [ ] Unit tests for instrumentation (>90% coverage)
- [ ] Integration tests for ActiveRecord
- [ ] Retry logic edge cases
- [ ] Generator tests
- [ ] Update CI to run benchmarks

### Phase 3: Documentation
- [ ] Usage examples for each feature
- [ ] API documentation (YARD)
- [ ] Blog post announcing features
- [ ] Update RubyGems description

### Phase 4: Release
- [ ] Bump version to 0.2.0
- [ ] Update CHANGELOG
- [ ] Create GitHub release
- [ ] Publish to RubyGems
- [ ] Announce on Ruby communities

---

## Recommended Next Steps

1. **Implement instrumentation in Client methods**
   - Wrap upsert, query, fetch, etc. with `Instrumentation.instrument`

2. **Add retry logic to pgvector Connection module**
   - Include `Retry` module
   - Wrap `execute` method

3. **Test ActiveRecord integration thoroughly**
   - Create a demo Rails app
   - Test with real database
   - Document edge cases

4. **Run benchmarks on real hardware**
   - Different PostgreSQL versions
   - Different data sizes
   - Document optimal settings

5. **Write comprehensive tests**
   - Aim for 90%+ coverage
   - Include integration tests
   - Test error scenarios

6. **Update documentation**
   - README with new features
   - CHANGELOG entries
   - API docs (YARD)

---

## Questions & Troubleshooting

### Q: Instrumentation not working?

**Check:**
- `config.instrumentation = true` is set
- Handler is registered before operations run
- No errors in handler (check logs)

### Q: ActiveRecord auto-index not firing?

**Check:**
- `auto_index: true` is set
- Embedding attribute actually changed (`saved_change_to_embedding?`)
- No errors in callback (check logs)

### Q: Retry not working?

**Check:**
- Error is retryable (check `RETRYABLE_PG_ERRORS`)
- Not exceeded `max_attempts`
- `config.max_retries` is > 0

### Q: Poor benchmark results?

**Check:**
- PostgreSQL is tuned (`work_mem`, `shared_buffers`)
- Index exists (`CREATE INDEX USING ivfflat`)
- `batch_size` matches your workload
- `pool_size` matches concurrent connections

---

## Contributing

When implementing new features:

1. Follow existing code style (RuboCop passing)
2. Add comprehensive tests (>90% coverage)
3. Update documentation (README, YARD, CHANGELOG)
4. Add usage examples
5. Run benchmarks if performance-related
6. Update this guide with implementation details

---

Happy coding! 🚀
