# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Vectra::AuditLog do
  let(:output) { StringIO.new }
  let(:audit) { described_class.new(output: output, enabled: true) }

  describe "#initialize" do
    it "creates audit logger" do
      expect(audit.logger).to be_a(Vectra::JsonLogger)
    end

    it "can be disabled" do
      disabled = described_class.new(enabled: false)
      expect(disabled.logger).to be_nil
    end
  end

  describe "#log_access" do
    it "logs access event" do
      audit.log_access(
        user_id: "user123",
        operation: "query",
        index: "my-index",
        result_count: 10
      )

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["event_type"]).to eq("access")
      expect(entry["user_id"]).to eq("user123")
      expect(entry["operation"]).to eq("query")
      expect(entry["resource"]).to eq("my-index")
      expect(entry["result_count"]).to eq(10)
    end
  end

  describe "#log_authentication" do
    it "logs successful authentication" do
      audit.log_authentication(user_id: "user1", success: true, provider: "pinecone")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["event_type"]).to eq("authentication")
      expect(entry["success"]).to be true
      expect(entry["provider"]).to eq("pinecone")
    end

    it "logs failed authentication" do
      audit.log_authentication(user_id: "user1", success: false)

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["success"]).to be false
    end
  end

  describe "#log_authorization" do
    it "logs authorization decision" do
      audit.log_authorization(
        user_id: "user1",
        resource: "sensitive-index",
        allowed: true
      )

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["event_type"]).to eq("authorization")
      expect(entry["allowed"]).to be true
    end

    it "logs denial with reason" do
      audit.log_authorization(
        user_id: "user1",
        resource: "admin-index",
        allowed: false,
        reason: "Insufficient permissions"
      )

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["allowed"]).to be false
      expect(entry["reason"]).to eq("Insufficient permissions")
    end
  end

  describe "#log_configuration_change" do
    it "logs configuration changes" do
      audit.log_configuration_change(
        user_id: "admin",
        change_type: "api_key_rotation",
        old_value: "old-key-12345678",
        new_value: "new-key-87654321"
      )

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["event_type"]).to eq("configuration_change")
      expect(entry["change_type"]).to eq("api_key_rotation")
      # Values should be sanitized
      expect(entry["old_value"]).to match(/old-key-1.*\.\.\..*5678/)
    end

    it "sanitizes API key values" do
      audit.log_configuration_change(
        user_id: "admin",
        change_type: "api_key_update",
        old_value: "pk-1234567890abcdef",
        new_value: "pk-abcdef1234567890"
      )

      output.rewind
      entry = JSON.parse(output.read)

      # Should mask middle portion
      expect(entry["old_value"]).to match(/^pk-1234.*\.\.\.*cdef$/)
    end
  end

  describe "#log_credential_rotation" do
    it "logs credential rotation" do
      audit.log_credential_rotation(
        provider: "pinecone",
        success: true,
        rotated_by: "admin123"
      )

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["event_type"]).to eq("credential_rotation")
      expect(entry["provider"]).to eq("pinecone")
      expect(entry["success"]).to be true
    end
  end

  describe "#log_data_modification" do
    it "logs data modifications" do
      audit.log_data_modification(
        user_id: "user1",
        operation: "upsert",
        index: "vectors",
        record_count: 100
      )

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["event_type"]).to eq("data_modification")
      expect(entry["operation"]).to eq("upsert")
      expect(entry["record_count"]).to eq(100)
    end
  end

  describe "#log_error" do
    it "logs error events with severity" do
      error = Vectra::AuthenticationError.new("Invalid API key")
      audit.log_error(error: error, user_id: "user1")

      output.rewind
      entry = JSON.parse(output.read)

      expect(entry["event_type"]).to eq("error")
      expect(entry["error_class"]).to eq("Vectra::AuthenticationError")
      expect(entry["severity"]).to eq("critical")
    end
  end
end

RSpec.describe Vectra::AuditLogging do
  let(:output) { StringIO.new }

  before do
    described_class.audit_log = nil
  end

  describe ".setup!" do
    it "creates global audit log" do
      described_class.setup!(output: output)
      expect(described_class.audit_log).to be_a(Vectra::AuditLog)
    end
  end

  describe ".log" do
    before { described_class.setup!(output: output) }

    it "logs audit events" do
      described_class.log(:access, user_id: "user1", operation: "query")

      output.rewind
      expect(output.read).to include("audit.access")
    end
  end
end
