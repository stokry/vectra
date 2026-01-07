# Security Policy

## Supported Versions

We release patches for security vulnerabilities for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |
| < 0.1   | :x:                |

## Reporting a Vulnerability

We take the security of Vectra seriously. If you believe you have found a security vulnerability, please report it to us as described below.

### Where to Report

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: **mijo@mijokristo.com**

### What to Include

Please include the following information in your report:

- Type of vulnerability (e.g., authentication bypass, SQL injection, credential exposure)
- Full paths of source file(s) related to the manifestation of the vulnerability
- The location of the affected source code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit it

### Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity, typically 30-90 days

We will:
1. Confirm the receipt of your vulnerability report
2. Provide an estimated timeline for a fix
3. Notify you when the vulnerability is fixed
4. Credit you in the security advisory (unless you prefer to remain anonymous)

## Security Best Practices for Users

### API Key Management

- **Never commit API keys** to version control
- Store API keys in environment variables or secure vaults
- Use different API keys for development, staging, and production
- Rotate API keys regularly
- Limit API key permissions to minimum required access

```ruby
# ✅ Good - Use environment variables
Vectra.configure do |config|
  config.api_key = ENV['PINECONE_API_KEY']
end

# ❌ Bad - Hardcoded API key
Vectra.configure do |config|
  config.api_key = "pk-123456789"  # Never do this!
end
```

### Network Security

- Always use HTTPS for API connections (enforced by default)
- Verify SSL certificates (enabled by default)
- Use VPN or private networks when possible
- Monitor API usage for unusual patterns

### Data Security

- **Sanitize input data** before upserting to vector databases
- **Validate vector dimensions** match your index configuration
- **Review metadata** for sensitive information before upserting
- **Implement access controls** at the application level
- **Encrypt sensitive metadata** before storage if needed

```ruby
# Example: Sanitizing metadata
def sanitize_metadata(metadata)
  metadata.reject { |k, _| k.to_s.match?(/password|secret|token/i) }
end

vectors = [{
  id: "vec1",
  values: embedding,
  metadata: sanitize_metadata(user_data)
}]

client.upsert(index: "my-index", vectors: vectors)
```

### Dependency Security

- Keep Vectra and its dependencies up to date
- Run `bundle audit` regularly to check for known vulnerabilities
- Review dependency changes in updates

```bash
# Check for vulnerabilities
gem install bundler-audit
bundle audit --update
```

### Rate Limiting

- Implement application-level rate limiting
- Handle `RateLimitError` exceptions appropriately
- Use exponential backoff for retries

```ruby
def safe_query_with_backoff(client, **params, max_retries: 3)
  retries = 0

  begin
    client.query(**params)
  rescue Vectra::RateLimitError => e
    retries += 1
    if retries <= max_retries
      sleep_time = e.retry_after || (2 ** retries)
      sleep(sleep_time)
      retry
    else
      raise
    end
  end
end
```

### Logging and Monitoring

- **Do not log API keys** or sensitive data
- Monitor for authentication failures
- Track unusual query patterns
- Set up alerts for rate limit violations

```ruby
# ❌ Bad - Logs API key
logger.info("Using API key: #{config.api_key}")

# ✅ Good - Logs without sensitive data
logger.info("Initializing Vectra client for #{config.provider}")
```

## Known Security Considerations

### API Key Exposure

API keys are transmitted in HTTP headers. While connections use HTTPS, ensure:
- API keys are never logged or exposed in error messages
- API keys are not included in client-side code
- Development/test API keys are separate from production

### Metadata Privacy

Metadata stored with vectors may contain sensitive information:
- Review metadata fields before upserting
- Consider encryption for sensitive fields
- Implement data retention policies
- Follow GDPR/privacy regulations for user data

### Dependency Chain

Vectra depends on:
- `faraday` - HTTP client library
- `faraday-retry` - Retry middleware

We monitor these dependencies for security issues and update promptly.

## Security Updates

Security updates will be released as patch versions (e.g., 0.1.1) and announced:
- On GitHub Security Advisories
- In the CHANGELOG.md
- Via RubyGems security notifications

Subscribe to GitHub releases to be notified of security updates.

## Compliance

Vectra is designed to work with various vector database providers. Ensure your usage complies with:
- Your provider's security requirements
- Data protection regulations (GDPR, CCPA, etc.)
- Industry-specific compliance (HIPAA, PCI-DSS, etc.)

## Questions?

If you have questions about security that are not covered here, please email: mijo@mijokristo.com

## Attribution

We appreciate responsible disclosure and will acknowledge security researchers who help improve Vectra's security.
