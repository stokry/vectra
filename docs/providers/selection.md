---
layout: page
title: Provider Selection Guide
permalink: /providers/selection/
---

# Provider Selection Guide

Kratki vodič kako odabrati pravog providera za tvoj use-case.

Vectra podržava 5 providera:

- **Pinecone** – managed cloud
- **Qdrant** – open source, self-host + cloud
- **Weaviate** – AI-native, GraphQL, open source
- **pgvector** – PostgreSQL ekstenzija
- **Memory** – in-memory, samo za testing

---

## Brzi "decision tree"

### 1. Već koristiš PostgreSQL i želiš minimalne promjene

**Preporuka:** `pgvector`

Koristi pgvector ako:

- Sve ti je već u Postgresu
- Ne želiš dodatni servis u infrastrukturi
- Hoćeš **SQL + ACID** i transakcije
- Dataset je **srednji** (deseci / stotine tisuća do par milijuna vektora)

```ruby
# Gemfile
# pg + pgvector extension u bazi

Vectra.configure do |config|
  config.provider = :pgvector
  config.host     = ENV['DATABASE_URL']
end

client = Vectra::Client.new
```

**Plusevi:**
- Nema dodatne baze → manje ops-a
- Možeš raditi JOIN-ove, transakcije, migrations kao i inače

**Minusi:**
- Nije "pure" vektorska baza (manje specijaliziranih featurea)
- Scaling je vezan uz Postgres

---

### 2. Želiš open source i mogućnost self-hosta

**Preporuka:** `Qdrant` (ili `Weaviate` ako ti treba GraphQL i AI-native featurei)

Koristi **Qdrant** ako:

- Želiš **OSS** i full kontrolu
- Hoćeš odličan performance i dobar filter engine
- Možeš vrtiti Docker/Kubernetes ili koristiti Qdrant Cloud

```ruby
Vectra.configure do |config|
  config.provider = :qdrant
  config.host     = ENV.fetch('QDRANT_HOST', 'http://localhost:6333')
  config.api_key  = ENV['QDRANT_API_KEY'] # opcionalno za lokalni
end

client = Vectra::Client.new
```

Koristi **Weaviate** ako:

- Želiš **GraphQL API** i bogat schema model
- Hoćeš AI-native feature (ugrađeni vektorizatori, hybrid search, cross-references)

```ruby
Vectra.configure do |config|
  config.provider = :weaviate
  config.host     = ENV['WEAVIATE_HOST']
  config.api_key  = ENV['WEAVIATE_API_KEY']
end
```

---

### 3. Želiš managed cloud i "zero ops"

**Preporuka:** `Pinecone`

Koristi Pinecone ako:

- Ne želiš brinuti o indexima, sharding-u, backupima
- Imaš veće volumene i trebaš stabilan cloud servis
- Hoćeš multi-region, SLA, enterprise podršku

```ruby
Vectra.configure do |config|
  config.provider   = :pinecone
  config.api_key    = ENV['PINECONE_API_KEY']
  config.environment = ENV['PINECONE_ENVIRONMENT'] # npr. 'us-west-4'
end

client = Vectra::Client.new
```

**Plusevi:**
- Najmanje ops-a
- Dobri performance i scaling out-of-the-box

**Minusi:**
- Vezan si na cloud provider
- Plaćeni servis

---

### 4. Samo želiš nešto što radi lokalno za prototipiranje / testing

**Preporuka:** `Memory` ili lokalni `Qdrant`

- **Memory provider** (`:memory`):
  - Super za RSpec / Minitest i CI
  - Nema vanjskih ovisnosti

```ruby
Vectra.configure do |config|
  config.provider = :memory if Rails.env.test?
end

client = Vectra::Client.new
```

- **Lokalni Qdrant**:
  - Pokreneš `docker run qdrant/qdrant`
  - Koristiš pravi vektorski engine i lokalni disk

```ruby
Vectra.configure do |config|
  config.provider = :qdrant
  config.host     = 'http://localhost:6333'
end
```

---

## Tipični scenariji

### E-commerce (1000–1M proizvoda)

- **Ako već koristiš Postgres** → `pgvector`
- **Ako želiš dedicated vektorsku bazu** → `Qdrant`

Za Rails primjer pogledaj [Rails Integration Guide](/guides/rails-integration/) i [Recipes & Patterns](/guides/recipes/).

---

### SaaS aplikacija s multi-tenant podrškom

- **Qdrant** ili **Weaviate** zbog dobrog filteringa i fleksibilnosti
- **Pgvector** ako je sve već u jednoj Postgres bazi

Koristi **namespace per tenant** + metadata `tenant_id` (primjer u [Recipes](/guides/recipes/#multi-tenant-saas-namespace-isolation)).

---

### RAG chatbot / dokumentacija / knowledge base

- **Qdrant** ili **Weaviate** zbog dobrog rada s tekstom i filterima
- **Pinecone** ako želiš managed cloud bez brige

Važno:

- Čunkaj dokumente u manje dijelove (npr. 200–500 tokena)
- Spremi `document_id`, `chunk_index`, `source_url` u metadata

Primjer: [RAG Chatbot recipe](/guides/recipes/#rag-chatbot-context-retrieval).

---

### Interni alati / reporting / dashboards

- **Pgvector** je često najbolji izbor:
  - Podaci već u Postgresu
  - Možeš kombinirati vektorske upite i klasične SQL joinove

---

## Što ako želim promijeniti providera kasnije?

To je upravo najveća prednost Vectre 🙂

1. U konfiguraciji promijeniš `config.provider` + relevantne kredencijale
2. Opcionalno pokreneš migraciju podataka (dual-write ili batch migracija)
3. Tvoj aplikacijski kod (`client.upsert`, `client.query`, `has_vector`) ostaje isti

Za detaljan primjer pogledaj:

- [Zero-Downtime Provider Migration](/guides/recipes/#zero-downtime-provider-migration)

---

## Sažetak preporuka

- **Samo Postgres, minimalne promjene:** `pgvector`
- **OSS + self-host, jak filter engine:** `Qdrant`
- **AI-native, GraphQL:** `Weaviate`
- **Managed cloud, zero ops:** `Pinecone`
- **Testing / CI:** `Memory`

Sve ove opcije koristiš kroz **isti Vectra API**, pa kasnije možeš mijenjati providera s minimalnim promjenama u kodu.

