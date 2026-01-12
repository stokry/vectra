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

    # Normalize the vector in-place (mutates the vector)
    #
    # @param type [Symbol] normalization type: :l2 (default) or :l1
    # @return [Vector] self (for method chaining)
    #
    # @example L2 normalization (unit vector)
    #   vector = Vectra::Vector.new(id: 'v1', values: [3.0, 4.0])
    #   vector.normalize!
    #   vector.values # => [0.6, 0.8] (magnitude = 1.0)
    #
    # @example L1 normalization (sum = 1)
    #   vector.normalize!(type: :l1)
    #   vector.values.sum(&:abs) # => 1.0
    def normalize!(type: :l2)
      case type
      when :l2
        magnitude = Math.sqrt(values.sum { |v| v**2 })
        if magnitude.zero?
          # Zero vector - cannot normalize, return as-is
          return self
        end

        @values = values.map { |v| v / magnitude }
      when :l1
        sum = values.sum(&:abs)
        if sum.zero?
          # Zero vector - cannot normalize, return as-is
          return self
        end

        @values = values.map { |v| v / sum }
      else
        raise ArgumentError, "Unknown normalization type: #{type}. Use :l2 or :l1"
      end
      self
    end

    # Normalize a vector array without creating a Vector object
    #
    # @param vector [Array<Float>] vector values to normalize
    # @param type [Symbol] normalization type: :l2 (default) or :l1
    # @return [Array<Float>] normalized vector values
    #
    # @example Normalize OpenAI embedding
    #   embedding = openai_response['data'][0]['embedding']
    #   normalized = Vectra::Vector.normalize(embedding)
    #   client.upsert(vectors: [{ id: '1', values: normalized }])
    #
    # @example L1 normalization
    #   normalized = Vectra::Vector.normalize([1.0, 2.0, 3.0], type: :l1)
    def self.normalize(vector, type: :l2)
      temp_vector = new(id: "temp", values: vector.dup)
      temp_vector.normalize!(type: type)
      temp_vector.values
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
