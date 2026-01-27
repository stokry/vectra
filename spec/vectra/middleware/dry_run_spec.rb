# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"

RSpec.describe Vectra::Middleware::DryRun do
  let(:middleware) { described_class.new }
  let(:successful_app) do
    lambda do |_req|
      Vectra::Middleware::Response.new(result: { success: true })
    end
  end

  describe "write operations" do
    describe "upsert" do
      let(:request) do
        Vectra::Middleware::Request.new(
          operation: :upsert,
          index: "products",
          namespace: "prod",
          vectors: [
            { id: "vec-1", values: [0.1, 0.2, 0.3] },
            { id: "vec-2", values: [0.4, 0.5, 0.6] }
          ]
        )
      end

      it "intercepts the operation and returns simulated response" do
        response = middleware.call(request, successful_app)

        expect(response.result[:dry_run]).to be true
        expect(response.result[:upserted_count]).to eq(2)
      end

      it "marks response metadata as dry run" do
        response = middleware.call(request, successful_app)

        expect(response.metadata[:dry_run]).to be true
      end

      it "includes operation plan in response metadata" do
        response = middleware.call(request, successful_app)

        plan = response.metadata[:plan]
        expect(plan[:operation]).to eq(:upsert)
        expect(plan[:index]).to eq("products")
        expect(plan[:namespace]).to eq("prod")
        expect(plan[:vector_count]).to eq(2)
        expect(plan[:vector_ids]).to eq(["vec-1", "vec-2"])
      end

      it "does not call the next middleware" do
        call_count = 0
        counting_app = lambda do |_req|
          call_count += 1
          Vectra::Middleware::Response.new(result: { success: true })
        end

        middleware.call(request, counting_app)

        expect(call_count).to eq(0)
      end
    end

    describe "delete" do
      it "intercepts delete by IDs" do
        request = Vectra::Middleware::Request.new(
          operation: :delete,
          index: "products",
          ids: %w[id-1 id-2 id-3]
        )

        response = middleware.call(request, successful_app)

        expect(response.result[:dry_run]).to be true
        expect(response.result[:deleted]).to be true
        expect(response.metadata[:plan][:id_count]).to eq(3)
      end

      it "intercepts delete all" do
        request = Vectra::Middleware::Request.new(
          operation: :delete,
          index: "products",
          delete_all: true
        )

        response = middleware.call(request, successful_app)

        expect(response.result[:dry_run]).to be true
        expect(response.metadata[:plan][:delete_all]).to be true
      end

      it "includes filter in plan when present" do
        request = Vectra::Middleware::Request.new(
          operation: :delete,
          index: "products",
          filter: { category: "old" }
        )

        response = middleware.call(request, successful_app)

        expect(response.metadata[:plan][:filter]).to eq({ category: "old" })
      end
    end

    describe "update" do
      it "intercepts update operation" do
        request = Vectra::Middleware::Request.new(
          operation: :update,
          index: "products",
          id: "vec-1",
          metadata: { title: "Updated" }
        )

        response = middleware.call(request, successful_app)

        expect(response.result[:dry_run]).to be true
        expect(response.result[:updated]).to be true
        expect(response.metadata[:plan][:id]).to eq("vec-1")
        expect(response.metadata[:plan][:has_metadata]).to be true
      end
    end

    describe "create_index" do
      it "intercepts create_index operation" do
        request = Vectra::Middleware::Request.new(
          operation: :create_index,
          name: "new-index",
          dimension: 384,
          metric: "cosine"
        )

        response = middleware.call(request, successful_app)

        expect(response.result[:dry_run]).to be true
        expect(response.result[:created]).to be true
        expect(response.metadata[:plan][:name]).to eq("new-index")
        expect(response.metadata[:plan][:dimension]).to eq(384)
        expect(response.metadata[:plan][:metric]).to eq("cosine")
      end
    end

    describe "delete_index" do
      it "intercepts delete_index operation" do
        request = Vectra::Middleware::Request.new(
          operation: :delete_index,
          name: "old-index"
        )

        response = middleware.call(request, successful_app)

        expect(response.result[:dry_run]).to be true
        expect(response.metadata[:plan][:name]).to eq("old-index")
      end
    end
  end

  describe "read operations" do
    it "passes query through to the next middleware" do
      request = Vectra::Middleware::Request.new(
        operation: :query,
        index: "products",
        vector: [0.1, 0.2, 0.3],
        top_k: 10
      )

      response = middleware.call(request, successful_app)

      expect(response.result[:success]).to be true
      expect(response.metadata[:dry_run]).to be_nil
    end

    it "passes fetch through to the next middleware" do
      request = Vectra::Middleware::Request.new(
        operation: :fetch,
        index: "products",
        ids: ["vec-1"]
      )

      response = middleware.call(request, successful_app)

      expect(response.result[:success]).to be true
      expect(response.metadata[:dry_run]).to be_nil
    end

    it "passes stats through to the next middleware" do
      request = Vectra::Middleware::Request.new(
        operation: :stats,
        index: "products"
      )

      response = middleware.call(request, successful_app)

      expect(response.result[:success]).to be true
    end

    it "passes list_indexes through to the next middleware" do
      request = Vectra::Middleware::Request.new(
        operation: :list_indexes
      )

      response = middleware.call(request, successful_app)

      expect(response.result[:success]).to be true
    end
  end

  describe "logging" do
    let(:log_output) { StringIO.new }
    let(:logger) { Logger.new(log_output) }
    let(:middleware) { described_class.new(logger: logger) }

    it "logs the dry run plan for upsert" do
      request = Vectra::Middleware::Request.new(
        operation: :upsert,
        index: "products",
        vectors: [{ id: "vec-1", values: [0.1, 0.2] }]
      )

      middleware.call(request, successful_app)

      logs = log_output.string
      expect(logs).to include("[DRY RUN]")
      expect(logs).to include("UPSERT")
      expect(logs).to include("index=products")
      expect(logs).to include("vectors=1")
    end

    it "logs delete all operations" do
      request = Vectra::Middleware::Request.new(
        operation: :delete,
        index: "products",
        delete_all: true
      )

      middleware.call(request, successful_app)

      logs = log_output.string
      expect(logs).to include("[DRY RUN]")
      expect(logs).to include("DELETE ALL")
    end

    it "does not log for read operations" do
      request = Vectra::Middleware::Request.new(
        operation: :query,
        index: "products",
        vector: [0.1, 0.2]
      )

      middleware.call(request, successful_app)

      expect(log_output.string).to be_empty
    end
  end

  describe "on_dry_run callback" do
    it "invokes the callback with the operation plan" do
      captured_plans = []
      middleware = described_class.new(on_dry_run: ->(plan) { captured_plans << plan })

      request = Vectra::Middleware::Request.new(
        operation: :upsert,
        index: "products",
        vectors: [{ id: "vec-1", values: [0.1, 0.2] }]
      )

      middleware.call(request, successful_app)

      expect(captured_plans.size).to eq(1)
      expect(captured_plans.first[:operation]).to eq(:upsert)
      expect(captured_plans.first[:vector_count]).to eq(1)
    end

    it "does not invoke callback for read operations" do
      captured_plans = []
      middleware = described_class.new(on_dry_run: ->(plan) { captured_plans << plan })

      request = Vectra::Middleware::Request.new(
        operation: :query,
        index: "products",
        vector: [0.1, 0.2]
      )

      middleware.call(request, successful_app)

      expect(captured_plans).to be_empty
    end
  end

  describe "middleware chain integration" do
    let(:config) do
      Vectra::Configuration.new.tap do |c|
        c.provider = :memory
      end
    end
    let(:provider) { Vectra::Providers::Memory.new(config) }

    it "intercepts writes but allows reads in a full stack" do
      stack = Vectra::Middleware::Stack.new(provider, [described_class.new])

      # Write should be intercepted
      result = stack.call(:upsert, index: "test", vectors: [{ id: "1", values: [0.1, 0.2, 0.3] }])
      expect(result[:dry_run]).to be true

      # Manually upsert to provider for query test
      provider.upsert(index: "test", vectors: [{ id: "1", values: [0.1, 0.2, 0.3] }])

      # Read should pass through
      query_result = stack.call(:query, index: "test", vector: [0.1, 0.2, 0.3], top_k: 5)
      expect(query_result).to be_a(Vectra::QueryResult)
    end
  end
end
