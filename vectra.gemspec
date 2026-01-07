# frozen_string_literal: true

require_relative "lib/vectra/version"

Gem::Specification.new do |spec|
  spec.name = "vectra-client"
  spec.version = Vectra::VERSION
  spec.authors = ["Mijo Kristo"]
  spec.email = ["mijo@mijokristo.com"]

  spec.summary = "Unified Ruby client for vector databases"
  spec.description = "Vectra provides a unified interface to work with multiple vector database providers including Pinecone, Qdrant, Weaviate, and PostgreSQL with pgvector. Write once, switch providers easily."
  spec.homepage = "https://github.com/stokry/vectra"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/stokry/vectra"
  spec.metadata["changelog_uri"] = "https://github.com/stokry/vectra/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-retry", "~> 2.0"

  # Optional runtime dependencies (required for specific providers)
  # For pgvector provider: gem 'pg', '~> 1.5'

  # Development dependencies
  spec.add_development_dependency "pg", "~> 1.5"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3.19"
  spec.add_development_dependency "vcr", "~> 6.2"
  spec.add_development_dependency "rubocop", "~> 1.57"
  spec.add_development_dependency "rubocop-rspec", "~> 2.25"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "yard", "~> 0.9"
end
