# frozen_string_literal: true

module Vectra
  module Middleware
    # Response object returned through middleware chain
    #
    # @example Success response
    #   response = Response.new(result: { success: true })
    #   response.success? # => true
    #   response.result   # => { success: true }
    #
    # @example Error response
    #   response = Response.new(error: StandardError.new('Failed'))
    #   response.failure? # => true
    #   response.error    # => #<StandardError: Failed>
    #
    # @example With metadata
    #   response = Response.new(result: [])
    #   response.metadata[:duration_ms] = 45
    #   response.metadata[:cache_hit] = true
    #
    class Response
      attr_accessor :result, :error, :metadata

      # @param result [Object] The successful result
      # @param error [Exception, nil] The error if failed
      def initialize(result: nil, error: nil)
        @result = result
        @error = error
        @metadata = {}
      end

      # Check if the response was successful
      #
      # @return [Boolean] true if no error
      def success?
        error.nil?
      end

      # Check if the response failed
      #
      # @return [Boolean] true if error present
      def failure?
        !success?
      end

      # Raise error if present
      #
      # @raise [Exception] The stored error
      # @return [void]
      def raise_if_error!
        raise error if error
      end

      # Get the result or raise error
      #
      # @return [Object] The result
      # @raise [Exception] If error present
      def value!
        raise_if_error!
        result
      end
    end
  end
end
