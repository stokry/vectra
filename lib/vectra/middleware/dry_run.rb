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
          explain_upsert(request)
        when :delete
          explain_delete(request)
        when :update
          explain_update(request)
        when :create_index
          explain_create_index(request)
        when :delete_index
          explain_delete_index(request)
        else
          explain_generic(request)
        end
      end

      def explain_upsert(request)
        vector_count = request.params[:vectors]&.size || 0
        "[DRY RUN] UPSERT index=#{request.index} " \
          "namespace=#{request.namespace || 'default'} " \
          "vectors=#{vector_count}"
      end

      def explain_delete(request)
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
      end

      def explain_update(request)
        "[DRY RUN] UPDATE index=#{request.index} " \
          "id=#{request.params[:id]} " \
          "namespace=#{request.namespace || 'default'}"
      end

      def explain_create_index(request)
        dimension = request.params[:dimension]
        metric = request.params[:metric] || "cosine"
        "[DRY RUN] CREATE INDEX name=#{request.index} " \
          "dimension=#{dimension} metric=#{metric}"
      end

      def explain_delete_index(request)
        "[DRY RUN] DELETE INDEX name=#{request.index}"
      end

      def explain_generic(request)
        "[DRY RUN] #{request.operation.upcase} index=#{request.index}"
      end

      def mock_response(request)
        result = build_mock_result(request)
        response = Response.new(result: result)
        response.metadata[:dry_run] = true
        response.metadata[:plan] = build_plan(request)
        response
      end

      def build_mock_result(request)
        operation = request.operation

        # Query operations
        return build_query_result if query_operation?(operation)

        # Write operations with dry_run flag
        return build_write_result(request, operation) if write_operation_for_mock?(operation)

        # Read operations
        return build_read_result(operation) if read_operation_for_mock?(operation)

        # Default
        { success: true }
      end

      def query_operation?(operation)
        %i[query text_search hybrid_search].include?(operation)
      end

      def write_operation_for_mock?(operation)
        %i[upsert delete update create_index delete_index list_namespaces].include?(operation)
      end

      def read_operation_for_mock?(operation)
        %i[fetch list_indexes describe_index stats].include?(operation)
      end

      def build_write_result(request, operation)
        case operation
        when :upsert
          build_upsert_result(request)
        when :delete
          build_delete_result
        when :update
          build_update_result
        when :create_index
          build_create_index_result
        when :delete_index, :list_namespaces
          build_delete_index_result
        end
      end

      def build_read_result(operation)
        case operation
        when :fetch
          {}
        when :list_indexes
          []
        when :describe_index
          { dimension: 1536, metric: "cosine" }
        when :stats
          { total_vector_count: 0 }
        end
      end

      def build_upsert_result(request)
        {
          dry_run: true,
          upserted_count: request.params[:vectors]&.size || 0
        }
      end

      def build_query_result
        require_relative "../query_result"
        QueryResult.new(matches: [])
      end

      def build_delete_result
        {
          dry_run: true,
          deleted: true
        }
      end

      def build_update_result
        {
          dry_run: true,
          updated: true
        }
      end

      def build_create_index_result
        {
          dry_run: true,
          created: true
        }
      end

      def build_delete_index_result
        {
          dry_run: true,
          deleted: true
        }
      end

      def build_plan(request)
        plan = {
          operation: request.operation,
          index: request.index,
          namespace: request.namespace
        }

        case request.operation
        when :upsert
          build_upsert_plan(request, plan)
        when :delete
          build_delete_plan(request, plan)
        when :update
          build_update_plan(request, plan)
        when :create_index
          build_create_index_plan(request, plan)
        when :delete_index
          build_delete_index_plan(request, plan)
        end

        plan
      end

      def build_upsert_plan(request, plan)
        vectors = request.params[:vectors] || []
        plan[:vector_count] = vectors.size
        plan[:vector_ids] = vectors.map { |v| v[:id] || v["id"] }.compact
      end

      def build_delete_plan(request, plan)
        if request.params[:delete_all]
          plan[:delete_all] = true
        elsif request.params[:ids]
          plan[:id_count] = request.params[:ids].size
        end
        plan[:filter] = request.params[:filter] if request.params[:filter]
      end

      def build_update_plan(request, plan)
        plan[:id] = request.params[:id]
        plan[:has_metadata] = !request.params[:metadata].nil?
      end

      def build_create_index_plan(request, plan)
        plan[:name] = request.params[:name] || request.index
        plan[:dimension] = request.params[:dimension]
        plan[:metric] = request.params[:metric]
      end

      def build_delete_index_plan(request, plan)
        plan[:name] = request.params[:name] || request.index
      end
    end
  end
end
