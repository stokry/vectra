# frozen_string_literal: true

module Vectra
  # Represents a vector with its associated data
  #
  # @example Create a vector
  #   vector = Vectra::Vector.new(
  #     id: 'vec1',
  #     values: [0.1, 0.2, 0.3],
  #     metadata: { text: 'Hello world', category: 'greeting' }
  #   )
  #
  class Vector
    attr_reader :id, :values, :metadata, :sparse_values

    # Initialize a new Vector
    #
    # @param id [String] unique identifier for the vector
    # @param values [Array<Float>] the vector embedding values
    # @param metadata [Hash] optional metadata associated with the vector
    # @param sparse_values [Hash] optional sparse vector values
    def initialize(id:, values:, metadata: nil, sparse_values: nil)
      @id = validate_id!(id)
      @values = validate_values!(values)
      @metadata = metadata&.transform_keys(&:to_s) || {}
      @sparse_values = sparse_values
    end

    # Get the dimension of the vector
    #
    # @return [Integer]
    def dimension
      values.length
    end

    # Check if vector has metadata
    #
    # @return [Boolean]
    def metadata?
      !metadata.empty?
    end

    # Check if vector has sparse values
    #
    # @return [Boolean]
    def sparse?
      !sparse_values.nil? && !sparse_values.empty?
    end

    # Convert vector to hash for API requests
    #
    # @return [Hash]
    def to_h
      hash = {
        id: id,
        values: values
      }
      hash[:metadata] = metadata unless metadata.empty?
      hash[:sparse_values] = sparse_values if sparse?
      hash
    end

    alias to_hash to_h

    # Create a Vector from a hash
    #
    # @param hash [Hash] hash containing vector data
    # @return [Vector]
    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_sym)
      new(
        id: hash[:id],
        values: hash[:values],
        metadata: hash[:metadata],
        sparse_values: hash[:sparse_values]
      )
    end

    # Calculate cosine similarity with another vector
    #
    # @param other [Vector, Array<Float>] the other vector
    # @return [Float] similarity score between -1 and 1
    def cosine_similarity(other)
      other_values = other.is_a?(Vector) ? other.values : other

      raise ArgumentError, "Vectors must have the same dimension" if values.length != other_values.length

      dot_product = values.zip(other_values).sum { |a, b| a * b }
      magnitude_a = Math.sqrt(values.sum { |v| v**2 })
      magnitude_b = Math.sqrt(other_values.sum { |v| v**2 })

      return 0.0 if magnitude_a.zero? || magnitude_b.zero?

      dot_product / (magnitude_a * magnitude_b)
    end

    # Calculate Euclidean distance to another vector
    #
    # @param other [Vector, Array<Float>] the other vector
    # @return [Float] distance (0 = identical)
    def euclidean_distance(other)
      other_values = other.is_a?(Vector) ? other.values : other

      raise ArgumentError, "Vectors must have the same dimension" if values.length != other_values.length

      Math.sqrt(values.zip(other_values).sum { |a, b| (a - b)**2 })
    end

    # Check equality with another vector
    #
    # @param other [Vector] the other vector
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(Vector)

      id == other.id && values == other.values && metadata == other.metadata
    end

    alias eql? ==

    def hash
      [id, values, metadata].hash
    end

    # String representation
    #
    # @return [String]
    def to_s
      "#<Vectra::Vector id=#{id.inspect} dimension=#{dimension} metadata_keys=#{metadata.keys}>"
    end

    alias inspect to_s

    private

    def validate_id!(id)
      raise ValidationError, "Vector ID cannot be nil" if id.nil?
      raise ValidationError, "Vector ID must be a string" unless id.is_a?(String) || id.is_a?(Symbol)

      id.to_s
    end

    def validate_values!(values)
      raise ValidationError, "Vector values cannot be nil" if values.nil?
      raise ValidationError, "Vector values must be an array" unless values.is_a?(Array)
      raise ValidationError, "Vector values cannot be empty" if values.empty?

      unless values.all? { |v| v.is_a?(Numeric) }
        raise ValidationError, "All vector values must be numeric"
      end

      values.map(&:to_f)
    end
  end
end
