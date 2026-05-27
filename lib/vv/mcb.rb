# frozen_string_literal: true

require_relative "mcb/version"
require_relative "mcb/protocol/jsonrpc"
require_relative "mcb/protocol/action"
require_relative "mcb/protocol/action_context"
require_relative "mcb/protocol/resource"
require_relative "mcb/protocol/pending_requests"
require_relative "mcb/server/websocket_transport"
require_relative "mcb/server/app"
require_relative "mcb/client/websocket_transport"
require_relative "mcb/client/connection"
require_relative "mcb/gateway/mcp_bridge"
require_relative "mcb/gateway/webmcp_bridge"

module Vv
  # Top-level Ruby replica of the Model-Context Injection (MCB) client/server exchange protocol.
  #
  # Key entry points:
  #
  #   Vv::Mcb::Server::App           - Rack app (web-app side of the WebSocket)
  #   Vv::Mcb::Gateway::McpBridge    - MCP server that bridges to the app
  #   Vv::Mcb::Gateway::WebmcpBridge - emits in-page JS that registers the
  #                                    app's actions as WebMCP tools
  #   Vv::Mcb::Client::Connection    - MCP client for agent-side usage
  #
  module Mcb
    class Error < StandardError; end
  end
end
