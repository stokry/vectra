# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"

module Vectra
  module Providers
    # Abstract base class for vector database providers
    #
    # All provider implementations must inherit from this class
    # and implement the required methods.
    #
    class Base
      attr_reader :config

      # Initialize the provider
      #
      # @param config [Configuration] the configuration object
      def initialize(config)
        @config = config
        validate_config!
      end

      # Upsert vectors into an index
      #
      # @param index [String] the index/collection name
      # @param vectors [Array<Hash, Vector>] vectors to upsert
      # @param namespace [String, nil] optional namespace
      # @return [Hash] upsert response
      def upsert(index:, vectors:, namespace: nil)
        raise NotImplementedError, "#{self.class} must implement #upsert"
      end

      # Query vectors by similarity
      #
      # @param index [String] the index/collection name
      # @param vector [Array<Float>] query vector
      # @param top_k [Integer] number of results to return
      # @param namespace [String, nil] optional namespace
      # @param filter [Hash, nil] metadata filter
      # @param include_values [Boolean] include vector values in response
      # @param include_metadata [Boolean] include metadata in response
      # @return [QueryResult] query results
      def query(index:, vector:, top_k: 10, namespace: nil, filter: nil,
                include_values: false, include_metadata: true)
        raise NotImplementedError, "#{self.class} must implement #query"
      end

      # Fetch vectors by IDs
      #
      # @param index [String] the index/collection name
      # @param ids [Array<String>] vector IDs to fetch
      # @param namespace [String, nil] optional namespace
      # @return [Hash<String, Vector>] fetched vectors
      def fetch(index:, ids:, namespace: nil)
        raise NotImplementedError, "#{self.class} must implement #fetch"
      end

      # Update a vector's metadata
      #
      # @param index [String] the index/collection name
      # @param id [String] vector ID
      # @param metadata [Hash] new metadata
      # @param namespace [String, nil] optional namespace
      # @return [Hash] update response
      def update(index:, id:, metadata:, namespace: nil)
        raise NotImplementedError, "#{self.class} must implement #update"
      end

      # Delete vectors
      #
      # @param index [String] the index/collection name
      # @param ids [Array<String>, nil] vector IDs to delete
      # @param namespace [String, nil] optional namespace
      # @param filter [Hash, nil] delete by metadata filter
      # @param delete_all [Boolean] delete all vectors
      # @return [Hash] delete response
      def delete(index:, ids: nil, namespace: nil, filter: nil, delete_all: false)
        raise NotImplementedError, "#{self.class} must implement #delete"
      end

      # List indexes/collections
      #
      # @return [Array<Hash>] list of indexes
      def list_indexes
        raise NotImplementedError, "#{self.class} must implement #list_indexes"
      end

      # Describe an index
      #
      # @param index [String] the index name
      # @return [Hash] index details
      def describe_index(index:)
        raise NotImplementedError, "#{self.class} must implement #describe_index"
      end

      # Get index statistics
      #
      # @param index [String] the index name
      # @param namespace [String, nil] optional namespace
      # @return [Hash] index statistics
      def stats(index:, namespace: nil)
        raise NotImplementedError, "#{self.class} must implement #stats"
      end

      # Provider name
      #
      # @return [Symbol]
      def provider_name
        raise NotImplementedError, "#{self.class} must implement #provider_name"
      end

      protected

      # Build HTTP connection with retry logic
      #
      # @param base_url [String] base URL for the API
      # @param headers [Hash] request headers
      # @return [Faraday::Connection]
      def build_connection(base_url, headers = {})
        Faraday.new(url: base_url) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/

          conn.request :retry, {
            max: config.max_retries,
            interval: config.retry_delay,
            interval_randomness: 0.5,
            backoff_factor: 2,
            retry_statuses: [429, 500, 502, 503, 504],
            exceptions: [
              Faraday::TimeoutError,
              Faraday::ConnectionFailed
            ]
          }

          conn.headers = default_headers.merge(headers)
          conn.options.timeout = config.timeout
          conn.options.open_timeout = config.open_timeout

          conn.adapter Faraday.default_adapter
        end
      end

      # Default headers for all requests
      #
      # @return [Hash]
      def default_headers
        {
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "User-Agent" => "vectra-ruby/#{Vectra::VERSION}"
        }
      end

      # Normalize vectors for API request
      #
      # @param vectors [Array<Hash, Vector>] vectors to normalize
      # @return [Array<Hash>]
      def normalize_vectors(vectors)
        vectors.map do |vec|
          case vec
          when Vector
            vec.to_h
          when Hash
            normalize_vector_hash(vec)
          else
            raise ValidationError, "Vector must be a Hash or Vectra::Vector"
          end
        end
      end

      # Normalize a single vector hash
      #
      # @param hash [Hash] vector hash
      # @return [Hash]
      def normalize_vector_hash(hash)
        hash = hash.transform_keys(&:to_sym)

        result = {
          id: hash[:id].to_s,
          values: hash[:values].map(&:to_f)
        }

        result[:metadata] = hash[:metadata] if hash[:metadata]
        result[:sparse_values] = hash[:sparse_values] if hash[:sparse_values]

        result
      end

      # Handle API errors
      #
      # @param response [Faraday::Response] the response
      # @raise [Error] appropriate error for the response
      def handle_error(response)
        status = response.status
        body = response.body

        error_message = extract_error_message(body)

        case status
        when 400
          raise ValidationError.new(error_message, response: response)
        when 401
          raise AuthenticationError.new(error_message, response: response)
        when 403
          raise AuthenticationError.new("Access forbidden: #{error_message}", response: response)
        when 404
          raise NotFoundError.new(error_message, response: response)
        when 429
          retry_after = response.headers["retry-after"]&.to_i
          raise RateLimitError.new(error_message, retry_after: retry_after, response: response)
        when 500..599
          raise ServerError.new(error_message, status_code: status, response: response)
        else
          raise Error.new("Request failed with status #{status}: #{error_message}", response: response)
        end
      end

      # Handle Faraday::RetriableResponse from retry middleware
      # This is raised when all retries are exhausted
      #
      # @param exception [Faraday::RetriableResponse] the exception
      # @raise [Error] appropriate error for the response
      def handle_retriable_response(exception)
        response = exception.response
        handle_error(response)
      end

      # Extract error message from response body
      #
      # @param body [Hash, String, nil] response body
      # @return [String]
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def extract_error_message(body)
        case body
        when Hash
          # Primary error message
          msg = body["message"] || body["error"] || body["error_message"] || body.to_s

          # Add context from details
          details = body["details"] || body["error_details"] || body["detail"]
          if details
            details_str = details.is_a?(Hash) ? details.to_json : details.to_s
            msg += " (#{details_str})" unless msg.include?(details_str)
          end

          # Add field-specific errors if available
          if body["errors"].is_a?(Array)
            field_errors = body["errors"].map { |e| e.is_a?(Hash) ? e["field"] || e["message"] : e }.join(", ")
            msg += " [Fields: #{field_errors}]" if field_errors && !msg.include?(field_errors)
          end

          msg
        when String
          body
        else
          "Unknown error"
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Log debug information
      #
      # @param message [String] message to log
      # @param data [Hash] optional data to log
      def log_debug(message, data = nil)
        return unless config.logger

        config.logger.debug("[Vectra] #{message}")
        config.logger.debug("[Vectra] #{data.inspect}") if data
      end

      # Log error information
      #
      # @param message [String] message to log
      # @param error [Exception, nil] optional error
      def log_error(message, error = nil)
        return unless config.logger

        config.logger.error("[Vectra] #{message}")
        config.logger.error("[Vectra] #{error.class}: #{error.message}") if error
      end

      private

      def validate_config!
        config.validate!
      end
    end
  end
end
