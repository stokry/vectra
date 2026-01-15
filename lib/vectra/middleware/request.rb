# frozen_string_literal: true

module Vectra
  module Middleware
    # Request object passed through middleware chain
    #
    # @example Basic usage
    #   request = Request.new(
    #     operation: :upsert,
    #     index: 'products',
    #     namespace: 'prod',
    #     vectors: [{ id: 'doc-1', values: [0.1, 0.2, 0.3] }]
    #   )
    #
    #   request.operation # => :upsert
    #   request.index     # => 'products'
    #   request.namespace # => 'prod'
    #   request.metadata[:custom_key] = 'custom_value'
    #
    class Request
      attr_accessor :operation, :index, :namespace, :params, :metadata

      # @param operation [Symbol] The operation type (:upsert, :query, :delete, etc.)
      # @param params [Hash] All parameters for the operation
      def initialize(operation:, **params)
        @operation = operation
        @index = params[:index]
        @namespace = params[:namespace]
        @params = params
        @metadata = {}
      end

      # Convert request back to hash for provider call
      #
      # @return [Hash] Parameters hash
      def to_h
        params
      end

      # Get the provider from params
      #
      # @return [Symbol, nil] Provider name
      def provider
        params[:provider]
      end

      # Check if this is a write operation
      #
      # @return [Boolean]
      def write_operation?
        [:upsert, :delete, :update, :create_index, :delete_index].include?(operation)
      end

      # Check if this is a read operation
      #
      # @return [Boolean]
      def read_operation?
        [:query, :text_search, :hybrid_search, :fetch, :list_indexes, :describe_index, :stats].include?(operation)
      end
    end
  end
end
