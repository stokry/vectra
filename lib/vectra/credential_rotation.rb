# frozen_string_literal: true

module Vectra
  # Credential rotation helper for seamless API key updates
  #
  # Provides utilities for rotating API keys without downtime by supporting
  # multiple credentials and gradual migration.
  #
  # @example Basic rotation
  #   rotator = Vectra::CredentialRotator.new(
  #     primary_key: ENV['PINECONE_API_KEY'],
  #     secondary_key: ENV['PINECONE_API_KEY_NEW']
  #   )
  #
  #   # Test new key before switching
  #   if rotator.test_secondary
  #     rotator.switch_to_secondary
  #   end
  #
  class CredentialRotator
    attr_reader :primary_key, :secondary_key, :current_key

    # Initialize credential rotator
    #
    # @param primary_key [String] Current active API key
    # @param secondary_key [String, nil] New API key to rotate to
    # @param provider [Symbol] Provider name
    # @param test_client [Client, nil] Client instance for testing
    def initialize(primary_key:, secondary_key: nil, provider: nil, test_client: nil)
      @primary_key = primary_key
      @secondary_key = secondary_key
      @provider = provider
      @test_client = test_client
      @current_key = primary_key
      @rotation_complete = false
    end

    # Test if secondary key is valid
    #
    # @return [Boolean] true if secondary key works
    def test_secondary
      return false if secondary_key.nil? || secondary_key.empty?

      client = build_test_client(secondary_key)
      client.healthy?
    rescue StandardError
      false
    end

    # Switch to secondary key
    #
    # @param validate [Boolean] Validate key before switching
    # @return [Boolean] true if switched successfully
    # rubocop:disable Naming/PredicateMethod
    def switch_to_secondary(validate: true)
      return false if secondary_key.nil? || secondary_key.empty?

      if validate && !test_secondary
        raise CredentialRotationError, "Secondary key validation failed"
      end

      @current_key = secondary_key
      @rotation_complete = true
      true
    end
    # rubocop:enable Naming/PredicateMethod

    # Rollback to primary key
    #
    # @return [void]
    def rollback
      @current_key = primary_key
      @rotation_complete = false
    end

    # Check if rotation is complete
    #
    # @return [Boolean]
    def rotation_complete?
      @rotation_complete
    end

    # Get current active key
    #
    # @return [String]
    def active_key
      @current_key
    end

    private

    def build_test_client(key)
      return @test_client if @test_client

      config = Vectra::Configuration.new
      config.provider = @provider || Vectra.configuration.provider
      config.api_key = key
      config.host = Vectra.configuration.host
      config.environment = Vectra.configuration.environment

      Vectra::Client.new(
        provider: config.provider,
        api_key: key,
        host: config.host,
        environment: config.environment
      )
    end
  end

  # Error raised during credential rotation
  class CredentialRotationError < Vectra::Error; end

  # Credential rotation manager for multiple providers
  #
  # @example
  #   manager = Vectra::CredentialRotationManager.new
  #
  #   manager.register(:pinecone,
  #     primary: ENV['PINECONE_API_KEY'],
  #     secondary: ENV['PINECONE_API_KEY_NEW']
  #   )
  #
  #   manager.rotate_all
  #
  module CredentialRotationManager
    class << self
      # Register a credential rotator
      #
      # @param provider [Symbol] Provider name
      # @param primary [String] Primary API key
      # @param secondary [String, nil] Secondary API key
      # @return [CredentialRotator]
      def register(provider, primary:, secondary: nil)
        rotators[provider] = CredentialRotator.new(
          primary_key: primary,
          secondary_key: secondary,
          provider: provider
        )
      end

      # Get rotator for provider
      #
      # @param provider [Symbol] Provider name
      # @return [CredentialRotator, nil]
      def [](provider)
        rotators[provider.to_sym]
      end

      # Test all secondary keys
      #
      # @return [Hash<Symbol, Boolean>] Test results
      def test_all_secondary
        rotators.transform_values(&:test_secondary)
      end

      # Rotate all providers
      #
      # @param validate [Boolean] Validate before rotating
      # @return [Hash<Symbol, Boolean>] Rotation results
      def rotate_all(validate: true)
        rotators.transform_values { |r| r.switch_to_secondary(validate: validate) }
      end

      # Rollback all rotations
      #
      # @return [void]
      def rollback_all
        rotators.each_value(&:rollback)
      end

      # Get rotation status
      #
      # @return [Hash<Symbol, Hash>]
      def status
        rotators.transform_values do |r|
          {
            rotation_complete: r.rotation_complete?,
            has_secondary: !r.secondary_key.nil?,
            active_key: "#{r.active_key[0, 8]}..." # First 8 chars only
          }
        end
      end

      # Clear all rotators
      #
      # @return [void]
      def clear!
        @rotators = {}
      end

      private

      def rotators
        @rotators ||= {}
      end
    end
  end
end
