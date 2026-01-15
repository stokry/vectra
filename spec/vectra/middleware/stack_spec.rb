# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vectra::Middleware::Stack do
  let(:config) do
    Vectra::Configuration.new.tap do |c|
      c.provider = :memory
    end
  end
  let(:provider) { Vectra::Providers::Memory.new(config) }
  let(:middleware_stack) { [] }
  let(:stack) { described_class.new(provider, middleware_stack) }

  describe "#call" do
    it "calls the provider when no middleware" do
      result = stack.call(:upsert, index: "test", vectors: [{ id: "1", values: [0.1, 0.2, 0.3] }])
      expect(result).to have_key(:upserted_count)
      expect(result[:upserted_count]).to eq(1)
    end

    it "executes middleware in order" do
      execution_order = []

      middleware1_class = Class.new(Vectra::Middleware::Base) do
        define_method(:before) { |_request| execution_order << :middleware1_before }
        define_method(:after) { |_request, _response| execution_order << :middleware1_after }
      end

      middleware2_class = Class.new(Vectra::Middleware::Base) do
        define_method(:before) { |_request| execution_order << :middleware2_before }
        define_method(:after) { |_request, _response| execution_order << :middleware2_after }
      end

      middleware_stack << middleware1_class.new
      middleware_stack << middleware2_class.new

      stack.call(:upsert, index: "test", vectors: [{ id: "1", values: [0.1, 0.2, 0.3] }])

      expect(execution_order).to eq(%i[
        middleware1_before
        middleware2_before
        middleware2_after
        middleware1_after
      ])
    end

    it "raises error from provider" do
      # Force an error by passing invalid vectors
      expect do
        stack.call(:upsert, index: "test", vectors: nil)
      end.to raise_error(StandardError)
    end

    it "allows middleware to handle errors" do
      error_caught = []

      error_handler = Class.new(Vectra::Middleware::Base) do
        define_method(:initialize) do |errors|
          @errors = errors
          super()
        end

        define_method(:on_error) do |_request, error|
          @errors << error
        end
      end

      middleware_stack << error_handler.new(error_caught)

      expect do
        stack.call(:upsert, index: "test", vectors: nil)
      end.to raise_error(StandardError)

      expect(error_caught.first).to be_a(StandardError)
    end
  end
end
