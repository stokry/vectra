# frozen_string_literal: true

module Vectra
  module Middleware
    # Cost tracking middleware for monitoring API usage costs
    #
    # Tracks estimated costs per operation based on provider pricing.
    # Costs are stored in response metadata and can be aggregated.
    #
    # @example With default pricing
    #   Vectra::Client.use Vectra::Middleware::CostTracker
    #
    # @example With custom pricing
    #   custom_pricing = {
    #     pinecone: { read: 0.0001, write: 0.0002 },
    #     qdrant: { read: 0.00005, write: 0.0001 }
    #   }
    #   Vectra::Client.use Vectra::Middleware::CostTracker, pricing: custom_pricing
    #
    # @example With cost callback
    #   Vectra::Client.use Vectra::Middleware::CostTracker, on_cost: ->(event) {
    #     puts "Cost: $#{event[:cost_usd]} for #{event[:operation]}"
    #   }
    #
    class CostTracker < Base
      # Default pricing per operation (in USD)
      # These are estimated values - check provider pricing for actual costs
      DEFAULT_PRICING = {
        pinecone: { read: 0.0001, write: 0.0002 },
        qdrant: { read: 0.00005, write: 0.0001 },
        weaviate: { read: 0.00008, write: 0.00015 },
        pgvector: { read: 0.0, write: 0.0 }, # Self-hosted, no API costs
        memory: { read: 0.0, write: 0.0 }    # In-memory, no costs
      }.freeze

      # @param pricing [Hash] Custom pricing structure
      # @param on_cost [Proc] Callback to invoke with cost events
      def initialize(pricing: DEFAULT_PRICING, on_cost: nil)
        super()
        @pricing = pricing
        @on_cost = on_cost
      end

      def after(request, response)
        return unless response.success?

        provider = request.provider || :unknown
        operation_type = write_operation?(request.operation) ? :write : :read

        cost = calculate_cost(provider, operation_type, request)
        response.metadata[:cost_usd] = cost

        # Invoke callback if provided
        return unless @on_cost

        @on_cost.call(
          operation: request.operation,
          provider: provider,
          index: request.index,
          cost_usd: cost,
          timestamp: Time.now
        )
      end

      private

      # Check if operation is a write operation
      #
      # @param operation [Symbol] The operation type
      # @return [Boolean] true if write operation
      def write_operation?(operation)
        [:upsert, :delete, :update, :create_index, :delete_index].include?(operation)
      end

      # Calculate cost for operation
      #
      # @param provider [Symbol] Provider name
      # @param operation_type [Symbol] :read or :write
      # @param request [Request] The request object
      # @return [Float] Cost in USD
      def calculate_cost(provider, operation_type, request)
        rate = @pricing.dig(provider, operation_type) || 0.0
        multiplier = operation_multiplier(request)
        rate * multiplier
      end

      # Calculate multiplier for operation based on batch size
      #
      # @param request [Request] The request object
      # @return [Integer, Float] Multiplier for the base rate
      def operation_multiplier(request)
        return 100 if delete_all?(request)

        case request.operation
        when :upsert
          collection_size(request.params[:vectors])
        when :fetch, :delete
          collection_size(request.params[:ids])
        else
          1 # Includes :query and all other operations
        end
      end

      # Check if request is a delete_all operation
      #
      # @param request [Request] The request object
      # @return [Boolean]
      def delete_all?(request)
        request.operation == :delete && request.params[:delete_all]
      end

      # Safely compute collection size with a default of 1
      #
      # @param collection [Enumerable, nil]
      # @return [Integer]
      def collection_size(collection)
        collection&.size || 1
      end
    end
  end
end
