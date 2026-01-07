# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2025-01-07

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

### Provider Support

- ✅ Pinecone - Fully implemented
- ✅ pgvector (PostgreSQL) - Fully implemented
- 🚧 Qdrant - Stub implementation (planned for v0.2.0)
- 🚧 Weaviate - Stub implementation (planned for v0.3.0)

## [0.1.0] - 2024-XX-XX

### Added

- Initial release
- Pinecone provider with full support for:
  - Vector upsert, query, fetch, update, delete operations
  - Index management (list, describe, create, delete)
  - Namespace support
  - Metadata filtering
- Configuration system with global and per-client options
- Automatic retry logic with exponential backoff
- Comprehensive error handling with specific error classes:
  - `AuthenticationError` - API key issues
  - `RateLimitError` - Rate limiting with retry-after
  - `NotFoundError` - Resource not found
  - `ValidationError` - Invalid request parameters
  - `ServerError` - Server-side errors
  - `ConnectionError` - Network issues
  - `TimeoutError` - Request timeouts
- `Vector` class for vector representation with:
  - Cosine similarity calculation
  - Euclidean distance calculation
  - Metadata support
- `QueryResult` class with Enumerable support:
  - Score filtering
  - Easy iteration
  - Result statistics
- Full RSpec test suite
- YARD documentation

## Planned

### [0.2.0]

- Qdrant provider implementation
- Enhanced error messages
- Connection pooling
- Improved retry strategies

### [0.3.0]

- Weaviate provider implementation
- Batch operation improvements
- Performance optimizations
- Async operations support

### [1.0.0]

- Rails integration
- ActiveRecord-like DSL for vector models
- Background job integration (Sidekiq, GoodJob)
- Production-ready with full documentation
