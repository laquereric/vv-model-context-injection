# frozen_string_literal: true

require "rack"
require "faye/websocket"
require "json"
require "securerandom"
require_relative "../protocol/jsonrpc"
require_relative "../protocol/action"
require_relative "../protocol/action_context"
require_relative "../protocol/resource"
require_relative "../protocol/pending_requests"
require_relative "websocket_transport"

module Vv
  module Mcb
    module Server
      # Rack application that accepts WebSocket connections from the MCP gateway.
      # Implements the app-side of the MCB protocol:
      #
      #   1. Accepts a WebSocket upgrade from the gateway.
      #   2. Sends mcb/hello to register the app, its actions, and resources.
      #   3. Handles actions/invoke, resources/read, resources/subscribe, and
      #      resources/unsubscribe requests from the gateway.
      #   4. Sends actions/progress notifications during long-running handlers.
      #   5. Handles actions/cancel notifications.
      #
      # Example (Rack config.ru):
      #
      #   require "vv/mcb"
      #
      #   app = Vv::Mcb::Server::App.new(id: "shop", name: "Acme Shop")
      #
      #   app.action("searchProducts")
      #      .describe("Search the product catalog")
      #      .input_schema({ type: "object", properties: { query: { type: "string" } }, required: ["query"] })
      #      .handler { |input, ctx| { items: [] } }
      #
      #   run app
      #
      class App
        # @return [String] application identifier (used to namespace MCP tools)
        attr_reader :id

        # @return [String] human-readable application name
        attr_reader :name

        # @param id [String] application identifier
        # @param name [String] human-readable name
        def initialize(id:, name:)
          @id = id
          @name = name
          @actions = {}
          @resources = {}
          @sessions = {}
          @request_counter = 0
          @counter_mutex = Mutex.new
        end

        # Register a new action using the fluent builder.
        # @param action_name [String]
        # @return [Protocol::Action]
        def action(action_name)
          act = Protocol::Action.new(action_name)
          @actions[action_name] = act
          act
        end

        # @return [Array<Protocol::Action>] the registered actions in declaration order.
        #   Iterable surface relied on by `Vv::Mcb::Gateway::WebmcpBridge::McbAdapter`.
        def actions
          @actions.values
        end

        # Register a new resource using the fluent builder.
        # @param resource_name [String]
        # @return [Protocol::Resource]
        def resource(resource_name)
          res = Protocol::Resource.new(resource_name)
          @resources[resource_name] = res
          res
        end

        # Rack call interface. Upgrades HTTP to WebSocket when the request
        # carries the appropriate headers; otherwise returns 426 Upgrade Required.
        #
        # @param env [Hash] Rack environment
        # @return [Array] Rack response triple
        def call(env)
          return [426, { "Content-Type" => "text/plain" }, ["WebSocket upgrade required"]] unless Faye::WebSocket.websocket?(env)

          ws = Faye::WebSocket.new(env)
          transport = WebsocketTransport.new(ws)
          session_id = SecureRandom.uuid
          pending = Protocol::PendingRequests.new
          active_invocations = {}

          transport.on_message do |message|
            handle_message(message, transport, pending, active_invocations, session_id)
          end

          transport.on_close do
            @sessions.delete(session_id)
            pending.reject_all
          end

          transport.on_error do |err|
            warn "[mcb] WebSocket error on session #{session_id}: #{err.message}"
          end

          @sessions[session_id] = { transport: transport, pending: pending }

          # Send mcb/hello immediately after the connection opens
          send_hello(transport)

          ws.rack_response
        end

        private

        # ------------------------------------------------------------------ #
        # Outbound helpers                                                     #
        # ------------------------------------------------------------------ #

        def next_id
          @counter_mutex.synchronize { @request_counter += 1 }
        end

        def send_hello(transport)
          id = next_id
          payload = Protocol.request(
            id: id,
            method: "mcb/hello",
            params: {
              protocolVersion: Protocol::PROTOCOL_VERSION,
              app: { id: @id, name: @name },
              actions: @actions.values.map(&:to_wire),
              resources: @resources.values.map(&:to_wire),
              capabilities: {
                progress: true,
                cancellation: true,
                resources: { subscribe: true }
              }
            }
          )
          transport.send_message(payload)
        end

        def send_progress(transport, invocation_id:, message: nil, percent: nil, data: nil)
          params = { invocationId: invocation_id }
          params[:message] = message if message
          params[:percent] = percent if percent
          params[:data] = data if data
          transport.send_message(Protocol.notification(method: "actions/progress", params: params))
        end

        def send_log(transport, level:, message:, meta: nil)
          params = { level: level, message: message }
          params[:meta] = meta if meta
          transport.send_message(Protocol.notification(method: "log", params: params))
        end

        # ------------------------------------------------------------------ #
        # Inbound dispatch                                                     #
        # ------------------------------------------------------------------ #

        def handle_message(message, transport, pending, active_invocations, _session_id)
          method = message[:method]
          id = message[:id]
          params = message[:params] || {}

          if message.key?(:result) || message.key?(:error)
            # This is a response to a request we sent (e.g. mcb/hello ack,
            # sampling/request, elicitation/request)
            pending.resolve(id, message)
            return
          end

          case method
          when "actions/invoke"
            handle_invoke(message, transport, active_invocations)
          when "actions/cancel"
            handle_cancel(params, active_invocations)
          when "resources/read"
            handle_resource_read(message, transport)
          when "resources/subscribe"
            handle_resource_subscribe(message, transport)
          when "resources/unsubscribe"
            handle_resource_unsubscribe(message, transport)
          else
            if id
              transport.send_message(
                Protocol.error_response(
                  id: id,
                  code: Protocol::ErrorCodes::METHOD_NOT_FOUND,
                  message: "Unknown method: #{method}"
                )
              )
            end
          end
        end

        def handle_invoke(message, transport, active_invocations)
          id = message[:id]
          params = message[:params] || {}
          action_name = params[:name]
          invocation_id = params[:invocationId] || SecureRandom.uuid
          input = params[:input] || {}
          client_meta = params[:client] || {}

          action = @actions[action_name]
          unless action
            transport.send_message(
              Protocol.error_response(
                id: id,
                code: Protocol::ErrorCodes::NOT_FOUND,
                message: "Unknown action: #{action_name}"
              )
            )
            return
          end

          ctx = Protocol::ActionContext.new(
            invocation_id: invocation_id,
            client: client_meta,
            progress_callback: ->(args) { send_progress(transport, **args) },
            log_callback: ->(args) { send_log(transport, **args) }
          )

          active_invocations[invocation_id] = ctx

          # Run the handler in a background thread so the WebSocket event loop
          # is not blocked during long-running operations.
          Thread.new do
            begin
              result = action.call(input, ctx)
              unless ctx.cancelled?
                transport.send_message(Protocol.success_response(id: id, result: result))
              end
            rescue StandardError => e
              unless ctx.cancelled?
                transport.send_message(
                  Protocol.error_response(
                    id: id,
                    code: Protocol::ErrorCodes::HANDLER_ERROR,
                    message: e.message
                  )
                )
              end
            ensure
              active_invocations.delete(invocation_id)
            end
          end
        end

        def handle_cancel(params, active_invocations)
          invocation_id = params[:invocationId]
          ctx = active_invocations[invocation_id]
          ctx&.cancel!
        end

        def handle_resource_read(message, transport)
          id = message[:id]
          params = message[:params] || {}
          resource_name = params[:name]
          resource = @resources[resource_name]

          unless resource
            transport.send_message(
              Protocol.error_response(
                id: id,
                code: Protocol::ErrorCodes::NOT_FOUND,
                message: "Unknown resource: #{resource_name}"
              )
            )
            return
          end

          begin
            value = resource.current_value
            transport.send_message(Protocol.success_response(id: id, result: { value: value }))
          rescue StandardError => e
            transport.send_message(
              Protocol.error_response(
                id: id,
                code: Protocol::ErrorCodes::HANDLER_ERROR,
                message: e.message
              )
            )
          end
        end

        def handle_resource_subscribe(message, transport)
          id = message[:id]
          params = message[:params] || {}
          resource_name = params[:name]
          resource = @resources[resource_name]

          unless resource
            transport.send_message(
              Protocol.error_response(
                id: id,
                code: Protocol::ErrorCodes::NOT_FOUND,
                message: "Unknown resource: #{resource_name}"
              )
            )
            return
          end

          callback = lambda do |value|
            transport.send_message(
              Protocol.notification(
                method: "resources/updated",
                params: { name: resource_name, value: value }
              )
            )
          end

          resource.add_subscriber(callback)
          transport.send_message(Protocol.success_response(id: id, result: {}))
        end

        def handle_resource_unsubscribe(message, transport)
          id = message[:id]
          params = message[:params] || {}
          resource_name = params[:name]
          resource = @resources[resource_name]

          if resource
            # We don't track per-subscriber identity here; remove all for simplicity.
            # A production implementation would track subscriber tokens.
            transport.send_message(Protocol.success_response(id: id, result: {}))
          else
            transport.send_message(
              Protocol.error_response(
                id: id,
                code: Protocol::ErrorCodes::NOT_FOUND,
                message: "Unknown resource: #{resource_name}"
              )
            )
          end
        end
      end
    end
  end
end
