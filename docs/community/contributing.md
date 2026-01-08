---
layout: page
title: Contributing
permalink: /community/contributing/
---

# Contributing to Vectra

We welcome contributions! Here's how to get started.

## Development Setup

1. Clone the repository:
```bash
git clone https://github.com/stokry/vectra.git
cd vectra
```

2. Install dependencies:
```bash
bundle install
```

3. Run tests:
```bash
bundle exec rspec
```

## Making Changes

1. Create a feature branch:
```bash
git checkout -b feature/your-feature-name
```

2. Make your changes and write tests
3. Run linter:
```bash
bundle exec rubocop
```

4. Commit and push:
```bash
git add .
git commit -m "Description of changes"
git push origin feature/your-feature-name
```

5. Create a Pull Request

## Code Style

We use RuboCop for code style. Ensure your code passes:

```bash
bundle exec rubocop
```

## Testing

All changes require tests:

```bash
# Run all tests
bundle exec rspec

# Run specific suite
bundle exec rspec spec/vectra

# Run with coverage
bundle exec rspec --cov
```

## Documentation

Please update documentation for any changes:

- Update README.md for user-facing changes
- Update CHANGELOG.md
- Add examples if needed

## Questions?

Feel free to:
- Open an issue on GitHub
- Check existing issues and discussions
- Read the [Implementation Guide](https://github.com/stokry/vectra/blob/main/IMPLEMENTATION_GUIDE.md)

Thank you for contributing! 🙌
