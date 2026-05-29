# frozen_string_literal: true

require "json"
require "set"

module Vv
  module Mcb
    module Gateway
      # Aggregates one or more in-substrate tool registries into the merged,
      # normalised tool catalogue (`collect_tools`). Names are normalised to
      # `mm.<domain>.<action>`.
      #
      # PLAN_0_94_0 Phase C — the per-session bridge JS is NO LONGER server
      # rendered. The transport clients + the registration loop ship in the
      # application's STATIC bundle (`webmcp/js/bridge.js`, exporting
      # `bootWebmcp`); the session-bound tool list arrives POST-HANDSHAKE over
      # the authed carriage (the platform `GET /mcb/tools` endpoint serves
      # `collect_tools`). The retired ERB render (`tools_json` + `session_id`
      # inlined into `bridge.js.erb`) was the only server-rendered piece of the
      # application body — `render_boot_snippet` now emits a tiny static
      # `<script type="module">` that imports + calls `bootWebmcp`, carrying NO
      # tools/session (those come over the wire).
      #
      # Architecture:
      #
      #   Vv::Mcb::Server::App actions ──┐
      #                                   ├──> WebmcpBridge#collect_tools ─┐
      #   Vv::Visualize::Wamp procedures ─┘                                │
      #                                            GET /mcb/tools (authed) ─┘
      #                                                           │ post-handshake
      #                                                           ▼
      #                       STATIC bridge.js `bootWebmcp` → navigator.modelContext
      #                                            ┌────────────┴────────────┐
      #                                            ▼                         ▼
      #                                Gemini in Chrome           LanguageModel({tools})
      #
      # Adapters bind a callable surface (e.g. an MCB `Server::App`, or a
      # `Vv::Visualize::Wamp::ProcedureRegistry`) to the bridge's tool-hash
      # shape:
      #
      #   { domain:, action:, description:, input_schema:, annotations:,
      #     transport_descriptor: }
      #
      # Where `transport_descriptor` tells the in-page JS which transport
      # client to dial when the agent invokes the tool. Two are defined:
      #
      #   { kind: "mcb_ws",   url: "wss://...", method: "action.invoke" }
      #   { kind: "wamp_rpc", url: "/visualize/rpc/<name>" }
      #
      # Usage:
      #
      #   bridge = Vv::Mcb::Gateway::WebmcpBridge.new(adapters: [
      #     Vv::Mcb::Gateway::WebmcpBridge::McbAdapter.new(
      #       app: app, websocket_url: "wss://example/mcb"
      #     ),
      #     # ...
      #   ])
      #   bridge.collect_tools
      #   # => [ { name: "mm.summary.substrate_summary", transport: {...} }, ... ]
      #   # served post-handshake by the platform GET /mcb/tools endpoint;
      #   # the STATIC bridge.js `bootWebmcp` fetches + registers them.
      #
      class WebmcpBridge
        # Raised when two adapters yield tools that compose to the same
        # `mm.<domain>.<action>` URI. Surfacing this at render time is
        # cheaper than diagnosing a silent override in the browser.
        class NameCollision < StandardError; end

        # Raised when an adapter yields a tool with a missing `domain`.
        # Domains are part of the substrate's pinned URI convention; an
        # undeclared one would compose to `mm..<action>`.
        class MissingDomain < StandardError; end

        # The path the STATIC bridge module is served from at the app origin.
        # Used by `render_boot_snippet` to import `bootWebmcp`. A consumer may
        # override it if it hosts the asset elsewhere.
        DEFAULT_BRIDGE_ASSET_PATH = "/js/webmcp-bridge.js"

        # @param adapters [Array<#each_tool>] one or more adapters yielding
        #   tool-hash entries.
        def initialize(adapters:)
          @adapters = Array(adapters)
        end

        # PLAN_0_94_0 Phase C — emit the tiny static boot snippet that wires the
        # STATIC bridge module (`webmcp/js/bridge.js`) into the page. It carries
        # NO `tools_json` / `session_id`: the bundle mints a handshake + fetches
        # its session-bound tools client-side (`bootWebmcp` → POST
        # /api/v1/web_sessions → GET /mcb/tools). This REPLACES the retired ERB
        # server render — the only server-rendered piece of the app body.
        #
        # @param platform_origin [String] absolute platform base the bundle
        #   dials for the handshake + tools fetch (e.g. "https://platform.example").
        # @param asset_path [String] where the static bridge module is served.
        # @return [String] a `<script type="module">…</script>` boot snippet,
        #   inline-safe in the layout `<head>`.
        def render_boot_snippet(platform_origin:, asset_path: DEFAULT_BRIDGE_ASSET_PATH)
          <<~HTML
            <script type="module">
              import { bootWebmcp } from #{JSON.generate(asset_path)}
              bootWebmcp({ platformOrigin: #{JSON.generate(platform_origin)} })
            </script>
          HTML
        end

        # Materialise the merged + normalised tool list. Public for tests +
        # adapter authors; the in-page JS is the only normal consumer.
        # @return [Array<Hash>]
        def collect_tools
          tools = @adapters.flat_map { |a| a.each_tool.map { |t| normalize(t) } }
          detect_name_collisions!(tools)
          tools
        end

        private

        def normalize(tool)
          domain = tool[:domain]
          action = tool[:action]
          raise MissingDomain, "tool '#{action}' has no domain" if domain.nil? || domain.empty?

          {
            name:        "mm.#{domain}.#{action}",
            description: tool[:description],
            inputSchema: tool[:input_schema],
            annotations: {
              readOnlyHint:         tool.dig(:annotations, :read_only) || false,
              untrustedContentHint: tool.dig(:annotations, :untrusted_content) || false
            },
            transport: tool[:transport_descriptor]
          }
        end

        def detect_name_collisions!(tools)
          seen = Set.new
          tools.each do |t|
            raise NameCollision, "tool name collision: #{t[:name]}" unless seen.add?(t[:name])
          end
        end
      end
    end
  end
end

require_relative "webmcp_bridge/mcb_adapter"
