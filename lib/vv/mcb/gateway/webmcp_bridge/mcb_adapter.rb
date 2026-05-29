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
          # @param token [String, nil] the short-TTL handshake token the
          #   in-page dial-back presents so the platform can authenticate +
          #   bind the WS to the agent's Mcb::Session (magentic-market-ai
          #   PLAN_0_94_0 Phase B). Omitted from the descriptor when nil so
          #   the same-origin/desktop bridge stays usable token-free.
          # @param origin [String, nil] the app origin the dial-back is
          #   pinned to (origin-pinned resolve). Omitted when nil.
          def initialize(app:, websocket_url:, token: nil, origin: nil)
            @app = app
            @websocket_url = websocket_url
            @token = token
            @origin = origin
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
                transport_descriptor: transport_descriptor
              )
            end
          end

          private

          # The mcb_ws descriptor. `token` + `origin` keys are included only
          # when present (nil ⇒ omitted) so a token-free, same-origin/desktop
          # dial-back stays back-compatible (PLAN_0_94_0 Phase B).
          def transport_descriptor
            descriptor = {
              kind:   "mcb_ws",
              url:    @websocket_url,
              method: "action.invoke"
            }
            descriptor[:token]  = @token  unless @token.nil?
            descriptor[:origin] = @origin unless @origin.nil?
            descriptor
          end
        end
      end
    end
  end
end
