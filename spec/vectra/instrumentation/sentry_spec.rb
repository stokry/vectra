# frozen_string_literal: true

require "spec_helper"
require "vectra/instrumentation/sentry"

# rubocop:disable RSpec/InstanceVariable, Naming/AccessorMethodName, Naming/MethodParameterName
RSpec.describe Vectra::Instrumentation::Sentry do
  # Mock Sentry module
  let(:mock_sentry) do
    Module.new do
      class << self
        attr_accessor :breadcrumbs, :captured_exceptions, :last_scope

        def add_breadcrumb(breadcrumb)
          @breadcrumbs ||= []
          @breadcrumbs << breadcrumb
        end

        def with_scope
          @last_scope = MockScope.new
          yield @last_scope
        end

        def capture_exception(error)
          @captured_exceptions ||= []
          @captured_exceptions << error
        end

        def reset!
          @breadcrumbs = []
          @captured_exceptions = []
          @last_scope = nil
        end
      end
    end
  end

  # Mock Breadcrumb class
  let(:mock_breadcrumb_class) do
    Class.new do
      attr_reader :category, :message, :level, :data

      def initialize(category:, message:, level:, data:)
        @category = category
        @message = message
        @level = level
        @data = data
      end
    end
  end

  # Mock Scope class
  let(:mock_scope_class) do
    Class.new do
      attr_reader :tags, :context, :fingerprint, :level

      def set_tags(tags)
        @tags = tags
      end

      def set_context(name, ctx)
        @context ||= {}
        @context[name] = ctx
      end

      def set_fingerprint(fp)
        @fingerprint = fp
      end

      def set_level(lvl)
        @level = lvl
      end
    end
  end

  before do
    Vectra::Instrumentation.clear_handlers!

    # Setup mock Sentry module with nested classes
    stub_const("MockScope", mock_scope_class)
    stub_const("Sentry", mock_sentry)
    stub_const("Sentry::Breadcrumb", mock_breadcrumb_class)

    Sentry.reset!
  end

  describe ".setup!" do
    it "registers instrumentation handler" do
      described_class.setup!

      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0,
        metadata: { result_count: 5 }
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Sentry.breadcrumbs.size).to eq(1)
      expect(Sentry.breadcrumbs.first.category).to eq("vectra")
    end
  end

  describe "breadcrumb recording" do
    before { described_class.setup! }

    it "records breadcrumb for successful operation" do
      event = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :qdrant,
        index: "vectors",
        duration: 50.0,
        metadata: { vector_count: 10 }
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      breadcrumb = Sentry.breadcrumbs.first
      expect(breadcrumb.level).to eq("info")
      expect(breadcrumb.data[:provider]).to eq("qdrant")
      expect(breadcrumb.data[:vector_count]).to eq(10)
    end

    it "records error breadcrumb for failed operation" do
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0,
        error: Vectra::ServerError.new("Server error")
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      breadcrumb = Sentry.breadcrumbs.first
      expect(breadcrumb.level).to eq("error")
    end
  end

  describe "error capturing" do
    before { described_class.setup! }

    it "captures exception on failure" do
      error = Vectra::ServerError.new("Server error")
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0,
        error: error
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Sentry.captured_exceptions).to include(error)
    end

    it "sets appropriate tags" do
      event = Vectra::Instrumentation::Event.new(
        operation: :upsert,
        provider: :qdrant,
        index: "my-index",
        duration: 50.0,
        error: Vectra::ServerError.new("fail")
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Sentry.last_scope.tags[:vectra_provider]).to eq("qdrant")
      expect(Sentry.last_scope.tags[:vectra_operation]).to eq("upsert")
    end

    it "sets fingerprint for error grouping" do
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0,
        error: Vectra::RateLimitError.new("Rate limited")
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Sentry.last_scope.fingerprint).to eq(
        ["vectra", "pinecone", "query", "Vectra::RateLimitError"]
      )
    end

    it "sets warning level for rate limit errors" do
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0,
        error: Vectra::RateLimitError.new("Rate limited")
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Sentry.last_scope.level).to eq(:warning)
    end

    it "sets fatal level for auth errors" do
      event = Vectra::Instrumentation::Event.new(
        operation: :query,
        provider: :pinecone,
        index: "test",
        duration: 100.0,
        error: Vectra::AuthenticationError.new("Invalid key")
      )

      Vectra::Instrumentation.send(:notify_handlers, event)

      expect(Sentry.last_scope.level).to eq(:fatal)
    end
  end
end
# rubocop:enable RSpec/InstanceVariable, Naming/AccessorMethodName, Naming/MethodParameterName
