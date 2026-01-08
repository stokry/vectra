# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Proactive Rate Limiting** (`Vectra::RateLimiter`)
  - Token bucket algorithm for smooth rate limiting
  - Burst support for handling traffic spikes
  - Per-provider rate limiter registry
  - `RateLimitedClient` wrapper for automatic throttling
  - Prevents API rate limit errors before they occur

- **Structured JSON Logging** (`Vectra::JsonLogger`)
  - Machine-readable JSON log format
  - Automatic operation logging via instrumentation
  - Custom metadata support
  - Integration with standard Ruby Logger via `JsonFormatter`
  - Log levels: debug, info, warn, error, fatal

- **Health Check Functionality** (`Vectra::HealthCheck`)
  - Built-in `client.health_check` method
  - Connectivity and latency testing
  - Optional index statistics inclusion
  - Pool health checking for pgvector
  - `AggregateHealthCheck` for multi-provider setups
  - JSON-serializable results

- **Error Tracking Integrations**
  - Sentry adapter with breadcrumbs, context, and fingerprinting
  - Honeybadger adapter with severity tags and configurable notifications
  - Automatic error context and grouping

- **Circuit Breaker Pattern** (`Vectra::CircuitBreaker`)
  - Three-state circuit (closed, open, half-open)
  - Automatic failover with fallback support
  - Per-provider circuit registry
  - Thread-safe implementation
  - Configurable failure/success thresholds

- **Credential Rotation** (`Vectra::CredentialRotator`)
  - Zero-downtime API key rotation
  - Pre-rotation validation
  - Rollback support
  - Multi-provider rotation manager
  - Per-provider rotation tracking

- **Audit Logging** (`Vectra::AuditLog`)
  - Structured audit events for compliance
  - Access, authentication, authorization logging
  - Configuration change tracking
  - Credential rotation audit trail
  - Automatic API key sanitization
  - Global audit logging support

## [v0.3.1](https://github.com/stokry/vectra/tree/v0.3.1) (2026-01-08)

[Full Changelog](https://github.com/stokry/vectra/compare/v0.3.0...v0.3.1)

## [v0.3.0](https://github.com/stokry/vectra/tree/v0.3.0) (2026-01-08)

[Full Changelog](https://github.com/stokry/vectra/compare/v0.2.2...v0.3.0)

### Added

- **Async Batch Operations** (`Vectra::Batch`)
  - Concurrent batch upsert with configurable worker count
  - Automatic chunking of large vector sets
  - Async delete and fetch operations
  - Error aggregation and partial success handling

- **Streaming Results** (`Vectra::Streaming`)
  - Lazy enumeration for large query result sets
  - Memory-efficient processing with automatic pagination
  - `query_each` and `query_stream` methods
  - Duplicate detection across pages

- **Caching Layer** (`Vectra::Cache` and `Vectra::CachedClient`)
  - In-memory LRU cache with configurable TTL
  - Transparent caching for query and fetch operations
  - Index-level cache invalidation
  - Thread-safe with mutex synchronization

- **Connection Pool with Warmup** (`Vectra::Pool`)
  - Configurable pool size and checkout timeout
  - Connection warmup at startup
  - Health checking and automatic reconnection
  - Pool statistics and monitoring

- **CI Benchmark Integration**
  - Weekly scheduled benchmark runs
  - PostgreSQL (pgvector) integration in CI
  - Benchmark result artifact storage

### Configuration

New configuration options:
- `cache_enabled` - Enable/disable caching (default: false)
- `cache_ttl` - Cache time-to-live in seconds (default: 300)
- `cache_max_size` - Maximum cache entries (default: 1000)
- `async_concurrency` - Concurrent workers for batch ops (default: 4)

### Dependencies

- Added `concurrent-ruby ~> 1.2` for thread-safe operations

## [v0.2.2](https://github.com/stokry/vectra/tree/v0.2.2) (2026-01-08)

[Full Changelog](https://github.com/stokry/vectra/compare/v0.2.1...v0.2.2)

## [v0.2.1](https://github.com/stokry/vectra/tree/v0.2.1) (2026-01-08)

[Full Changelog](https://github.com/stokry/vectra/compare/v0.2.0...v0.2.1)

### Added

- **Qdrant Provider** - Full Qdrant vector database support:
  - Vector upsert, query, fetch, update, delete operations
  - Collection management (create, list, describe, delete)
  - Multiple similarity metrics: cosine, euclidean, dot product
  - Namespace support via payload filtering
  - Advanced metadata filtering with Qdrant operators ($eq, $ne, $gt, $gte, $lt, $lte, $in, $nin)
  - Automatic point ID hashing for string IDs
  - Support for both local and cloud Qdrant instances
  - Optional API key authentication for local deployments

### Improved

- Enhanced error handling with `Faraday::RetriableResponse` support
- Configuration now allows optional API key for Qdrant and pgvector (local instances)
- Better retry middleware integration across all providers

### Provider Support

- ✅ Pinecone - Fully implemented
- ✅ pgvector (PostgreSQL) - Fully implemented
- ✅ Qdrant - Fully implemented
- 🚧 Weaviate - Stub implementation (planned for v0.4.0)

## [v0.2.0](https://github.com/stokry/vectra/tree/v0.2.0) (2026-01-08)

[Full Changelog](https://github.com/stokry/vectra/compare/v0.1.3...v0.2.0)

### Added

- **Instrumentation & Monitoring** - Track all vector operations with New Relic, Datadog, or custom handlers
- **ActiveRecord Integration** - `has_vector` DSL for seamless Rails model integration with automatic indexing
- **Rails Generator** - `rails generate vectra:install` for quick setup
- **Automatic Retry Logic** - Exponential backoff with jitter for transient database errors
- **Performance Benchmarks** - Measure batch operations and connection pooling performance
- **Comprehensive Documentation** - USAGE_EXAMPLES.md, IMPLEMENTATION_GUIDE.md with 10+ real-world examples

### Improved

- All Client methods now instrumented (upsert, query, fetch, update, delete)
- pgvector Connection module includes retry logic with smart error detection
- Configuration expanded with instrumentation, pool_size, batch_size, max_retries options

### Documentation

- Added USAGE_EXAMPLES.md with e-commerce search, RAG chatbot, duplicate detection examples
- Added IMPLEMENTATION_GUIDE.md for developers implementing new features
- Added NEW_FEATURES_v0.2.0.md with migration guide

## [v0.1.3](https://github.com/stokry/vectra/tree/v0.1.3) (2026-01-07)

[Full Changelog](https://github.com/stokry/vectra/compare/v0.1.1...v0.1.3)

## [v0.1.1](https://github.com/stokry/vectra/tree/v0.1.1) (2026-01-07)

[Full Changelog](https://github.com/stokry/vectra/compare/0ab2ea7b42d7fbf0b540b24889cc2b24254fef2e...v0.1.1)

### Added

- **pgvector provider** - Full PostgreSQL with pgvector extension support:
  - Vector upsert, query, fetch, update, delete operations
  - Index (table) management with automatic schema creation
  - Multiple similarity metrics: cosine, euclidean, inner product
  - Namespace support via namespace column
  - Metadata filtering with JSONB
  - IVFFlat index creation for fast similarity search
- `Vectra.pgvector` convenience method for creating pgvector clients
- Comprehensive unit and integration tests for pgvector provider

### Changed

- Updated gemspec description to include pgvector
- Added `pg` gem as development dependency

## Planned

### [0.4.0]

- Weaviate provider implementation
- Additional similarity metrics
- Vector quantization support

### [1.0.0]

- Background job integration (Sidekiq, GoodJob)
- Production-ready with full documentation
- Performance monitoring dashboard
