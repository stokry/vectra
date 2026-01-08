---
layout: page
title: Installation
permalink: /guides/installation/
---

# Installation Guide

## Requirements

- Ruby 3.2.0 or higher
- Bundler

## Install via Bundler

Add Vectra to your Gemfile:

```ruby
gem 'vectra-client'
```

Then run:

```bash
bundle install
```

## Install Standalone

Alternatively, install via RubyGems:

```bash
gem install vectra-client
```

## Rails Integration

For Rails applications, run the install generator:

```bash
rails generate vectra:install
```

This will create an initializer file at `config/initializers/vectra.rb`.

## Provider-Specific Setup

Each vector database provider may require additional dependencies:

### PostgreSQL with pgvector
```ruby
gem 'pg', '~> 1.5'
```

### Instrumentation

#### Datadog
```ruby
gem 'dogstatsd-ruby'
```

#### New Relic
```ruby
gem 'newrelic_rpm'
```

See [Provider Guides]({{ site.baseurl }}/providers) for detailed setup instructions.
