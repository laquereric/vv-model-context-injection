# frozen_string_literal: true

module Vv
  module Mcb
    module Gateway
      class WebmcpBridge
        # Adapts a `Vv::Mcb::Server::App` to the WebMCP bridge's tool-hash
        # shape. Yields one entry per registered action with a `transport_descriptor`
        # pointing back at the app's WebSocket so the in-page JS can dispatch
        # `action.invoke` calls against the same protocol the existing
        # `McpBridge` uses.
        class McbAdapter
          # @param app [Vv::Mcb::Server::App] the running app
          # @param websocket_url [String] the URL the in-page JS will dial
          def initialize(app:, websocket_url:)
            @app = app
            @websocket_url = websocket_url
          end

          # @yieldparam [Hash] one tool descriptor per registered action.
          # @return [Enumerator] when called without a block.
          def each_tool
            return enum_for(:each_tool) unless block_given?

            @app.actions.each do |a|
              yield(
                domain:               a.domain,
                action:               a.name,
                description:          a.description,
                input_schema:         a.input_json_schema,
                annotations:          a.annotations,
                transport_descriptor: {
                  kind:   "mcb_ws",
                  url:    @websocket_url,
                  method: "action.invoke"
                }
              )
            end
          end
        end
      end
    end
  end
end
