---
layout: page
title: Upgrading Vectra
permalink: /guides/migrations/upgrading-vectra/
---

# Upgrading Vectra

This guide helps you upgrade between versions of `vectra-client`.

## Checking Your Version

```ruby
require 'vectra'
puts Vectra::VERSION
# => "1.1.4"
```

Or in your Gemfile.lock:
```bash
grep vectra-client Gemfile.lock
```

## Upgrade Process

### 1. Update Gemfile

```ruby
gem 'vectra-client', '~> 1.1'
# Or specific version
gem 'vectra-client', '1.1.4'
```

Then:
```bash
bundle update vectra-client
```

### 2. Review Changelog

Check [CHANGELOG.md](https://github.com/stokry/vectra/blob/main/CHANGELOG.md) for breaking changes.

### 3. Run Tests

```bash
bundle exec rspec
```

## Version-Specific Upgrade Guides

### Upgrading to v1.1.x

#### New Features

- **Middleware system**: Rack-style middleware for extending functionality
- **Default index/namespace**: Auto-set from `config/vectra.yml` in Rails
- **Text search**: Keyword-only search across providers
- **Batch query**: `Batch.query_async` for concurrent queries
- **Client helpers**: `with_timeout`, `with_defaults`, `for_tenant`, `validate!`, `valid?`

#### Breaking Changes

None. v1.1.x is backward compatible with v1.0.x.

#### Migration Steps

1. **Update Gemfile**:
   ```ruby
   gem 'vectra-client', '~> 1.1'
   ```

2. **Optional: Use new features**:
   ```ruby
   # Middleware
   Vectra::Client.use Vectra::Middleware::Logging
   
   # Default index/namespace
   client = Vectra::Client.new(index: 'docs', namespace: 'default')
   
   # Text search
   results = client.text_search(index: 'docs', text: 'query', top_k: 10)
   ```

### Upgrading to v1.0.x

#### Breaking Changes

- **Namespace parameter**: Now optional and uses default if set
- **Response objects**: Query results return `Vectra::QueryResult` instead of raw hashes

#### Migration Steps

**Before (v0.x):**
```ruby
results = client.query(index: 'docs', vector: emb, top_k: 10)
results['matches'].each do |match|
  puts match['id']
end
```

**After (v1.0.x):**
```ruby
results = client.query(index: 'docs', vector: emb, top_k: 10)
results.each do |match|
  puts match.id  # String, not hash key
end
```

## Common Upgrade Issues

### Issue: Method Not Found

**Error:**
```
NoMethodError: undefined method `text_search' for #<Vectra::Client>
```

**Solution:**
Update to v1.1.1+:
```bash
bundle update vectra-client
```

### Issue: Middleware Not Working

**Error:**
```
NoMethodError: undefined method `use' for Vectra::Client:Class
```

**Solution:**
Update to v1.1.0+:
```bash
bundle update vectra-client
```

### Issue: Default Index Not Working

**Error:**
```
ValidationError: Index name cannot be nil
```

**Solution:**
In Rails, ensure `config/vectra.yml` has exactly one entry, or explicitly set:
```ruby
client = Vectra::Client.new(index: 'docs', ...)
```

## Testing After Upgrade

### 1. Validate Configuration

```ruby
client.validate!
```

### 2. Test Basic Operations

```ruby
# Upsert
result = client.upsert(index: 'test', vectors: [test_vector])
expect(result[:upserted_count]).to eq(1)

# Query
results = client.query(index: 'test', vector: test_vector, top_k: 1)
expect(results.size).to eq(1)

# Fetch
vectors = client.fetch(index: 'test', ids: ['test-id'])
expect(vectors['test-id']).to be_present
```

### 3. Test New Features (if applicable)

```ruby
# Text search (v1.1.1+)
if client.provider.respond_to?(:text_search)
  results = client.text_search(index: 'test', text: 'query', top_k: 10)
  expect(results.size).to be >= 0
end

# Middleware (v1.1.0+)
Vectra::Client.use Vectra::Middleware::Logging
# Test that logging works
```

## Deprecation Warnings

Vectra may show deprecation warnings for features that will be removed in future versions:

```ruby
# Example warning
# [DEPRECATION] Using :index_name parameter is deprecated. Use :index instead.
```

Update your code to use the new parameter names.

## Rollback Plan

If you encounter issues after upgrading:

### 1. Pin to Previous Version

```ruby
# Gemfile
gem 'vectra-client', '1.0.8'  # Previous working version
```

```bash
bundle install
```

### 2. Report Issues

- [GitHub Issues](https://github.com/stokry/vectra/issues)
- Include version, error messages, and code examples

## Upgrade Checklist

- [ ] Review [CHANGELOG.md](https://github.com/stokry/vectra/blob/main/CHANGELOG.md)
- [ ] Update Gemfile
- [ ] Run `bundle update vectra-client`
- [ ] Run test suite
- [ ] Test in development environment
- [ ] Test in staging (if applicable)
- [ ] Deploy to production
- [ ] Monitor for errors
- [ ] Update code to use new features (optional)

## Getting Help

- [GitHub Issues](https://github.com/stokry/vectra/issues)
- [API Reference](/api/methods/)
- [Troubleshooting Guide](/troubleshooting/common-errors/)
