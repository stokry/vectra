# frozen_string_literal: true

module Vectra
  module Middleware
    # Dry run / explain mode middleware
    #
    # Instead of executing operations, this middleware logs what would be done.
    # Useful for debugging, testing, and understanding operation behavior
    # without side effects.
    #
    # @example Enable dry run mode
    #   client = Vectra::Client.new(
    #     provider: :qdrant,
    #     middleware: [Vectra::Middleware::DryRun]
    #   )
    #
    #   # Operations will be logged but not executed
    #   client.upsert(index: 'test', vectors: [...])
    #   # => [DRY RUN] Would upsert 5 vectors to index 'test'
    #
    # @example With custom logger
    #   logger = Logger.new($stdout)
    #   Vectra::Client.use Vectra::Middleware::DryRun, logger: logger
    #
    # @example With custom explain formatter
    #   formatter = ->(req) { "Would execute: #{req.operation}" }
    #   Vectra::Client.use Vectra::Middleware::DryRun, formatter: formatter
    #
    class DryRun < Base
    # @param logger [Logger, nil] Custom logger (default: Vectra.configuration.logger)
    # @param enabled [Boolean] Enable/disable dry run mode (default: true)
    # @param formatter [Proc, nil] Custom formatter for explain messages
    # @param on_dry_run [Proc, nil] Callback invoked when dry run intercepts operation
    def initialize(logger: nil, enabled: true, formatter: nil, on_dry_run: nil)
      super()
      @logger = logger || Vectra.configuration.logger
      @enabled = enabled
      @formatter = formatter
      @on_dry_run = on_dry_run
    end

    def call(request, app)
      # Only intercept write operations
      return app.call(request) unless @enabled && request.write_operation?

      # Explain what would happen
      explain(request)

      # Build plan and invoke callback
      plan = build_plan(request)
      @on_dry_run&.call(plan)

      # Return a mock response instead of executing
      mock_response(request)
    end

      private

      def explain(request)
        return unless @logger

        message = if @formatter
                    @formatter.call(request)
                  else
                    default_explain(request)
                  end

        @logger.info("[DRY RUN] #{message}")
      end

      def default_explain(request)
        case request.operation
        when :upsert
          vector_count = request.params[:vectors]&.size || 0
          "[DRY RUN] UPSERT index=#{request.index} " \
            "namespace=#{request.namespace || 'default'} " \
            "vectors=#{vector_count}"
        when :delete
          delete_all = request.params[:delete_all] || false
          if delete_all
            "[DRY RUN] DELETE ALL index=#{request.index} " \
              "namespace=#{request.namespace || 'default'}"
          else
            id_count = request.params[:ids]&.size || 0
            "[DRY RUN] DELETE index=#{request.index} " \
              "namespace=#{request.namespace || 'default'} " \
              "ids=#{id_count}"
          end
        when :update
          "[DRY RUN] UPDATE index=#{request.index} " \
            "id=#{request.params[:id]} " \
            "namespace=#{request.namespace || 'default'}"
        when :create_index
          dimension = request.params[:dimension]
          metric = request.params[:metric] || "cosine"
          "[DRY RUN] CREATE INDEX name=#{request.index} " \
            "dimension=#{dimension} metric=#{metric}"
        when :delete_index
          "[DRY RUN] DELETE INDEX name=#{request.index}"
        else
          "[DRY RUN] #{request.operation.upcase} index=#{request.index}"
        end
      end

      def namespace_suffix(namespace)
        namespace ? " (namespace: '#{namespace}')" : ""
      end

      def mock_response(request)
        result = case request.operation
                 when :upsert
                   {
                     dry_run: true,
                     upserted_count: request.params[:vectors]&.size || 0
                   }
                 when :query, :text_search, :hybrid_search
                   require_relative "../query_result"
                   QueryResult.new(matches: [])
                 when :fetch
                   {}
                 when :delete
                   {
                     dry_run: true,
                     deleted: true
                   }
                 when :update
                   {
                     dry_run: true,
                     updated: true
                   }
                 when :create_index
                   {
                     dry_run: true,
                     created: true
                   }
                 when :delete_index
                   {
                     dry_run: true,
                     deleted: true
                   }
                 when :list_indexes
                   []
                 when :describe_index
                   { dimension: 1536, metric: "cosine" }
                 when :stats
                   { total_vector_count: 0 }
                 when :list_namespaces
                   []
                 else
                   { success: true }
                 end

        response = Response.new(result: result)
        response.metadata[:dry_run] = true
        response.metadata[:plan] = build_plan(request)
        response
      end

      def build_plan(request)
        plan = {
          operation: request.operation,
          index: request.index,
          namespace: request.namespace
        }

        case request.operation
        when :upsert
          vectors = request.params[:vectors] || []
          plan[:vector_count] = vectors.size
          plan[:vector_ids] = vectors.map { |v| v[:id] || v["id"] }.compact
        when :delete
          if request.params[:delete_all]
            plan[:delete_all] = true
          elsif request.params[:ids]
            plan[:id_count] = request.params[:ids].size
          end
          plan[:filter] = request.params[:filter] if request.params[:filter]
        when :update
          plan[:id] = request.params[:id]
          plan[:has_metadata] = !request.params[:metadata].nil?
        when :create_index
          plan[:name] = request.params[:name] || request.index
          plan[:dimension] = request.params[:dimension]
          plan[:metric] = request.params[:metric]
        when :delete_index
          plan[:name] = request.params[:name] || request.index
        end

        plan
      end
    end
  end
end
