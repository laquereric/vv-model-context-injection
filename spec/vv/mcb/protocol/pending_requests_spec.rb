# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vv::Mcb::Protocol::PendingRequests do
  subject(:pending) { described_class.new }

  describe "#register and #resolve" do
    it "resolves a pending request with the given response" do
      queue = pending.register(1)
      response = { jsonrpc: "2.0", id: 1, result: { ok: true } }

      Thread.new { sleep 0.01; pending.resolve(1, response) }

      received = pending.wait(queue, timeout: 2)
      expect(received).to eq(response)
    end

    it "ignores resolve calls for unknown ids" do
      expect { pending.resolve(999, {}) }.not_to raise_error
    end
  end

  describe "#reject_all" do
    it "raises TransportClosedError for all pending requests" do
      queue = pending.register(2)

      Thread.new { sleep 0.01; pending.reject_all }

      expect { pending.wait(queue, timeout: 2) }.to raise_error(
        Vv::Mcb::Protocol::PendingRequests::TransportClosedError
      )
    end
  end
end
