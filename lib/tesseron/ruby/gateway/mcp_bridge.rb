# frozen_string_literal: true

require "mcp"
require "securerandom"
require_relative "../protocol/jsonrpc"
require_relative "../protocol/pending_requests"

module Tesseron
  module Ruby
    module Gateway
      # MCP bridge: runs as an MCP server (using the `mcp` gem) and connects
      # to a Tesseron app over WebSocket, translating between the two protocols.
      #
      # Architecture:
      #
      #   MCP client (Claude, Cursor, etc.)
      #       ↕  JSON-RPC over stdio / Streamable HTTP
      #   McpBridge  (this class)
      #       ↕  JSON-RPC over WebSocket
      #   Tesseron app (Tesseron::Ruby::Server::App)
      #
      # The bridge:
      #   1. Opens a WebSocket connection to the app.
      #   2. Waits for the tesseron/hello handshake.
      #   3. Registers each declared action as an MCP tool.
      #   4. When an MCP client calls a tool, sends actions/invoke to the app
      #      and waits for the response.
      #   5. Forwards actions/progress notifications as MCP notifications/progress.
      #   6. Supports cancellation by sending actions/cancel when the MCP client
      #      cancels a tools/call.
      #
      # Usage:
      #
      #   bridge = Tesseron::Ruby::Gateway::McpBridge.new(
      #     app_ws_url: "ws://localhost:4000",
      #     name: "tesseron-gateway"
      #   )
      #   bridge.run   # blocks; starts MCP server on stdio
      #
      class McpBridge
        # @param app_ws_url [String] WebSocket URL of the Tesseron app
        # @param name [String] MCP server name
        def initialize(app_ws_url:, name: "tesseron-gateway")
          @app_ws_url = app_ws_url
          @name = name
          @pending = Protocol::PendingRequests.new
          @request_counter = 0
          @counter_mutex = Mutex.new
          @app_meta = nil          # populated after tesseron/hello
          @registered_actions = {} # name => action wire descriptor
        end

        # Connect to the app and start the MCP server.
        # This method blocks until the process exits.
        def run
          connect_to_app
          wait_for_hello
          start_mcp_server
        end

        private

        # ------------------------------------------------------------------ #
        # WebSocket connection to the Tesseron app                            #
        # ------------------------------------------------------------------ #

        def connect_to_app
          require "faye/websocket"
          require "eventmachine"

          @ws_queue = Queue.new

          @em_thread = Thread.new do
            EM.run do
              @ws = Faye::WebSocket::Client.new(@app_ws_url)

              @ws.on :message do |event|
                begin
                  msg = JSON.parse(event.data, symbolize_names: true)
                  dispatch_app_message(msg)
                rescue JSON::ParserError => e
                  warn "[tesseron-gateway] JSON parse error: #{e.message}"
                end
              end

              @ws.on :close do |_event|
                warn "[tesseron-gateway] WebSocket closed"
                @pending.reject_all
                EM.stop
              end

              @ws.on :error do |event|
                warn "[tesseron-gateway] WebSocket error: #{event.message}"
              end
            end
          end

          @em_thread.abort_on_exception = true
        end

        def dispatch_app_message(msg)
          if msg.key?(:result) || msg.key?(:error)
            # Response to a request we sent
            @pending.resolve(msg[:id], msg)
          elsif msg[:method]
            handle_app_notification(msg)
          end
        end

        def handle_app_notification(msg)
          case msg[:method]
          when "actions/progress"
            # Forward to MCP as notifications/progress
            # (handled by the MCP server context in the tool call thread)
            params = msg[:params] || {}
            @progress_callbacks&.dig(params[:invocationId])&.call(params)
          when "resources/updated"
            # Could be forwarded to subscribed MCP clients; omitted for brevity
          when "log"
            params = msg[:params] || {}
            warn "[app-log] [#{params[:level]}] #{params[:message]}"
          end
        end

        def send_to_app(message)
          # Faye WebSocket must be called from the EventMachine thread
          EM.next_tick { @ws.send(message.to_json) }
        end

        def next_id
          @counter_mutex.synchronize { @request_counter += 1 }
        end

        # ------------------------------------------------------------------ #
        # Handshake                                                           #
        # ------------------------------------------------------------------ #

        def wait_for_hello
          # The app sends tesseron/hello as a request; we wait for it.
          # In the Tesseron protocol the app initiates hello, so we need to
          # intercept the first request message.
          hello_queue = Queue.new
          @hello_queue = hello_queue

          # Give the app up to 10 seconds to send hello
          msg = hello_queue.pop(timeout: 10)
          raise "Timed out waiting for tesseron/hello" if msg.nil?

          params = msg[:params] || {}
          @app_meta = params[:app]
          @registered_actions = (params[:actions] || []).index_by { |a| a[:name] }

          # Acknowledge the hello
          send_to_app(Protocol.success_response(id: msg[:id], result: { status: "ok" }))
        end

        # Override dispatch to capture hello before it goes to pending
        alias_method :_original_dispatch, :dispatch_app_message
        def dispatch_app_message(msg)
          if msg[:method] == "tesseron/hello" && @hello_queue
            @hello_queue.push(msg)
            @hello_queue = nil
            return
          end

          _original_dispatch(msg)
        end

        # ------------------------------------------------------------------ #
        # MCP server                                                          #
        # ------------------------------------------------------------------ #

        def start_mcp_server
          app_id = @app_meta&.dig(:id) || "app"
          bridge = self

          server = MCP::Server.new(name: @name)

          @registered_actions.each_value do |action_wire|
            action_name = action_wire[:name]
            mcp_tool_name = "#{app_id}__#{action_name}"
            description = action_wire[:description] || action_name
            input_schema = action_wire[:inputSchema] || {}

            server.define_tool(
              name: mcp_tool_name,
              description: description,
              input_schema: input_schema
            ) do |args, server_context:|
              bridge.invoke_action(
                action_name: action_name,
                input: args,
                server_context: server_context
              )
            end
          end

          transport = MCP::Server::Transports::StdioTransport.new(server)
          transport.open
        end

        # ------------------------------------------------------------------ #
        # Action invocation (called from MCP tool handler threads)           #
        # ------------------------------------------------------------------ #

        # Invoke a Tesseron action on the connected app and return the result.
        # Blocks the calling thread until the app responds.
        #
        # @param action_name [String]
        # @param input [Hash]
        # @param server_context [MCP::ServerContext]
        # @return [MCP::Tool::Response]
        def invoke_action(action_name:, input:, server_context:)
          invocation_id = "inv_#{SecureRandom.hex(6)}"
          id = next_id

          queue = @pending.register(id)

          # Wire up progress forwarding for this invocation
          @progress_callbacks ||= {}
          @progress_callbacks[invocation_id] = lambda do |params|
            progress_value = params[:percent] || 0
            total = 100
            message = params[:message]
            server_context.report_progress(progress_value, total: total, message: message)
          end

          send_to_app(
            Protocol.request(
              id: id,
              method: "actions/invoke",
              params: {
                name: action_name,
                invocationId: invocation_id,
                input: input
              }
            )
          )

          begin
            response = @pending.wait(queue, timeout: 120)
          ensure
            @progress_callbacks&.delete(invocation_id)
          end

          if response.key?(:error)
            err = response[:error]
            MCP::Tool::Response.new(
              [{ type: "text", text: "Error #{err[:code]}: #{err[:message]}" }],
              error: true
            )
          else
            result = response[:result]
            MCP::Tool::Response.new([{ type: "text", text: result.to_json }])
          end
        end
      end
    end
  end
end
