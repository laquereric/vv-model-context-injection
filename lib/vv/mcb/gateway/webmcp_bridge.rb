# frozen_string_literal: true

require "erb"
require "json"
require "set"

module Vv
  module Mcb
    module Gateway
      # Aggregates one or more in-substrate tool registries and emits a
      # per-session JS bundle that calls `navigator.modelContext.registerTool`
      # once per tool. Names are normalised to `mm.<domain>.<action>`.
      #
      # Architecture:
      #
      #   Vv::Mcb::Server::App actions ──┐
      #                                   ├──> WebmcpBridge ──> bridge.js.erb
      #   Vv::Visualize::Wamp procedures ─┘                       │
      #                                                           ▼
      #                                            browser tab `navigator.modelContext`
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
      #   bridge.render_bridge_js(session_id: session.id)
      #   # => "(function(){ ... })();"  -- inline as a <script> in the layout
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

        TEMPLATE_PATH = File.expand_path("webmcp/js/bridge.js.erb", __dir__)

        # @param adapters [Array<#each_tool>] one or more adapters yielding
        #   tool-hash entries.
        def initialize(adapters:)
          @adapters = Array(adapters)
        end

        # Render the per-session JS bridge.
        # @param session_id [String]
        # @return [String] JS source suitable for an inline <script> tag.
        def render_bridge_js(session_id:)
          tools = collect_tools
          ERB.new(File.read(TEMPLATE_PATH), trim_mode: "-").result_with_hash(
            tools_json: JSON.generate(tools),
            session_id: session_id
          )
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
