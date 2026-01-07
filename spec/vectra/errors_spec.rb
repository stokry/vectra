# frozen_string_literal: true

RSpec.describe "Vectra Errors" do
  describe Vectra::Error do
    it "is a StandardError" do
      expect(described_class).to be < StandardError
    end

    it "stores original error" do
      original = StandardError.new("Original")
      error = described_class.new("Wrapped", original_error: original)

      expect(error.original_error).to eq(original)
    end

    it "stores response" do
      response = double("response")
      error = described_class.new("Error", response: response)

      expect(error.response).to eq(response)
    end
  end

  describe Vectra::ConfigurationError do
    it "inherits from Vectra::Error" do
      expect(described_class).to be < Vectra::Error
    end
  end

  describe Vectra::AuthenticationError do
    it "inherits from Vectra::Error" do
      expect(described_class).to be < Vectra::Error
    end
  end

  describe Vectra::NotFoundError do
    it "inherits from Vectra::Error" do
      expect(described_class).to be < Vectra::Error
    end
  end

  describe Vectra::RateLimitError do
    it "inherits from Vectra::Error" do
      expect(described_class).to be < Vectra::Error
    end

    it "stores retry_after value" do
      error = described_class.new("Rate limited", retry_after: 60)
      expect(error.retry_after).to eq(60)
    end

    it "allows nil retry_after" do
      error = described_class.new("Rate limited")
      expect(error.retry_after).to be_nil
    end
  end

  describe Vectra::ValidationError do
    it "inherits from Vectra::Error" do
      expect(described_class).to be < Vectra::Error
    end

    it "stores validation errors" do
      errors = ["Field is required", "Invalid format"]
      error = described_class.new("Validation failed", errors: errors)

      expect(error.errors).to eq(errors)
    end

    it "defaults to empty errors array" do
      error = described_class.new("Validation failed")
      expect(error.errors).to eq([])
    end
  end

  describe Vectra::ConnectionError do
    it "inherits from Vectra::Error" do
      expect(described_class).to be < Vectra::Error
    end
  end

  describe Vectra::ServerError do
    it "inherits from Vectra::Error" do
      expect(described_class).to be < Vectra::Error
    end

    it "stores status code" do
      error = described_class.new("Server error", status_code: 500)
      expect(error.status_code).to eq(500)
    end
  end

  describe Vectra::UnsupportedProviderError do
    it "inherits from Vectra::Error" do
      expect(described_class).to be < Vectra::Error
    end
  end

  describe Vectra::TimeoutError do
    it "inherits from Vectra::Error" do
      expect(described_class).to be < Vectra::Error
    end
  end

  describe Vectra::BatchError do
    it "inherits from Vectra::Error" do
      expect(described_class).to be < Vectra::Error
    end

    it "stores succeeded and failed items" do
      succeeded = ["item1", "item2"]
      failed = ["item3"]
      error = described_class.new("Batch failed", succeeded: succeeded, failed: failed)

      expect(error.succeeded).to eq(succeeded)
      expect(error.failed).to eq(failed)
    end

    it "defaults to empty arrays" do
      error = described_class.new("Batch failed")

      expect(error.succeeded).to eq([])
      expect(error.failed).to eq([])
    end
  end
end
