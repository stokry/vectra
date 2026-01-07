# frozen_string_literal: true

module Vectra
  module Providers
    # Weaviate vector database provider (planned for v0.3.0)
    #
    # @note This provider is not yet implemented
    #
    class Weaviate < Base
      def provider_name
        :weaviate
      end

      def upsert(index:, vectors:, namespace: nil)
        raise NotImplementedError, "Weaviate provider is planned for v0.3.0"
      end

      def query(index:, vector:, top_k: 10, namespace: nil, filter: nil,
                include_values: false, include_metadata: true)
        raise NotImplementedError, "Weaviate provider is planned for v0.3.0"
      end

      def fetch(index:, ids:, namespace: nil)
        raise NotImplementedError, "Weaviate provider is planned for v0.3.0"
      end

      def update(index:, id:, metadata:, namespace: nil)
        raise NotImplementedError, "Weaviate provider is planned for v0.3.0"
      end

      def delete(index:, ids: nil, namespace: nil, filter: nil, delete_all: false)
        raise NotImplementedError, "Weaviate provider is planned for v0.3.0"
      end

      def list_indexes
        raise NotImplementedError, "Weaviate provider is planned for v0.3.0"
      end

      def describe_index(index:)
        raise NotImplementedError, "Weaviate provider is planned for v0.3.0"
      end

      def stats(index:, namespace: nil)
        raise NotImplementedError, "Weaviate provider is planned for v0.3.0"
      end
    end
  end
end
