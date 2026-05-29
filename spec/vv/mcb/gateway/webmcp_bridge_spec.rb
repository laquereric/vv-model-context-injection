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

    context "with a token + origin (PLAN_0_94_0 Phase B)" do
      let(:authed_adapter) do
        Vv::Mcb::Gateway::WebmcpBridge::McbAdapter.new(
          app: app, websocket_url: "wss://example.test/mcb",
          token: "whs_abc", origin: "https://app.example"
        )
      end

      subject(:tools) { described_class.new(adapters: [authed_adapter]).collect_tools }

      it "includes the token + origin in every mcb_ws descriptor" do
        tools.each do |t|
          expect(t[:transport]).to eq(
            kind: "mcb_ws", url: "wss://example.test/mcb", method: "action.invoke",
            token: "whs_abc", origin: "https://app.example"
          )
        end
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

  # PLAN_0_94_0 Phase C — the per-session JS bridge is no longer server
  # rendered. `render_boot_snippet` emits a tiny static <script type="module">
  # that imports + calls `bootWebmcp` against the static bridge asset; it
  # carries NO inlined tools / session id (those arrive post-handshake).
  describe "#render_boot_snippet" do
    subject(:snippet) do
      described_class.new(adapters: [mcb_adapter])
        .render_boot_snippet(platform_origin: "https://platform.example")
    end

    it "emits a module <script> that imports bootWebmcp" do
      expect(snippet).to include('<script type="module">')
      expect(snippet).to match(/import \{ bootWebmcp \} from/)
    end

    it "imports from the default static bridge asset path" do
      expect(snippet).to include('"/js/webmcp-bridge.js"')
    end

    it "calls bootWebmcp with the platform origin" do
      expect(snippet).to include('bootWebmcp({ platformOrigin: "https://platform.example" })')
    end

    it "honours an explicit asset_path override" do
      out = described_class.new(adapters: [mcb_adapter]).render_boot_snippet(
        platform_origin: "https://platform.example", asset_path: "/assets/wmb.js"
      )
      expect(out).to include('"/assets/wmb.js"')
    end

    it "does NOT inline a server-rendered tool list (Phase C invariant)" do
      expect(snippet).not_to include("const tools")
      expect(snippet).not_to include("mm.summary.substrate_summary")
    end

    it "does NOT inline a session id" do
      expect(snippet).not_to match(/sessionId\s*=/)
    end

    it "no longer renders the retired bridge.js.erb (no transport-class source)" do
      expect(snippet).not_to include("navigator.modelContext.registerTool")
      expect(snippet).not_to include("new AbortController()")
    end
  end
end
