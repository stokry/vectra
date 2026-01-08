# frozen_string_literal: true

require "spec_helper"
require "vectra/instrumentation/honeybadger"

RSpec.describe Vectra::Instrumentation::Honeybadger do
  # Mock Honeybadger module
  let(:mock_honeybadger) do
    Module.new do
      class << self
        attr_accessor :breadcrumbs, :notifications

        def add_breadcrumb(message, category:, metadata:)
          @breadcrumbs ||= []
          @breadcrumbs << { message: message, category: category, metadata: metadata }
        end

        def notify(error, context:, tags:, fingerprint:)
          @notifications ||= []
          @notifications << {
            error: error,
            context: context,
            tags: tags,
            fingerprint: fingerprint
          }
        end

        def reset!
          @breadcrumbs = []
          @notifications = []
        end
      end
    end
  end

  before do
    Vectra::Instrumentation.clear_handlers!
    stub_const("Honeybadger", mock_honeybadger)
    Honeybadger.reset!
  end

  describe ".setup!" do
    it "registers instrumentation handler" do
      described_class.setup!

      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Honeybadger.breadcrumbs.size).to eq(1)
    end
  end

  describe "breadcrumb recording" do
    before { described_class.setup! }

    it "adds breadcrumb for each operation" do
      event = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :qdrant,
        index: "vectors",
        duration: 50.0,
        metadata: { vector_count: 10 }
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      breadcrumb = Honeybadger.breadcrumbs.first
      expect(breadcrumb[:message]).to eq("Vectra upsert")
      expect(breadcrumb[:category]).to eq("vectra")
      expect(breadcrumb[:metadata][:vector_count]).to eq(10)
      expect(breadcrumb[:metadata][:success]).to be true
    end
  end

  describe "error notification" do
    before { described_class.setup! }

    it "notifies on server errors" do
      error = Vectra::ServerError.new("Server down")
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0,
        error: error
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Honeybadger.notifications.size).to eq(1)
      expect(Honeybadger.notifications.first[:error]).to eq(error)
    end

    it "includes vectra context" do
      error = Vectra::ServerError.new("fail")
      event = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :qdrant,
        index: "my-index",
        duration: 50.0,
        error: error
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      context = Honeybadger.notifications.first[:context][:vectra]
      expect(context[:provider]).to eq("qdrant")
      expect(context[:operation]).to eq("upsert")
      expect(context[:index]).to eq("my-index")
    end

    it "includes severity tags" do
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0,
        error: Vectra::AuthenticationError.new("Invalid key")
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      tags = Honeybadger.notifications.first[:tags]
      expect(tags).to include("severity:critical")
    end

    it "does not notify on rate limit by default" do
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0,
        error: Vectra::RateLimitError.new("Rate limited")
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Honeybadger.notifications).to be_empty
    end

    it "notifies on rate limit when enabled" do
      # Clear handlers and re-setup with rate limit enabled
      Vectra::Instrumentation.clear_handlers!
      described_class.setup!(notify_on_rate_limit: true)

      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0,
        error: Vectra::RateLimitError.new("Rate limited")
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Honeybadger.notifications.size).to eq(1)
    end

    it "does not notify on validation errors by default" do
      event = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :pinecone,
        index: "test",
        duration: 50.0,
        error: Vectra::ValidationError.new("Invalid vector")
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Honeybadger.notifications).to be_empty
    end

    it "creates fingerprint for error grouping" do
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :qdrant,
        index: "test",
        duration: 100.0,
        error: Vectra::ServerError.new("Error")
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      fingerprint = Honeybadger.notifications.first[:fingerprint]
      expect(fingerprint).to eq("vectra-qdrant-query-Vectra::ServerError")
    end
  end
end
