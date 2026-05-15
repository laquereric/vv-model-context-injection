# frozen_string_literal: true

require "mcp"
require_relative "websocket_transport"

module Tesseron
  module Ruby
    module Client
      # High-level MCP client that connects to a Tesseron MCP gateway using
      # the `mcp` gem's stdio transport.
      #
      # This is the agent-side client. It wraps MCP::Client to provide a
      # Tesseron-flavoured API for listing and calling actions (MCP tools)
      # and reading resources.
      #
      # Usage:
      #
      #   connection = Tesseron::Ruby::Client::Connection.new(
      #     command: "npx",
      #     args: ["-y", "@tesseron/mcp"]   # or your Ruby gateway binary
      #   )
      #   connection.connect
      #
      #   # List available actions
      #   connection.actions.each { |a| puts a.name }
      #
      #   # Invoke an action
      #   result = connection.invoke("shop__searchProducts", query: "ruby gems")
      #   puts result
      #
      #   connection.close
      #
      class Connection
        # @return [MCP::Client] the underlying MCP client
        attr_reader :mcp_client

        # @param command [String] command to spawn the gateway process
        # @param args [Array<String>] arguments for the gateway command
        # @param env [Hash, nil] environment variables for the gateway process
        # @param read_timeout [Numeric, nil] seconds to wait for responses
        def initialize(command:, args: [], env: nil, read_timeout: 60)
          @command = command
          @args = args
          @env = env
          @read_timeout = read_timeout
          @mcp_client = nil
        end

        # Establish the connection and perform the MCP initialization handshake.
        def connect
          transport = MCP::Client::Stdio.new(
            command: @command,
            args: @args,
            env: @env,
            read_timeout: @read_timeout
          )
          @mcp_client = MCP::Client.new(transport: transport)
          @mcp_client.connect
          self
        end

        # Return all available actions (MCP tools) on the connected gateway.
        # @return [Array<MCP::Client::Tool>]
        def actions
          @mcp_client.tools
        end

        # Invoke a Tesseron action by its MCP tool name.
        # The tool name follows the <app_id>__<action_name> convention.
        #
        # @param tool_name [String] e.g. "shop__searchProducts"
        # @param input [Hash] action input arguments
        # @return [String] the text result from the action
        def invoke(tool_name, **input)
          response = @mcp_client.call_tool(tool_name, input)
          # Extract text content from the MCP tool response
          content = response[:content] || []
          text_parts = content.select { |c| c[:type] == "text" }.map { |c| c[:text] }
          text_parts.join("\n")
        end

        # Read a Tesseron resource by its URI.
        # @param uri [String] e.g. "tesseron://shop/currentRoute"
        # @return [Array<Hash>] resource contents
        def read_resource(uri)
          @mcp_client.read_resource(uri)
        end

        # List all resources available on the gateway.
        # @return [Array<MCP::Client::Resource>]
        def resources
          @mcp_client.resources
        end

        # Check connectivity with a ping.
        # @return [Hash] empty hash on success
        def ping
          @mcp_client.ping
        end

        # Close the connection.
        def close
          # MCP::Client does not expose an explicit close; the transport
          # process will be cleaned up when the object is garbage-collected.
          @mcp_client = nil
        end
      end
    end
  end
end
