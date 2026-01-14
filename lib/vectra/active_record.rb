# frozen_string_literal: true

require "active_support/concern"

# Ensure Client and supporting classes are loaded (for Rails autoloading compatibility)
require_relative "client" unless defined?(Vectra::Client)
require_relative "batch" unless defined?(Vectra::Batch)

module Vectra
  # ActiveRecord integration for vector embeddings
  #
  # Provides ActiveRecord models with vector search capabilities.
  #
  # @example Basic usage
  #   class Document < ApplicationRecord
  #     include Vectra::ActiveRecord
  #
  #     has_vector :embedding,
  #                dimension: 384,
  #                provider: :pgvector,
  #                index: 'documents'
  #   end
  #
  #   # Auto-index on create/update
  #   doc = Document.create!(title: 'Hello', embedding: [0.1, 0.2, ...])
  #
  #   # Search similar documents
  #   results = Document.vector_search([0.1, 0.2, ...], limit: 10)
  #
  # rubocop:disable Metrics/ModuleLength
  module ActiveRecord
    extend ActiveSupport::Concern

    included do
      class_attribute :_vectra_config, default: {}
      class_attribute :_vectra_client
    end

    class_methods do
      # Define a vector attribute
      #
      # @param attribute [Symbol] The attribute name (e.g., :embedding)
      # @param dimension [Integer] Vector dimension
      # @param provider [Symbol] Provider name (:pinecone, :pgvector, etc.)
      # @param index [String] Index/collection name
      # @param auto_index [Boolean] Automatically index on save
      # @param metadata_fields [Array<Symbol>] Fields to include in metadata
      #
      # @example
      #   has_vector :embedding,
      #              dimension: 384,
      #              provider: :pgvector,
      #              index: 'documents',
      #              auto_index: true,
      #              metadata_fields: [:title, :category, :status]
      #
      def has_vector(attribute, dimension:, provider: nil, index: nil, auto_index: true, metadata_fields: [])
        self._vectra_config = {
          attribute: attribute,
          dimension: dimension,
          provider: provider || Vectra.configuration.provider,
          index: index || table_name,
          auto_index: auto_index,
          metadata_fields: metadata_fields
        }

        # Initialize client lazily
        define_singleton_method(:vectra_client) do
          @_vectra_client ||= Vectra::Client.new(provider: _vectra_config[:provider])
        end

        # Callbacks for auto-indexing
        if auto_index
          after_save :_vectra_index_vector
          after_destroy :_vectra_delete_vector
        end

        # Class methods for search
        define_singleton_method(:vector_search) do |query_vector, limit: 10, **options|
          _vectra_search(query_vector, limit: limit, **options)
        end

        define_singleton_method(:similar_to) do |record, limit: 10, **options|
          vector = record.send(_vectra_config[:attribute])
          raise ArgumentError, "Record has no vector" if vector.nil?

          _vectra_search(vector, limit: limit, **options)
        end
      end

      # Reindex all vectors for this model using current configuration.
      #
      # @param scope [ActiveRecord::Relation] records to reindex (default: all)
      # @param batch_size [Integer] number of records per batch
      # @param on_progress [Proc, nil] optional callback called after each batch
      #   Receives a hash with :processed and :total keys (and any other stats from Batch)
      #
      # @return [Integer] number of records processed
      def reindex_vectors(scope: all, batch_size: 1_000, on_progress: nil)
        config = _vectra_config
        client = vectra_client
        batch = Vectra::Batch.new(client)

        processed = 0

        scope.in_batches(of: batch_size).each do |relation|
          records = relation.to_a

          vectors = records.map do |record|
            vector = record.send(config[:attribute])
            next if vector.nil?

            metadata = config[:metadata_fields].each_with_object({}) do |field, hash|
              hash[field.to_s] = record.send(field) if record.respond_to?(field)
            end

            {
              id: "#{config[:index]}_#{record.id}",
              values: vector,
              metadata: metadata
            }
          end.compact

          next if vectors.empty?

          batch.upsert_async(
            index: config[:index],
            vectors: vectors,
            namespace: nil,
            on_progress: on_progress
          )

          processed += vectors.size
        end

        processed
      end

      # Search vectors
      #
      # @api private
      def _vectra_search(query_vector, limit: 10, filter: {}, score_threshold: nil, load_records: true)
        config = _vectra_config
        results = vectra_client.query(
          index: config[:index],
          vector: query_vector,
          top_k: limit,
          filter: filter
        )

        # Filter by score if threshold provided
        results = results.above_score(score_threshold) if score_threshold

        return results unless load_records

        # Load ActiveRecord objects
        ids = results.map { |match| match.id.gsub("#{config[:index]}_", "").to_i }
        records = where(id: ids).index_by(&:id)

        results.map do |match|
          id = match.id.gsub("#{config[:index]}_", "").to_i
          record = records[id]
          next unless record

          record.instance_variable_set(:@_vectra_score, match.score)
          record.define_singleton_method(:vector_score) { @_vectra_score }
          record
        end.compact
      end
    end

    # Instance methods

    # Index this record's vector
    #
    # @return [void]
    def index_vector!
      config = self.class._vectra_config
      vector_data = send(config[:attribute])

      raise ArgumentError, "#{config[:attribute]} is nil" if vector_data.nil?

      metadata = config[:metadata_fields].each_with_object({}) do |field, hash|
        hash[field.to_s] = send(field) if respond_to?(field)
      end

      self.class.vectra_client.upsert(
        index: config[:index],
        vectors: [{
          id: _vectra_vector_id,
          values: vector_data,
          metadata: metadata
        }]
      )
    end

    # Delete this record's vector from index
    #
    # @return [void]
    def delete_vector!
      config = self.class._vectra_config

      self.class.vectra_client.delete(
        index: config[:index],
        ids: [_vectra_vector_id]
      )
    end

    # Find similar records
    #
    # @param limit [Integer] Number of results
    # @param filter [Hash] Metadata filter
    # @return [Array<ActiveRecord::Base>]
    def similar(limit: 10, filter: {})
      config = self.class._vectra_config
      vector_data = send(config[:attribute])

      raise ArgumentError, "#{config[:attribute]} is nil" if vector_data.nil?

      self.class._vectra_search(vector_data, limit: limit + 1, filter: filter)
        .reject { |record| record.id == id } # Exclude self
        .first(limit)
    end

    private

    # Auto-index callback
    def _vectra_index_vector
      return unless saved_change_to_attribute?(self.class._vectra_config[:attribute])

      index_vector!
    rescue StandardError => e
      Rails.logger.error("Vectra auto-index failed: #{e.message}") if defined?(Rails)
    end

    # Auto-delete callback
    def _vectra_delete_vector
      delete_vector!
    rescue StandardError => e
      Rails.logger.error("Vectra auto-delete failed: #{e.message}") if defined?(Rails)
    end

    # Generate vector ID
    def _vectra_vector_id
      "#{self.class._vectra_config[:index]}_#{id}"
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
