# Contributing to Vectra

Thank you for considering contributing to Vectra! This document outlines the process for contributing to this project.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for everyone.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce** the problem
- **Expected behavior** vs **actual behavior**
- **Ruby version** and **Vectra version**
- **Provider** you're using (Pinecone, Qdrant, Weaviate)
- **Code samples** if applicable

### Suggesting Enhancements

Enhancement suggestions are welcome! Please include:

- **Clear use case** for the enhancement
- **Expected behavior** of the new feature
- **Examples** of how it would be used
- **Benefits** to users

### Pull Requests

1. **Fork the repository** and create your branch from `main`:
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. **Set up your development environment**:
   ```bash
   bundle install
   ```

3. **Make your changes**:
   - Follow the existing code style
   - Add tests for any new functionality
   - Update documentation as needed
   - Ensure all tests pass

4. **Run the test suite**:
   ```bash
   # Run all tests
   bundle exec rspec

   # Run specific test file
   bundle exec rspec spec/vectra/client_spec.rb

   # Run with coverage
   COVERAGE=true bundle exec rspec
   ```

5. **Run the linter**:
   ```bash
   bundle exec rubocop

   # Auto-fix issues
   bundle exec rubocop -a
   ```

6. **Commit your changes**:
   - Use clear, descriptive commit messages
   - Reference issue numbers when applicable
   ```bash
   git commit -m "Add feature X to improve Y (#123)"
   ```

7. **Push to your fork** and submit a pull request:
   ```bash
   git push origin feature/my-new-feature
   ```

## Development Setup

### Prerequisites

- Ruby 3.2 or higher
- Bundler 2.0+

### Installation

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/vectra.git
cd vectra

# Install dependencies
bundle install

# Run tests to verify setup
bundle exec rspec
```

### Running Tests

```bash
# Run all tests
bundle exec rake

# Run only unit tests
bundle exec rake spec:unit

# Run only integration tests
bundle exec rake spec:integration

# Run with coverage report
COVERAGE=true bundle exec rspec
```

### Code Style

We use RuboCop to enforce consistent code style. Configuration is in `.rubocop.yml`.

```bash
# Check code style
bundle exec rubocop

# Auto-fix violations
bundle exec rubocop -a
```

### Documentation

We use YARD for documentation. All public methods should be documented.

```bash
# Generate documentation
bundle exec rake docs

# View documentation locally
open doc/index.html
```

## Adding a New Provider

To add support for a new vector database provider:

1. **Create provider class** in `lib/vectra/providers/`:
   ```ruby
   # lib/vectra/providers/new_provider.rb
   module Vectra
     module Providers
       class NewProvider < Base
         def provider_name
           :new_provider
         end

         # Implement required methods from Base
       end
     end
   end
   ```

2. **Add to configuration**:
   Update `SUPPORTED_PROVIDERS` in `lib/vectra/configuration.rb`

3. **Require in main file**:
   Add to `lib/vectra.rb`

4. **Write comprehensive tests**:
   - Unit tests in `spec/vectra/providers/new_provider_spec.rb`
   - Integration tests in `spec/integration/new_provider_integration_spec.rb`

5. **Update documentation**:
   - Add to README.md
   - Update CHANGELOG.md
   - Add YARD documentation

## Testing with VCR

Integration tests use VCR to record HTTP interactions:

```ruby
# spec/integration/provider_spec.rb
RSpec.describe "Provider Integration", :vcr do
  it "performs operation", vcr: { cassette_name: "provider/operation" } do
    # Test code
  end
end
```

To record new cassettes:
```bash
# Delete old cassettes
rm -rf spec/fixtures/vcr_cassettes/provider

# Run tests with real API (set API keys in ENV)
PINECONE_API_KEY=your_key bundle exec rspec spec/integration/
```

## Commit Message Guidelines

We follow conventional commits:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `test:` Adding or updating tests
- `refactor:` Code refactoring
- `style:` Code style changes
- `chore:` Maintenance tasks

Examples:
```
feat: add support for Qdrant vector database
fix: handle rate limit errors correctly
docs: update README with new examples
test: add integration tests for Pinecone
```

## Release Process

Releases are managed by maintainers:

1. Update version in `lib/vectra/version.rb`
2. Update CHANGELOG.md
3. Create git tag: `git tag -a v0.2.0 -m "Release v0.2.0"`
4. Push tag: `git push origin v0.2.0`
5. Build gem: `gem build vectra.gemspec`
6. Push to RubyGems: `gem push vectra-0.2.0.gem`

## Questions?

Feel free to open an issue for:
- Questions about the codebase
- Clarification on contribution process
- Feature discussions

## License

By contributing to Vectra, you agree that your contributions will be licensed under the MIT License.
