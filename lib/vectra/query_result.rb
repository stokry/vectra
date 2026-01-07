# frozen_string_literal: true

module Vectra
  # Represents results from a vector query
  #
  # @example Working with query results
  #   results = client.query(index: 'my-index', vector: [0.1, 0.2], top_k: 5)
  #   results.each do |match|
  #     puts "ID: #{match.id}, Score: #{match.score}"
  #   end
  #
  class QueryResult
    include Enumerable

    attr_reader :matches, :namespace, :usage

    # Initialize a new QueryResult
    #
    # @param matches [Array<Match>] array of match results
    # @param namespace [String, nil] the namespace queried
    # @param usage [Hash, nil] usage statistics from the provider
    def initialize(matches: [], namespace: nil, usage: nil)
      @matches = matches.map { |m| m.is_a?(Match) ? m : Match.new(**m.transform_keys(&:to_sym)) }
      @namespace = namespace
      @usage = usage
    end

    # Iterate over matches
    #
    # @yield [Match] each match
    def each(&)
      matches.each(&)
    end

    # Get the number of matches
    #
    # @return [Integer]
    def size
      matches.size
    end

    alias length size
    alias count size

    # Check if there are no matches
    #
    # @return [Boolean]
    def empty?
      matches.empty?
    end

    # Get the first match
    #
    # @return [Match, nil]
    def first
      matches.first
    end

    # Get the last match
    #
    # @return [Match, nil]
    def last
      matches.last
    end

    # Get match by index
    #
    # @param index [Integer]
    # @return [Match, nil]
    def [](index)
      matches[index]
    end

    # Get all vector IDs
    #
    # @return [Array<String>]
    def ids
      matches.map(&:id)
    end

    # Get all scores
    #
    # @return [Array<Float>]
    def scores
      matches.map(&:score)
    end

    # Get the highest score
    #
    # @return [Float, nil]
    def max_score
      scores.max
    end

    # Get the lowest score
    #
    # @return [Float, nil]
    def min_score
      scores.min
    end

    # Filter matches by minimum score
    #
    # @param min_score [Float] minimum score threshold
    # @return [QueryResult] new result with filtered matches
    def above_score(min_score)
      filtered = matches.select { |m| m.score >= min_score }
      QueryResult.new(matches: filtered, namespace: namespace, usage: usage)
    end

    # Convert to array of hashes
    #
    # @return [Array<Hash>]
    def to_a
      matches.map(&:to_h)
    end

    # Convert to hash
    #
    # @return [Hash]
    def to_h
      {
        matches: to_a,
        namespace: namespace,
        usage: usage
      }.compact
    end

    # Create QueryResult from provider response
    #
    # @param data [Hash] raw response data
    # @return [QueryResult]
    def self.from_response(data)
      data = data.transform_keys(&:to_sym)
      matches = (data[:matches] || []).map do |match|
        Match.from_hash(match)
      end

      new(
        matches: matches,
        namespace: data[:namespace],
        usage: data[:usage]
      )
    end

    # String representation
    #
    # @return [String]
    def to_s
      "#<Vectra::QueryResult matches=#{size} namespace=#{namespace.inspect}>"
    end

    alias inspect to_s
  end

  # Represents a single match from a query
  class Match
    attr_reader :id, :score, :values, :metadata, :sparse_values

    # Initialize a new Match
    #
    # @param id [String] vector ID
    # @param score [Float] similarity score
    # @param values [Array<Float>, nil] vector values (if requested)
    # @param metadata [Hash, nil] vector metadata (if requested)
    # @param sparse_values [Hash, nil] sparse vector values
    def initialize(id:, score:, values: nil, metadata: nil, sparse_values: nil)
      @id = id.to_s
      @score = score.to_f
      @values = values
      @metadata = metadata&.transform_keys(&:to_s) || {}
      @sparse_values = sparse_values
    end

    # Check if values are included
    #
    # @return [Boolean]
    def values?
      !values.nil?
    end

    # Check if metadata is included
    #
    # @return [Boolean]
    def metadata?
      !metadata.empty?
    end

    # Get metadata value by key
    #
    # @param key [String, Symbol] metadata key
    # @return [Object, nil]
    def [](key)
      metadata[key.to_s]
    end

    # Convert to Vector object
    #
    # @return [Vector]
    # @raise [Error] if values are not included
    def to_vector
      raise Error, "Vector values not included in query result" unless values?

      Vector.new(
        id: id,
        values: values,
        metadata: metadata,
        sparse_values: sparse_values
      )
    end

    # Convert to hash
    #
    # @return [Hash]
    def to_h
      hash = { id: id, score: score }
      hash[:values] = values if values?
      hash[:metadata] = metadata if metadata?
      hash[:sparse_values] = sparse_values if sparse_values
      hash
    end

    # Create Match from hash
    #
    # @param hash [Hash]
    # @return [Match]
    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_sym)
      new(
        id: hash[:id],
        score: hash[:score],
        values: hash[:values],
        metadata: hash[:metadata],
        sparse_values: hash[:sparse_values]
      )
    end

    # Check equality
    #
    # @param other [Match]
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(Match)

      id == other.id && score == other.score
    end

    # String representation
    #
    # @return [String]
    def to_s
      "#<Vectra::Match id=#{id.inspect} score=#{score.round(4)}>"
    end

    alias inspect to_s
  end
end
