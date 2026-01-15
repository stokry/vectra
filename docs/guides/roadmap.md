---
layout: page
title: Roadmap
permalink: /guides/roadmap/
---

# Vectra Roadmap

This page outlines the high-level roadmap for **vectra-client**, the unified Ruby client for vector databases.

The roadmap is intentionally focused on **production features** that make AI workloads reliable, observable, and easy to operate in Ruby.

## Near Term (1.x)

- **Reranking middleware**
  - Middleware that can call external rerankers (e.g., Cohere, Jina, custom HTTP) and reorder search results after a `query`.
  - Pluggable providers, configurable `top_n`, and safe fallbacks when reranking fails.
- **More middleware building blocks**
  - Request sampling / tracing for debugging complex production issues.
  - Response shaping (e.g., score normalization, custom thresholds) as reusable middleware.
- **Rails UX improvements**
  - Convenience generators and helpers for multi-tenant setups.
  - Better defaults and examples for 1k+ records demos (e‑commerce, blogs, RAG, recommendations).

## Mid Term

- **Additional providers**
  - Support for more hosted / self-hosted vector solutions where it makes sense and stays maintainable.
- **First-class reranking guides**
  - End-to-end documentation for combining vectra-client with external LLMs / rerankers.
- **More recipes & patterns**
  - Deeper recipes for analytics, recommendations, and hybrid search in large Rails apps.

## Long Term Vision

Keep **vectra-client** the most **production-ready Ruby toolkit** for vector databases:

- Strong guarantees around retries, circuit breakers, and backpressure.
- Excellent observability out of the box.
- Stable, provider-agnostic API that lets you change infra without rewriting your app.

If you have ideas or needs that fit this direction, please open an issue on GitHub so we can prioritise the roadmap around real-world use cases.

{
  "cells": [],
  "metadata": {
    "language_info": {
      "name": "python"
    }
  },
  "nbformat": 4,
  "nbformat_minor": 2
}