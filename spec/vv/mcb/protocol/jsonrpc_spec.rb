# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vv::Mcb::Protocol do
  describe ".request" do
    it "builds a valid JSON-RPC 2.0 request" do
      msg = described_class.request(id: 1, method: "actions/invoke", params: { name: "test" })
      expect(msg[:jsonrpc]).to eq("2.0")
      expect(msg[:id]).to eq(1)
      expect(msg[:method]).to eq("actions/invoke")
      expect(msg[:params]).to eq({ name: "test" })
    end

    it "omits params when not provided" do
      msg = described_class.request(id: 2, method: "ping")
      expect(msg).not_to have_key(:params)
    end
  end

  describe ".notification" do
    it "builds a valid JSON-RPC 2.0 notification (no id)" do
      msg = described_class.notification(method: "actions/progress", params: { invocationId: "inv_1", percent: 50 })
      expect(msg[:jsonrpc]).to eq("2.0")
      expect(msg).not_to have_key(:id)
      expect(msg[:method]).to eq("actions/progress")
    end
  end

  describe ".success_response" do
    it "builds a valid JSON-RPC 2.0 success response" do
      msg = described_class.success_response(id: 3, result: { items: [] })
      expect(msg[:jsonrpc]).to eq("2.0")
      expect(msg[:id]).to eq(3)
      expect(msg[:result]).to eq({ items: [] })
      expect(msg).not_to have_key(:error)
    end
  end

  describe ".error_response" do
    it "builds a valid JSON-RPC 2.0 error response" do
      msg = described_class.error_response(
        id: 4,
        code: Vv::Mcb::Protocol::ErrorCodes::NOT_FOUND,
        message: "Unknown action",
        data: { action: "missing" }
      )
      expect(msg[:jsonrpc]).to eq("2.0")
      expect(msg[:id]).to eq(4)
      expect(msg[:error][:code]).to eq(-32_003)
      expect(msg[:error][:message]).to eq("Unknown action")
      expect(msg[:error][:data]).to eq({ action: "missing" })
    end

    it "omits data when not provided" do
      msg = described_class.error_response(id: 5, code: -32_601, message: "Not found")
      expect(msg[:error]).not_to have_key(:data)
    end
  end
end
