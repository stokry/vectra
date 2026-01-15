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
        if @on_cost
          @on_cost.call(
            operation: request.operation,
            provider: provider,
            index: request.index,
            cost_usd: cost,
            timestamp: Time.now
          )
        end
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

        # Multiply by vector count for batch operations
        case request.operation
        when :upsert
          count = request.params[:vectors]&.size || 1
          rate * count
        when :query
          # Query cost is typically per query, not per result
          rate
        when :fetch
          count = request.params[:ids]&.size || 1
          rate * count
        when :delete
          if request.params[:delete_all]
            # Flat rate for delete_all
            rate * 100 # Estimate
          else
            count = request.params[:ids]&.size || 1
            rate * count
          end
        else
          rate
        end
      end
    end
  end
end
