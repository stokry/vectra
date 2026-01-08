---
layout: page
title: Security Best Practices
permalink: /guides/security/
---

# Security Best Practices

Complete guide for securing Vectra in production environments.

## API Key Management

### Environment Variables (Recommended)

**Always use environment variables for API keys:**

```ruby
# ✅ Good
Vectra.configure do |config|
  config.provider = :pinecone
  config.api_key = ENV['PINECONE_API_KEY']  # Set in .env or system env
  config.environment = ENV['PINECONE_ENVIRONMENT'] || 'us-east-1'
end
```

```bash
# Set in environment
export PINECONE_API_KEY="your-key-here"
export PINECONE_ENVIRONMENT="us-east-1"
```

### Rails Credentials (Encrypted)

```ruby
# ✅ Good - Rails encrypted credentials
Vectra.configure do |config|
  config.api_key = Rails.application.credentials.dig(:pinecone, :api_key)
end
```

```bash
# Edit credentials
rails credentials:edit

# Add to credentials.yml.enc:
# pinecone:
#   api_key: your-key-here
```

### Secret Management Services

```ruby
# ✅ Good - AWS Secrets Manager
require 'aws-sdk-secretsmanager'

secrets = Aws::SecretsManager::Client.new
secret = JSON.parse(
  secrets.get_secret_value(secret_id: 'vectra/pinecone').secret_string
)

Vectra.configure do |config|
  config.api_key = secret['api_key']
end
```

```ruby
# ✅ Good - HashiCorp Vault
require 'vault'

Vault.auth.aws
secret = Vault.logical.read("secret/vectra/pinecone")

Vectra.configure do |config|
  config.api_key = secret.data[:api_key]
end
```

### What NOT to Do

```ruby
# ❌ NEVER hardcode API keys
Vectra.configure do |config|
  config.api_key = "pk-123456789"  # This will be committed to git!
end

# ❌ NEVER store in config files
# config/vectra.yml
# api_key: "pk-123456789"  # This will be committed!

# ❌ NEVER log API keys
logger.info("API key: #{config.api_key}")  # Will appear in logs!
```

## Credential Rotation

Use built-in credential rotation for zero-downtime key updates:

```ruby
require 'vectra/credential_rotation'

# Setup rotation
rotator = Vectra::CredentialRotator.new(
  primary_key: ENV['PINECONE_API_KEY'],
  secondary_key: ENV['PINECONE_API_KEY_NEW'],
  provider: :pinecone
)

# Test new key before switching
if rotator.test_secondary
  rotator.switch_to_secondary
  puts "✅ Rotation complete"
else
  puts "❌ New key validation failed - keeping primary"
end

# Rollback if issues occur
rotator.rollback
```

### Multi-Provider Rotation

```ruby
# Register multiple providers
Vectra::CredentialRotationManager.register(:pinecone,
  primary: ENV['PINECONE_API_KEY'],
  secondary: ENV['PINECONE_API_KEY_NEW']
)

Vectra::CredentialRotationManager.register(:qdrant,
  primary: ENV['QDRANT_API_KEY'],
  secondary: ENV['QDRANT_API_KEY_NEW']
)

# Test all new keys
results = Vectra::CredentialRotationManager.test_all_secondary
# => { pinecone: true, qdrant: false }

# Rotate all if tests pass
if results.values.all?
  Vectra::CredentialRotationManager.rotate_all
end

# Check rotation status
Vectra::CredentialRotationManager.status
```

### Rotation Best Practices

1. **Test before switching** - Always validate new credentials
2. **Monitor after rotation** - Watch for errors for 24-48 hours
3. **Keep old key active** - Don't revoke immediately
4. **Rotate during low traffic** - Minimize impact
5. **Use gradual migration** - For high-traffic systems

## Audit Logging

Enable audit logging for compliance and security monitoring:

```ruby
require 'vectra/audit_log'

# Setup audit logging
audit = Vectra::AuditLog.new(
  output: "log/audit.json.log",
  app: "my-service",
  env: Rails.env
)

# Log access events
audit.log_access(
  user_id: current_user.id,
  operation: "query",
  index: "sensitive-data",
  result_count: 10
)

# Log authentication
audit.log_authentication(
  user_id: user.id,
  success: true,
  provider: "pinecone"
)

# Log credential rotations
audit.log_credential_rotation(
  provider: "pinecone",
  success: true,
  rotated_by: admin_user.id
)

# Log data modifications
audit.log_data_modification(
  user_id: user.id,
  operation: "upsert",
  index: "vectors",
  record_count: 100
)
```

### Global Audit Logging

```ruby
# Setup once in initializer
Vectra::AuditLogging.setup!(
  output: "log/audit.json.log",
  app: "my-service"
)

# Use anywhere
Vectra::AuditLogging.log(:access,
  user_id: current_user.id,
  operation: "query",
  index: "data"
)
```

### Audit Log Format

```json
{
  "timestamp": "2025-01-08T12:00:00.123Z",
  "level": "info",
  "logger": "vectra",
  "message": "audit.access",
  "event_type": "access",
  "user_id": "user123",
  "operation": "query",
  "resource": "my-index",
  "result_count": 10
}
```

## Network Security

### HTTPS/TLS

- **Always use HTTPS** - Enforced by default
- **Verify certificates** - Enabled by default
- **Use VPN/private networks** when possible

### mTLS (Mutual TLS)

For providers supporting mutual TLS authentication:

```ruby
# pgvector with client certificates
Vectra.configure do |config|
  config.provider = :pgvector
  config.host = "postgresql://user:pass@host/db?" \
                 "sslmode=verify-full&" \
                 "sslcert=/path/to/client.crt&" \
                 "sslkey=/path/to/client.key&" \
                 "sslrootcert=/path/to/ca.crt"
end
```

**Note:** mTLS support depends on provider capabilities. Check provider documentation.

## Data Security

### Input Sanitization

```ruby
# Sanitize metadata before upsert
def sanitize_metadata(metadata)
  metadata.reject { |k, _| k.to_s.match?(/password|secret|token|ssn|credit_card/i) }
end

vectors = [{
  id: "vec1",
  values: embedding,
  metadata: sanitize_metadata(user_data)
}]

client.upsert(index: "my-index", vectors: vectors)
```

### Access Control

```ruby
# Implement application-level access control
class VectorService
  def query(user:, index:, vector:, top_k:)
    # Check permissions
    unless user.can_access?(index)
      audit.log_authorization(
        user_id: user.id,
        resource: index,
        allowed: false,
        reason: "Insufficient permissions"
      )
      raise ForbiddenError, "Access denied"
    end

    # Log access
    audit.log_access(
      user_id: user.id,
      operation: "query",
      index: index,
      result_count: top_k
    )

    client.query(index: index, vector: vector, top_k: top_k)
  end
end
```

## Compliance

### GDPR/Privacy

- **Data retention policies** - Implement automatic deletion
- **Right to deletion** - Support user data removal
- **Data encryption** - Encrypt sensitive metadata
- **Access logs** - Maintain audit trails

### HIPAA/Healthcare

- **Encryption at rest** - Provider responsibility
- **Encryption in transit** - HTTPS enforced
- **Access controls** - Application-level
- **Audit logging** - Required for compliance

### PCI-DSS

- **No card data in vectors** - Never store card numbers
- **Tokenization** - Use tokens instead of raw data
- **Access monitoring** - Audit all access

## Security Checklist

- [ ] API keys stored in environment variables or vaults
- [ ] No API keys in version control
- [ ] Different keys for dev/staging/production
- [ ] Credential rotation implemented
- [ ] Audit logging enabled
- [ ] HTTPS/TLS enforced
- [ ] Input sanitization implemented
- [ ] Access controls in place
- [ ] Rate limiting configured
- [ ] Error monitoring setup
- [ ] Security alerts configured

## Related

- [SECURITY.md](https://github.com/stokry/vectra/blob/main/SECURITY.md) - Security policy
- [Monitoring Guide]({{ site.baseurl }}/guides/monitoring) - Security monitoring
- [Performance Guide]({{ site.baseurl }}/guides/performance) - Rate limiting
