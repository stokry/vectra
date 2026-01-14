---
layout: page
title: FAQ
permalink: /guides/faq/
---

# FAQ

Najčešća pitanja i kratki odgovori oko korištenja Vectre u produkciji.

---

## 1. Koju dimenziju (dimension) trebam koristiti?

**Kratko:** Uskladi `dimension` s modelom kojim generiraš embeddings.

- OpenAI `text-embedding-3-small` → 1536 dimenzija
- OpenAI `text-embedding-3-large` → 3072 dimenzija
- Cohere `embed-english-v3.0` → 1024 dimenzija

U Rails modelu / generatoru:

```ruby
has_vector :embedding,
  dimension: 1536
```

Ako dimenzija ne odgovara, Vectra će baciti **ValidationError** pri upsertu.

---

## 2. Kad koristiti pgvector, a kad Qdrant / Pinecone / Weaviate?

**Pgvector (PostgreSQL):**
- Imaš već PostgreSQL i želiš **minimalne dodatne servise**
- Želiš **SQL** i ACID transakcije
- Dataset je srednje veličine (do par milijuna vektora)

**Qdrant:**
- Želiš **open source** i **self-hosted** rješenje
- Trebaš napredne filtere i dobar performance
- Želiš i opciju clouda (Qdrant Cloud)

**Pinecone:**
- Želiš **managed cloud** i "zero ops"
- Veći volumeni podataka, multi-region, SLA

**Weaviate:**
- Hoćeš **AI-native** vektorsku bazu s ugrađenim vektorizatorima
- Želiš GraphQL API i bogat schema model

Detaljnije usporedbe imaš i na [homepage-u](https://vectra-docs.netlify.app/api/methods).

---

## 3. Kako spremati embeddings – trebam li ih normalizirati?

Preporuka:

- Normaliziraj vektore na L2 normu prije spremanja (bolja stabilnost cosine sličnosti)

```ruby
embedding  = EmbeddingService.generate(text)
normalized = Vectra::Vector.normalize(embedding)

client.upsert(
  index: 'documents',
  vectors: [
    { id: 'doc-1', values: normalized, metadata: { title: 'Hello' } }
  ]
)
```

Ako koristiš pgvector i želiš direktan `cosine` / `inner product` preko SQL-a, i dalje je dobra praksa normalizirati embeddinge na aplikacijskoj strani.

---

## 4. Zašto ne dobivam nikakve rezultate iz pretrage?

Najčešći razlozi:

1. **Krivi index ili namespace**
   - Provjeri da koristiš isti `index` i `namespace` kod `upsert` i `query`

2. **Filter previše restriktivan**
   - Probaj maknuti `filter` i vidjeti dobivaš li rezultate

3. **Dimenzija ne odgovara**
   - Ako je `dimension` u bazi 1536, a šalješ vektor s npr. 1024 elemenata → provider će baciti grešku ili ignorirati upit

4. **Embedding funkcija ne vraća ono što misliš**
   - U testu ispiši prvih par elemenata i dužinu vektora

---

## 5. Kako odabrati metricu sličnosti (cosine / dot / L2)?

Vectra ti apstrahira metricu, ali provider ispod može koristiti različite metrike.

Praktično:

- Za većinu use-caseova → **cosine** ili **dot product** (na normaliziranim vektorima)
- Pgvector: koristi `cosine` ili `<->` operator, ali Vectra to sakriva iza unified API-ja

Ako nisi siguran, koristi default provider metricu + normalizirane embeddinge.

---

## 6. Kako razdvojiti tenant-e (multi-tenant SaaS)?

Koristi kombinaciju **namespace** + **metadata filter**:

```ruby
# Upsert
client.upsert(
  index: 'documents',
  vectors: [
    { id: 'doc-1', values: embedding, metadata: { tenant_id: tenant.id } }
  ],
  namespace: "tenant_#{tenant.id}"
)

# Query
client.query(
  index: 'documents',
  vector: query_embedding,
  namespace: "tenant_#{tenant.id}",
  filter: { tenant_id: tenant.id }
)
```

Za konkretan primjer pogledaj [Recipes & Patterns](/guides/recipes/#multi-tenant-saas-namespace-isolation).

---

## 7. Kako testirati bez pravog providera?

Koristi **Memory provider** (`:memory`):

- U test environmentu:

```ruby
Vectra.configure do |config|
  config.provider = :memory if Rails.env.test?
end
```

- Ili direktno u RSpec-u:

```ruby
let(:client) { Vectra.memory }
```

Detaljan vodič: [Testing Guide](/guides/testing/).

---

## 8. Koje health checkove trebam za production?

Minimalno:

- `client.healthy?` u background jobu ili health endpointu
- `client.ping` za mjerenje latencije

Primjer Rails endpointa:

```ruby
class HealthController < ApplicationController
  def vectra
    status = Vectra::Client.new.ping

    if status[:healthy]
      render json: status
    else
      render json: status, status: :service_unavailable
    end
  rescue => e
    render json: { healthy: false, error: e.message }, status: :service_unavailable
  end
end
```

Više u [Monitoring & Observability](/guides/monitoring/).

---

## 9. Kada koristiti batch upsert umjesto pojedinačnih poziva?

Uvijek kad:

- Imaš **više od ~20 vektora odjednom**
- Radiš inicijalni import (npr. 1000+ proizvoda)

```ruby
Vectra::Batch.upsert(
  client: client,
  index: 'products',
  vectors: product_vectors,
  batch_size: 100,
  on_progress: ->(batch_index, total_batches, batch_count) do
    Rails.logger.info "Batch #{batch_index + 1}/#{total_batches} (#{batch_count} vectors)"
  end
)
```

---

## 10. Kako izabrati pravog providera za moj use-case?

Pogledaj [Provider Selection Guide](/providers/selection/) za konkretne scenarije:

- "Imam samo Postgres" → pgvector
- "Želim managed cloud" → Pinecone
- "Hoću OSS i da se mogu sam hostati" → Qdrant / Weaviate

