# frozen_string_literal: true

require_relative "ruby/version"
require_relative "ruby/protocol/jsonrpc"
require_relative "ruby/protocol/action"
require_relative "ruby/protocol/action_context"
require_relative "ruby/protocol/resource"
require_relative "ruby/protocol/pending_requests"
require_relative "ruby/server/websocket_transport"
require_relative "ruby/server/app"
require_relative "ruby/client/websocket_transport"
require_relative "ruby/client/connection"
require_relative "ruby/gateway/mcp_bridge"

module Tesseron
  # Top-level Ruby replica of the Tesseron client/server exchange protocol.
  #
  # Key entry points:
  #
  #   Tesseron::Ruby::Server::App    - Rack app (web-app side of the WebSocket)
  #   Tesseron::Ruby::Gateway::McpBridge - MCP server that bridges to the app
  #   Tesseron::Ruby::Client::Connection - MCP client for agent-side usage
  #
  module Ruby
    class Error < StandardError; end
  end
end
