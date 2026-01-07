# frozen_string_literal: true

module Vectra
  module Providers
    # Qdrant vector database provider (planned for v0.2.0)
    #
    # @note This provider is not yet implemented
    #
    class Qdrant < Base
      def provider_name
        :qdrant
      end

      def upsert(index:, vectors:, namespace: nil)
        raise NotImplementedError, "Qdrant provider is planned for v0.2.0"
      end

      def query(index:, vector:, top_k: 10, namespace: nil, filter: nil,
                include_values: false, include_metadata: true)
        raise NotImplementedError, "Qdrant provider is planned for v0.2.0"
      end

      def fetch(index:, ids:, namespace: nil)
        raise NotImplementedError, "Qdrant provider is planned for v0.2.0"
      end

      def update(index:, id:, metadata:, namespace: nil)
        raise NotImplementedError, "Qdrant provider is planned for v0.2.0"
      end

      def delete(index:, ids: nil, namespace: nil, filter: nil, delete_all: false)
        raise NotImplementedError, "Qdrant provider is planned for v0.2.0"
      end

      def list_indexes
        raise NotImplementedError, "Qdrant provider is planned for v0.2.0"
      end

      def describe_index(index:)
        raise NotImplementedError, "Qdrant provider is planned for v0.2.0"
      end

      def stats(index:, namespace: nil)
        raise NotImplementedError, "Qdrant provider is planned for v0.2.0"
      end
    end
  end
end
