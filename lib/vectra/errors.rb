# frozen_string_literal: true

module Vectra
  # Base error class for all Vectra errors
  class Error < StandardError
    attr_reader :original_error, :response

    def initialize(message = nil, original_error: nil, response: nil)
      @original_error = original_error
      @response = response
      super(message)
    end
  end

  # Raised when configuration is invalid or missing
  class ConfigurationError < Error; end

  # Raised when authentication fails
  class AuthenticationError < Error; end

  # Raised when a resource is not found
  class NotFoundError < Error; end

  # Raised when rate limit is exceeded
  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **kwargs)
      @retry_after = retry_after
      super(message, **kwargs)
    end
  end

  # Raised when request validation fails
  class ValidationError < Error
    attr_reader :errors

    def initialize(message = nil, errors: [], **kwargs)
      @errors = errors
      super(message, **kwargs)
    end
  end

  # Raised when there's a connection problem
  class ConnectionError < Error; end

  # Raised when the server returns an error
  class ServerError < Error
    attr_reader :status_code

    def initialize(message = nil, status_code: nil, **kwargs)
      @status_code = status_code
      super(message, **kwargs)
    end
  end

  # Raised when the provider is not supported
  class UnsupportedProviderError < Error; end

  # Raised when an operation times out
  class TimeoutError < Error; end

  # Raised when batch operation partially fails
  class BatchError < Error
    attr_reader :succeeded, :failed

    def initialize(message = nil, succeeded: [], failed: [], **kwargs)
      @succeeded = succeeded
      @failed = failed
      super(message, **kwargs)
    end
  end
end
