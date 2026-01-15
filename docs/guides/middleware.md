---
layout: page
title: Middleware System
permalink: /guides/middleware/
---

# Middleware System

Vectra includes a **Rack-style middleware stack** that lets you extend the client
without forking the gem or patching providers.

You can:

- Add **logging, metrics, retries, PII redaction, cost tracking**.
- Inject **custom behaviour** before/after every operation.
- Enable features **globally** or **per client**, same kao Faraday/Sidekiq.

---

## Core Concepts

### Request / Response

- **`Vectra::Middleware::Request`**
  - `operation` – npr. `:upsert`, `:query`, `:fetch`, `:delete`, `:stats`, `:hybrid_search`
  - `index` – ime indeksa (može biti `nil` ako koristiš default)
  - `namespace` – namespace (može biti `nil`)
  - `params` – originalni keyword parametri koje je `Vectra::Client` proslijedio
  - `provider` – ime providera (`:pinecone`, `:qdrant`, `:pgvector`, `:memory`, …)
  - helperi: `write_operation?`, `read_operation?`

- **`Vectra::Middleware::Response`**
  - `result` – što god provider vrati (npr. hash, `QueryResult`, itd.)
  - `error` – iznimka ako je došlo do greške
  - `metadata` – slobodan hash za dodatne informacije (trajanje, cost, retry_count…)
  - helperi: `success?`, `failure?`, `raise_if_error!`, `value!`

### Base i Stack

- **`Vectra::Middleware::Base`**
  - Hookovi koje možeš override-ati:
    - `before(request)` – prije poziva providera / sljedećeg middlewarea
    - `after(request, response)` – nakon uspješnog poziva
    - `on_error(request, error)` – kad dođe do iznimke (error se zatim re-raise-a)

- **`Vectra::Middleware::Stack`**
  - Gradi chain oko konkretnog providera:
    ```ruby
    stack = Vectra::Middleware::Stack.new(provider, [Logging.new, Retry.new])
    result = stack.call(:upsert, index: "docs", vectors: [...], provider: :qdrant)
    ```
  - `Stack` interno:
    - kreira `Request`,
    - kroz sve middlewares propagira isti `Request`,
    - na kraju zove `provider.public_send(request.operation, **provider_params)`,
    - vraća `Response` (s `result` ili `error`).

---

## Enabling Middleware

### Global Middleware

Primjenjuje se na **sve** `Vectra::Client` instance.

```ruby
require "vectra"

# Global logging + retry + cost tracking
Vectra::Client.use Vectra::Middleware::Logging
Vectra::Client.use Vectra::Middleware::Retry, max_attempts: 5
Vectra::Client.use Vectra::Middleware::CostTracker
```

Sve sljedeće `Vectra::Client.new(...)` instance će koristiti ovaj globalni stack.

### Per‑Client Middleware

Dodatni ili prilagođeni middleware samo za jedan klijent:

```ruby
client = Vectra::Client.new(
  provider: :qdrant,
  index: "products",
  middleware: [
    Vectra::Middleware::PIIRedaction,
    Vectra::Middleware::Instrumentation
  ]
)
```

- Per‑client middleware se izvodi **nakon** globalnog, u istom chainu.
- Redoslijed u arrayu definira redoslijed ekzekucije (zadnji je najunutarnji, tik do providera).

---

## Koje operacije prolaze kroz stack?

Sve standardne operacije `Vectra::Client`a koriste middleware stack:

- `upsert`
- `query`
- `fetch`
- `update`
- `delete`
- `list_indexes`
- `describe_index`
- `stats`
- `hybrid_search`

To znači da middleware može:

- logirati / instrumentirati **sve pozive** prema provideru,
- raditi **PII redakciju** na `upsert` zahtjevima,
- brojati i retry-ati i **read** i **write** operacije,
- računati trošak po operaciji (npr. za billing / budžete).

---

## Built‑in Middleware

### Logging (`Vectra::Middleware::Logging`)

**Što radi:**
- logira početak i kraj svake operacije (`operation`, `index`, `namespace`),
- mjeri trajanje i sprema ga u `response.metadata[:duration_ms]`.

**Konfiguracija:**

```ruby
# Globalno
Vectra::Client.use Vectra::Middleware::Logging

# S custom loggerom
logger = Logger.new($stdout)
Vectra::Client.use Vectra::Middleware::Logging, logger: logger
```

**Tipična upotreba:** debugiranje, audit logovi, korelacija s HTTP logovima.

---

### Retry (`Vectra::Middleware::Retry`)

**Što radi:**
- automatski retry-a transient greške:
  - `Vectra::RateLimitError`
  - `Vectra::ConnectionError`
  - `Vectra::TimeoutError`
  - `Vectra::ServerError`
- koristi exponential ili linear backoff,
- upisuje broj retry-a u `response.metadata[:retry_count]`.

**Konfiguracija:**

```ruby
# 3 pokušaja, exponential backoff (default)
Vectra::Client.use Vectra::Middleware::Retry

# 5 pokušaja, linearni backoff
Vectra::Client.use Vectra::Middleware::Retry,
  max_attempts: 5,
  backoff: :linear

# Fiksni delay 1.0s
Vectra::Client.use Vectra::Middleware::Retry,
  max_attempts: 3,
  backoff: 1.0
```

**Tipična upotreba:** zaštita od povremenih mrežnih problema i rate‑limit grešaka.

---

### Instrumentation (`Vectra::Middleware::Instrumentation`)

**Što radi:**
- emitira događaje preko postojećeg `Vectra::Instrumentation` sustava,
- prikuplja trajanje, status, error class, dodatni `metadata`.

**Primjer:**

```ruby
Vectra::Client.use Vectra::Middleware::Instrumentation

Vectra.on_operation do |event|
  # event[:operation], event[:provider], event[:duration_ms], event[:success], ...
  StatsD.timing("vectra.#{event[:operation]}", event[:duration_ms])
end
```

**Tipična upotreba:** integracija s Prometheus/Grafana, Datadog, New Relic…

---

### PII Redaction (`Vectra::Middleware::PIIRedaction`)

**Što radi:**
- prije `upsert` operacija prolazi kroz `vectors[:metadata]`,
- prepoznaje PII pattern-e (email, phone, SSN, credit card) i zamjenjuje ih placeholderom
  npr. `[REDACTED_EMAIL]`, `[REDACTED_PHONE]`, itd.

**Primjer:**

```ruby
Vectra::Client.use Vectra::Middleware::PIIRedaction

client.upsert(
  index: "sensitive",
  vectors: [
    {
      id: "user-1",
      values: [0.1, 0.2, 0.3],
      metadata: {
        email: "user@example.com",
        phone: "555-1234",
        note:  "Contact at user@example.com"
      }
    }
  ]
)
```

Nakon `upsert`‑a, provider će vidjeti već **redaktirani** metadata.

**Custom patterni:**

```ruby
patterns = {
  credit_card: /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/,
  api_key: /sk-[a-zA-Z0-9]{32}/
}

Vectra::Client.use Vectra::Middleware::PIIRedaction, patterns: patterns
```

**Tipična upotreba:** GDPR, SOC2, PCI‑DSS okruženja gdje je zabranjen PII u vektor bazi.

---

### CostTracker (`Vectra::Middleware::CostTracker`)

**Što radi:**
- procjenjuje trošak po operaciji na temelju providera i tipa operacije (`read` / `write`),
- upisuje trošak u `response.metadata[:cost_usd]`,
- opcionalno zove `on_cost` callback za real‑time praćenje.

**Primjer:**

```ruby
Vectra::Client.use Vectra::Middleware::CostTracker,
  on_cost: ->(event) {
    puts "💰 Cost: $#{event[:cost_usd].round(6)} for #{event[:operation]} (#{event[:provider]})"
  }
```

**Custom pricing:**

```ruby
pricing = {
  pinecone: { read: 0.0001, write: 0.0002 },
  qdrant:   { read: 0.00005, write: 0.0001 }
}

Vectra::Client.use Vectra::Middleware::CostTracker, pricing: pricing
```

**Tipična upotreba:** unutarnji billing, budget guardrails, cost dashboards.

---

## Custom Middleware

Najjednostavniji način je naslijediti `Vectra::Middleware::Base` i override-ati hookove:

```ruby
class MyAuditMiddleware < Vectra::Middleware::Base
  def before(request)
    AuditLog.create!(
      operation: request.operation,
      index:     request.index,
      namespace: request.namespace,
      provider:  request.provider
    )
  end

  def after(_request, response)
    puts "Duration: #{response.metadata[:duration_ms]}ms"
  end

  def on_error(request, error)
    ErrorTracker.notify(error, context: { operation: request.operation })
  end
end

Vectra::Client.use MyAuditMiddleware
```

**Savjeti:**

- Ne mijenjaj strukturu `request.params` na način koji provider ne očekuje.
- Svoje pomoćne podatke stavljaj u `response.metadata` ili `request.metadata`.
- Ako hvataš greške u `on_error`, **nemoj ih gutati** – middleware stack će ih ponovo baciti.

---

## Primjer: `examples/middleware_demo.rb`

U repozitoriju imaš kompletan demo:

- konfigurira globalni stack (`Logging`, `Retry`, `CostTracker`),
- pokazuje per‑client PII redaction,
- definira custom `TimingMiddleware`,
- demonstrira kako izgleda output u konzoli.

Pokretanje:

```bash
bundle exec ruby examples/middleware_demo.rb
```

Ovaj demo je dobar “živi” primjer kako kombinirati više middleware-a u praksi.


