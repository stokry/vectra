---
layout: page
title: Rails Troubleshooting
permalink: /guides/rails-troubleshooting/
---

# Rails Troubleshooting Guide

## Common Issues and Solutions

### Issue: `uninitialized constant Vectra::Providers::Qdrant`

**Error Message:**
```
NameError: uninitialized constant Vectra::Providers::Qdrant
```

**Cause:**
In Rails, when using autoloading (Zeitwerk), modules are loaded on-demand. If `Vectra::Client` is instantiated before all Providers are loaded, you'll get this error.

**Solution 1: Explicit require in initializer (Recommended)**

Add `require 'vectra'` at the top of your initializer:

```ruby
# config/initializers/vectra.rb
require 'vectra'  # Ensure all Providers are loaded

Vectra.configure do |config|
  config.provider = :qdrant
  # ... rest of config
end
```

**Solution 2: Lazy loading in ActiveRecord**

If you're using `has_vector` in your models, the client is created lazily, which should work. However, if you're creating clients directly, ensure Providers are loaded:

```ruby
# This will work because vectra.rb loads all Providers
client = Vectra::Client.new(provider: :qdrant)

# But if you're in a context where autoloading hasn't kicked in:
require 'vectra'  # Load everything first
client = Vectra::Client.new(provider: :qdrant)
```

**Solution 3: Check autoload paths**

If you're using Zeitwerk, ensure Vectra is in your autoload paths:

```ruby
# config/application.rb
config.autoload_paths << Rails.root.join('lib')
```

However, since Vectra is a gem, this shouldn't be necessary. The gem's `lib` directory should be in the load path automatically.

### Issue: `uninitialized constant Vectra::Client::HealthCheck`

**Error Message:**
```
NameError: uninitialized constant Vectra::Client::HealthCheck
```

**Cause:**
Module loading order issue. `Client` tries to include `HealthCheck` before it's loaded.

**Solution:**

This is already fixed in the gem with defensive requires. If you still see this, ensure you're using the latest version:

```ruby
# In your Gemfile
gem 'vectra-client', '>= 1.0.1'
```

Then run:
```bash
bundle update vectra-client
```

### Issue: Providers not found in Rails console

**Symptom:**
```ruby
# In rails console
Vectra::Providers::Qdrant
# => NameError: uninitialized constant Vectra::Providers::Qdrant
```

**Solution:**

Load Vectra explicitly:
```ruby
require 'vectra'
Vectra::Providers::Qdrant
# => Vectra::Providers::Qdrant
```

Or use the client directly:
```ruby
client = Vectra::Client.new(provider: :qdrant)
# This will load all necessary Providers
```

### Issue: Autoloading conflicts with Zeitwerk

**Symptom:**
In Rails 7+ with Zeitwerk, you might see warnings or errors about constant loading.

**Solution:**

Vectra uses explicit `require_relative` statements, which work with both classic autoloading and Zeitwerk. However, if you're seeing issues:

1. **Ensure initializer loads Vectra:**
   ```ruby
   # config/initializers/vectra.rb
   require 'vectra'  # Explicit require
   ```

2. **Disable Zeitwerk for Vectra (not recommended, but works):**
   ```ruby
   # config/application.rb
   config.autoloader = :classic  # Only if absolutely necessary
   ```

3. **Use eager loading in production:**
   ```ruby
   # config/environments/production.rb
   config.eager_load = true  # Already default in production
   ```

### Issue: `has_vector` not working in models

**Symptom:**
```ruby
class Product < ApplicationRecord
  include Vectra::ActiveRecord
  has_vector :embedding, dimension: 1536
end

# Error: undefined method `has_vector`
```

**Cause:**
`Vectra::ActiveRecord` module not loaded or included incorrectly.

**Solution:**

1. **Ensure Vectra is required:**
   ```ruby
   # config/initializers/vectra.rb
   require 'vectra'
   ```

2. **Check include order:**
   ```ruby
   class Product < ApplicationRecord
     include Vectra::ActiveRecord  # Must be included first
     
     has_vector :embedding, dimension: 1536, provider: :qdrant
   end
   ```

3. **Use the generator (recommended):**
   ```bash
   rails generate vectra:index Product embedding dimension:1536 provider:qdrant
   ```
   This will create the concern correctly.

### Issue: Client created but provider methods fail

**Symptom:**
```ruby
client = Vectra::Client.new(provider: :qdrant)
client.upsert(...)  # Works
client.query(...)   # NameError: uninitialized constant Vectra::Providers::Qdrant
```

**Cause:**
Provider was loaded initially, but then unloaded by autoloader, or there's a circular dependency.

**Solution:**

1. **Use explicit require:**
   ```ruby
   require 'vectra'
   client = Vectra::Client.new(provider: :qdrant)
   ```

2. **Check for circular dependencies:**
   If you have custom code that requires Vectra modules, ensure they're loaded in the correct order.

3. **Disable autoloading for Vectra (last resort):**
   ```ruby
   # config/application.rb
   # Add Vectra to eager load paths
   config.eager_load_paths << Gem.find_files('vectra').first.split('/lib/').first + '/lib'
   ```

### Issue: Generator creates files but model doesn't work

**Symptom:**
```bash
rails generate vectra:index Product embedding dimension:1536 provider:qdrant
# Files created, but model errors
```

**Solution:**

1. **Restart Rails server/console:**
   ```bash
   # After running generator
   rails restart
   ```

2. **Check generated concern:**
   ```ruby
   # app/models/concerns/product_vector.rb
   module ProductVector
     extend ActiveSupport::Concern
     
     included do
       include Vectra::ActiveRecord
       has_vector :embedding, ...
     end
   end
   ```

3. **Check model includes concern:**
   ```ruby
   # app/models/product.rb
   class Product < ApplicationRecord
     include ProductVector  # Must be present
   end
   ```

4. **Verify initializer:**
   ```ruby
   # config/initializers/vectra.rb
   require 'vectra'  # Should be at the top
   Vectra.configure do |config|
     config.provider = :qdrant
     # ...
   end
   ```

## Debugging Tips

### 1. Check what's loaded

```ruby
# In Rails console
Vectra.constants
# => [:Configuration, :Client, :Vector, ...]

Vectra::Providers.constants
# => Should show: [:Base, :Pinecone, :Qdrant, :Weaviate, :Pgvector, :Memory]

# Check if specific provider is loaded
defined?(Vectra::Providers::Qdrant)
# => "constant" if loaded, nil if not
```

### 2. Force load everything

```ruby
# In Rails console or initializer
require 'vectra'
require 'vectra/providers/base'
require 'vectra/providers/qdrant'
require 'vectra/providers/pinecone'
require 'vectra/providers/weaviate'
require 'vectra/providers/pgvector'
require 'vectra/providers/memory'
```

### 3. Check load order

```ruby
# In Rails console
$LOADED_FEATURES.grep(/vectra/)
# Shows what Vectra files are loaded and in what order
```

### 4. Test client creation

```ruby
# In Rails console
begin
  client = Vectra::Client.new(provider: :qdrant, host: 'http://localhost:6333')
  puts "✅ Client created successfully"
  puts "Provider: #{client.provider.class}"
rescue => e
  puts "❌ Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end
```

## Best Practices for Rails

### 1. Always require Vectra in initializer

```ruby
# config/initializers/vectra.rb
require 'vectra'  # Always at the top

Vectra.configure do |config|
  # Configuration
end
```

### 2. Use the generator for new models

```bash
rails generate vectra:index ModelName column_name dimension:1536 provider:qdrant
```

This ensures correct setup.

### 3. Test in Rails console

After setup, test in console:
```ruby
rails console

# Test configuration
Vectra.configuration.provider
# => :qdrant

# Test client
client = Vectra::Client.new
client.healthy?
# => true

# Test model (if using ActiveRecord)
Product.vector_search([0.1, 0.2, ...], limit: 5)
```

### 4. Check logs

Enable logging to see what's happening:
```ruby
# config/initializers/vectra.rb
Vectra.configure do |config|
  config.logger = Rails.logger
  config.logger.level = :debug  # In development
end
```

## Still Having Issues?

1. **Check Vectra version:**
   ```bash
   bundle show vectra-client
   ```

2. **Update to latest:**
   ```bash
   bundle update vectra-client
   ```

3. **Check Rails version:**
   ```bash
   rails --version
   ```

4. **Create minimal reproduction:**
   - New Rails app
   - Add Vectra
   - Reproduce issue
   - Share steps

5. **Open an issue:**
   - [GitHub Issues](https://github.com/stokry/vectra/issues)
   - Include Rails version, Vectra version, error message, and stack trace
