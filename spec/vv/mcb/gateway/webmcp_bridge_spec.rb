# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Vv::Mcb::Gateway::WebmcpBridge do
  let(:app) { Vv::Mcb::Server::App.new(id: "ai.example", name: "Example") }

  let(:mcb_adapter) do
    Vv::Mcb::Gateway::WebmcpBridge::McbAdapter.new(
      app: app, websocket_url: "wss://example.test/mcb"
    )
  end

  before do
    app.action("substrate_summary")
      .domain("summary")
      .describe("Summarise the substrate")
      .input_schema({ type: "object" })
      .annotate(read_only: true, untrusted_content: false)
      .handler { |_input, _ctx| { ok: true } }

    app.action("quick_note")
      .domain("notes")
      .describe("Capture a user-authored note")
      .input_schema({ type: "object" })
      .annotate(untrusted_content: true)
      .handler { |_input, _ctx| { ok: true } }
  end

  describe "#collect_tools" do
    subject(:tools) { described_class.new(adapters: [mcb_adapter]).collect_tools }

    it "normalises names to mm.<domain>.<action>" do
      expect(tools.map { |t| t[:name] }).to contain_exactly(
        "mm.summary.substrate_summary",
        "mm.notes.quick_note"
      )
    end

    it "maps annotate(read_only:) to WebMCP readOnlyHint" do
      summary = tools.find { |t| t[:name] == "mm.summary.substrate_summary" }
      expect(summary[:annotations]).to eq(readOnlyHint: true, untrustedContentHint: false)
    end

    it "maps annotate(untrusted_content:) to WebMCP untrustedContentHint" do
      note = tools.find { |t| t[:name] == "mm.notes.quick_note" }
      expect(note[:annotations][:untrustedContentHint]).to be(true)
    end

    it "attaches an mcb_ws transport descriptor from the adapter" do
      tools.each do |t|
        expect(t[:transport]).to eq(
          kind: "mcb_ws", url: "wss://example.test/mcb", method: "action.invoke"
        )
      end
    end

    it "raises MissingDomain when an action has no domain set" do
      app.action("orphan").describe("no domain").handler { |_i, _c| {} }
      expect { described_class.new(adapters: [mcb_adapter]).collect_tools }
        .to raise_error(described_class::MissingDomain, /orphan/)
    end

    it "raises NameCollision when two adapters yield the same URI" do
      bridge = described_class.new(adapters: [mcb_adapter, mcb_adapter])
      expect { bridge.collect_tools }.to raise_error(described_class::NameCollision)
    end
  end

  describe "#render_bridge_js" do
    subject(:js) do
      described_class.new(adapters: [mcb_adapter]).render_bridge_js(session_id: "sess-1")
    end

    it "embeds the session id" do
      expect(js).to include('sessionId = "sess-1"')
    end

    it "embeds the tool catalogue as JSON" do
      json_blob = js[/const tools\s+=\s+(\[.*?\]);/m, 1]
      expect(json_blob).not_to be_nil
      parsed = JSON.parse(json_blob)
      expect(parsed.map { |t| t["name"] }).to include(
        "mm.summary.substrate_summary", "mm.notes.quick_note"
      )
    end

    it "registers a capability gate for navigator.modelContext" do
      expect(js).to include('"modelContext" in navigator')
    end

    it "calls registerTool inside an AbortController.signal scope" do
      expect(js).to include("new AbortController()")
      expect(js).to include("navigator.modelContext.registerTool")
      expect(js).to include("{ signal: controller.signal }")
    end

    it "exposes window.__vvMcbWebmcp for downstream consumers" do
      expect(js).to include("window.__vvMcbWebmcp")
    end
  end
end
