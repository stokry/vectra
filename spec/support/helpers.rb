# frozen_string_literal: true

module SpecHelpers
  # Create sample vector data for tests
  def sample_vector(id: "vec1", dimension: 3, metadata: nil)
    {
      id: id,
      values: Array.new(dimension) { rand },
      metadata: metadata || { text: "Sample #{id}" }
    }
  end

  # Create multiple sample vectors
  def sample_vectors(count: 3, dimension: 3)
    Array.new(count) { |i| sample_vector(id: "vec#{i + 1}", dimension: dimension) }
  end

  # Create a sample query result match
  def sample_match(id: "vec1", score: 0.95, values: nil, metadata: nil)
    {
      id: id,
      score: score,
      values: values,
      metadata: metadata || { text: "Sample #{id}" }
    }
  end

  # Stub successful HTTP response
  def stub_success_response(body = {})
    instance_double(Faraday::Response, success?: true, status: 200, body: body)
  end

  # Stub error HTTP response
  def stub_error_response(status:, body: {})
    instance_double(Faraday::Response, success?: false, status: status, body: body, headers: {})
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
end
