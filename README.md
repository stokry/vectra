# Vectra 🚀

[![Gem Version](https://badge.fury.io/rb/vectra-client.svg)](https://rubygems.org/gems/vectra-client)
[![CI](https://github.com/stokry/vectra/actions/workflows/ci.yml/badge.svg)](https://github.com/stokry/vectra/actions)
[![codecov](https://codecov.io/gh/stokry/vectra/branch/main/graph/badge.svg)](https://codecov.io/gh/stokry/vectra)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.0-4baaaa.svg)](CODE_OF_CONDUCT.md)

> **A unified Ruby client for vector databases.** Write once, switch vector database providers seamlessly. Perfect for AI/ML applications, semantic search, and RAG (Retrieval Augmented Generation) systems.

## 📖 Complete Documentation

**Full documentation, guides, and API reference available at:** [**https://vectra-docs.netlify.app/**](https://vectra-docs.netlify.app/)

This README provides a quick overview. For detailed guides, examples, and API documentation, visit the official documentation site above.

---

## ✨ Key Features

- 🔌 **Provider Agnostic** - Switch between vector database providers with minimal code changes
- 🚀 **Production Ready** - Built for Ruby 3.2+ with comprehensive test coverage (95%+)
- 🔄 **Resilient** - Built-in retry logic with exponential backoff and circuit breaker patterns
- 📊 **Rich Results** - Enumerable query results with advanced filtering and mapping capabilities
- 🛡️ **Type Safe** - Comprehensive input validation and meaningful error messages
- 📈 **Observable** - Native instrumentation support for Datadog and New Relic
- 🏗️ **Rails Ready** - Seamless ActiveRecord integration with migrations support
- 📚 **Well Documented** - Extensive YARD documentation and comprehensive examples

## 🗄️ Supported Vector Databases

| Provider | Type | Status | Docs |
|----------|------|--------|------|
| **Pinecone** | Managed Cloud | ✅ Fully Supported | [Guide](https://vectra-docs.netlify.app/providers/pinecone) |
| **PostgreSQL + pgvector** | SQL Database | ✅ Fully Supported | [Guide](https://vectra-docs.netlify.app/providers/pgvector) |
| **Qdrant** | Open Source | ✅ Fully Supported | [Guide](https://vectra-docs.netlify.app/providers/qdrant) |
| **Weaviate** | Open Source | ✅ Fully Supported | [Guide](https://vectra-docs.netlify.app/providers/weaviate) |



## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem 'vectra-client'
```

Then execute:

```bash
bundle install
```

Or install directly:

```bash
gem install vectra-client
```

### RubyGems Information

- **Gem Name:** `vectra-client`
- **Latest Version:** 0.2.1
- **Repository:** [stokry/vectra](https://github.com/stokry/vectra)
- **RubyGems Page:** [vectra-client](https://rubygems.org/gems/vectra-client)
- **License:** MIT
- **Ruby Requirement:** >= 3.2.0

### Provider-Specific Setup

Each vector database may require additional dependencies:

**PostgreSQL + pgvector:**
```ruby
gem 'pg', '~> 1.5'
```

**For Instrumentation:**
```ruby
gem 'dogstatsd-ruby'      # Datadog
gem 'newrelic_rpm'        # New Relic
```

## 🚀 Quick Start

### 1. Initialize a Client

```ruby
require 'vectra'

# Pinecone
client = Vectra::Client.new(
  provider: :pinecone,
  api_key: ENV['PINECONE_API_KEY'],
  environment: 'us-west-4'
)

# PostgreSQL + pgvector
client = Vectra::Client.new(
  provider: :pgvector,
  database: 'my_app_production',
  host: 'localhost'
)

# Qdrant
client = Vectra::Client.new(
  provider: :qdrant,
  host: 'http://localhost:6333'
)
```

### 2. Upsert Vectors

```ruby
client.upsert(
  vectors: [
    { 
      id: 'doc-1', 
      values: [0.1, 0.2, 0.3], 
      metadata: { title: 'Introduction to AI' }
    },
    { 
      id: 'doc-2', 
      values: [0.2, 0.3, 0.4], 
      metadata: { title: 'Advanced ML Techniques' }
    }
  ]
)
```

### 3. Search for Similar Vectors

```ruby
results = client.query(
  vector: [0.1, 0.2, 0.3],
  top_k: 5
)

results.matches.each do |match|
  puts "#{match['id']}: #{match['score']}"
  puts "  Metadata: #{match['metadata']}"
end
```

### 4. Delete Vectors

```ruby
client.delete(ids: ['doc-1', 'doc-2'])
```

## 📖 Full Documentation

For complete documentation, examples, and guides, visit:

**👉 [https://vectra-docs.netlify.app/](https://vectra-docs.netlify.app/)**

### Documentation Includes:

- [Installation Guide](https://vectra-docs.netlify.app/guides/installation)
- [Getting Started](https://vectra-docs.netlify.app/guides/getting-started)
- [Provider Guides](https://vectra-docs.netlify.app/providers)
  - [Pinecone](https://vectra-docs.netlify.app/providers/pinecone)
  - [PostgreSQL + pgvector](https://vectra-docs.netlify.app/providers/pgvector)
  - [Qdrant](https://vectra-docs.netlify.app/providers/qdrant)
  - [Weaviate](https://vectra-docs.netlify.app/providers/weaviate)
- [API Reference](https://vectra-docs.netlify.app/api/overview)
- [Code Examples](https://vectra-docs.netlify.app/examples)
- [Rails Integration Guide](https://vectra-docs.netlify.app/providers/pgvector/)

---

## 💡 Use Cases

### Semantic Search
Build intelligent search that understands meaning, not just keywords. Perfect for product discovery, knowledge base search, and content recommendation.

### Retrieval Augmented Generation (RAG)
Combine vector databases with LLMs to enable precise information retrieval for AI applications, chatbots, and knowledge systems.

### Duplicate Detection
Identify and deduplicate similar items across your dataset using vector similarity.

### Recommendation Systems
Power personalized recommendations based on user behavior and content similarity.

---


## 🛠️ Development

### Set Up Development Environment

```bash
git clone https://github.com/stokry/vectra.git
cd vectra
bundle install
```

### Run Tests

```bash
# All tests
bundle exec rspec

# Unit tests only
bundle exec rspec spec/vectra

# Integration tests only
bundle exec rspec spec/integration
```

### Code Quality

```bash
# Run RuboCop linter
bundle exec rubocop

# Generate documentation
bundle exec rake docs
```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

See [CHANGELOG.md](CHANGELOG.md) for the complete history of changes.

## 🔗 Links

- **Documentation:** [https://vectra-docs.netlify.app/](https://vectra-docs.netlify.app/)
- **RubyGems:** [vectra-client](https://rubygems.org/gems/vectra-client)
- **GitHub:** [stokry/vectra](https://github.com/stokry/vectra)
- **Issues:** [Report a bug](https://github.com/stokry/vectra/issues)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Built with ❤️ by the Vectra community**
- 🚧 Performance optimizations

### v1.0.0
- 🚧 Rails integration
- 🚧 ActiveRecord-like DSL
- 🚧 Background job support
- 🚧 Full documentation

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/stokry/vectra.

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Acknowledgments

Inspired by the simplicity of Ruby database gems and the need for a unified vector database interface.
