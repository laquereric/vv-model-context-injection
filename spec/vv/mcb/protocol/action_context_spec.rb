# frozen_string_literal: true

require "spec_helper"

RSpec.describe Vv::Mcb::Protocol::ActionContext do
  let(:progress_calls) { [] }
  let(:log_calls) { [] }

  subject(:ctx) do
    described_class.new(
      invocation_id: "inv_test_001",
      agent: { id: "claude", name: "Claude" },
      agent_capabilities: { sampling: true, elicitation: true },
      client: { origin: "http://localhost:3000", route: "/home" },
      progress_callback: ->(args) { progress_calls << args },
      log_callback: ->(args) { log_calls << args }
    )
  end

  describe "#invocation_id" do
    it "returns the invocation ID" do
      expect(ctx.invocation_id).to eq("inv_test_001")
    end
  end

  describe "#cancelled?" do
    it "is false by default" do
      expect(ctx.cancelled?).to be(false)
    end

    it "is true after cancel! is called" do
      ctx.cancel!
      expect(ctx.cancelled?).to be(true)
    end
  end

  describe "#progress" do
    it "invokes the progress callback with the invocation ID and payload" do
      ctx.progress(message: "processing", percent: 42)
      expect(progress_calls.size).to eq(1)
      call = progress_calls.first
      expect(call[:invocation_id]).to eq("inv_test_001")
      expect(call[:message]).to eq("processing")
      expect(call[:percent]).to eq(42)
    end

    it "is a no-op when the invocation has been cancelled" do
      ctx.cancel!
      ctx.progress(message: "too late", percent: 99)
      expect(progress_calls).to be_empty
    end
  end

  describe "#log" do
    it "invokes the log callback with level, message, and meta" do
      ctx.log(level: "info", message: "Starting", meta: { step: 1 })
      expect(log_calls.size).to eq(1)
      expect(log_calls.first[:level]).to eq("info")
      expect(log_calls.first[:message]).to eq("Starting")
    end
  end

  describe "#confirm" do
    it "returns false when elicitation is not supported" do
      ctx_no_elicit = described_class.new(
        invocation_id: "inv_2",
        agent_capabilities: {}
      )
      expect(ctx_no_elicit.confirm(question: "Are you sure?")).to be(false)
    end

    it "calls the elicitation callback and returns true on acceptance" do
      elicitation_calls = []
      ctx_with_elicit = described_class.new(
        invocation_id: "inv_3",
        agent_capabilities: { elicitation: true },
        elicitation_callback: ->(args) {
          elicitation_calls << args
          true
        }
      )
      result = ctx_with_elicit.confirm(question: "Place order?")
      expect(result).to be(true)
      expect(elicitation_calls.first[:type]).to eq("confirm")
    end
  end
end
