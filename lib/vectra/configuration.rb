# frozen_string_literal: true

module Vectra
  # Configuration class for Vectra
  #
  # @example Configure Vectra globally
  #   Vectra.configure do |config|
  #     config.provider = :pinecone
  #     config.api_key = ENV['PINECONE_API_KEY']
  #     config.environment = 'us-east-1'
  #   end
  #
  class Configuration
    SUPPORTED_PROVIDERS = %i[pinecone qdrant weaviate pgvector].freeze

    attr_accessor :api_key, :environment, :host, :timeout, :open_timeout,
                  :max_retries, :retry_delay, :logger

    attr_reader :provider

    def initialize
      @provider = nil
      @api_key = nil
      @environment = nil
      @host = nil
      @timeout = 30
      @open_timeout = 10
      @max_retries = 3
      @retry_delay = 1
      @logger = nil
    end

    # Set the provider
    #
    # @param value [Symbol, String] the provider name
    # @raise [UnsupportedProviderError] if provider is not supported
    def provider=(value)
      provider_sym = value.to_sym

      unless SUPPORTED_PROVIDERS.include?(provider_sym)
        raise UnsupportedProviderError,
              "Provider '#{value}' is not supported. " \
              "Supported providers: #{SUPPORTED_PROVIDERS.join(', ')}"
      end

      @provider = provider_sym
    end

    # Validate the configuration
    #
    # @raise [ConfigurationError] if configuration is invalid
    def validate!
      raise ConfigurationError, "Provider must be configured" if provider.nil?
      raise ConfigurationError, "API key must be configured" if api_key.nil? || api_key.empty?

      validate_provider_specific!
    end

    # Check if configuration is valid
    #
    # @return [Boolean]
    def valid?
      validate!
      true
    rescue ConfigurationError
      false
    end

    # Create a duplicate configuration
    #
    # @return [Configuration]
    def dup
      config = Configuration.new
      config.instance_variable_set(:@provider, @provider)
      config.api_key = @api_key
      config.environment = @environment
      config.host = @host
      config.timeout = @timeout
      config.open_timeout = @open_timeout
      config.max_retries = @max_retries
      config.retry_delay = @retry_delay
      config.logger = @logger
      config
    end

    # Convert configuration to hash
    #
    # @return [Hash]
    def to_h
      {
        provider: provider,
        api_key: api_key,
        environment: environment,
        host: host,
        timeout: timeout,
        open_timeout: open_timeout,
        max_retries: max_retries,
        retry_delay: retry_delay
      }
    end

    private

    def validate_provider_specific!
      case provider
      when :pinecone
        validate_pinecone!
      when :qdrant
        validate_qdrant!
      when :weaviate
        validate_weaviate!
      when :pgvector
        validate_pgvector!
      end
    end

    def validate_pinecone!
      return unless environment.nil? && host.nil?

      raise ConfigurationError,
            "Pinecone requires either 'environment' or 'host' to be configured"
    end

    def validate_qdrant!
      return unless host.nil?

      raise ConfigurationError, "Qdrant requires 'host' to be configured"
    end

    def validate_weaviate!
      return unless host.nil?

      raise ConfigurationError, "Weaviate requires 'host' to be configured"
    end

    def validate_pgvector!
      return unless host.nil?

      raise ConfigurationError, "pgvector requires 'host' (connection URL or hostname) to be configured"
    end
  end

  class << self
    attr_writer :configuration

    # Get the current configuration
    #
    # @return [Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Configure Vectra
    #
    # @yield [Configuration] the configuration object
    # @return [Configuration]
    def configure
      yield(configuration)
      configuration
    end

    # Reset configuration to defaults
    #
    # @return [Configuration]
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
