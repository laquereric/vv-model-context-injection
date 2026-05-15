# frozen_string_literal: true

require "faye/websocket"
require "eventmachine"
require "json"

module Tesseron
  module Ruby
    module Client
      class WebsocketTransport
        def initialize(url)
          @url = url
          @ws = nil
          @on_message_callback = nil
          @on_close_callback = nil
          @on_error_callback = nil
        end

        def connect
          @ws = Faye::WebSocket::Client.new(@url)

          @ws.on :open do |event|
            # Connected
          end

          @ws.on :message do |event|
            begin
              message = JSON.parse(event.data, symbolize_names: true)
              @on_message_callback&.call(message)
            rescue JSON::ParserError => e
              @on_error_callback&.call(e)
            end
          end

          @ws.on :close do |event|
            @on_close_callback&.call
            @ws = nil
          end

          @ws.on :error do |event|
            @on_error_callback&.call(StandardError.new(event.message))
          end
        end

        def send_message(message)
          @ws.send(message.to_json) if @ws
        end

        def on_message(&block)
          @on_message_callback = block
        end

        def on_close(&block)
          @on_close_callback = block
        end

        def on_error(&block)
          @on_error_callback = block
        end
        
        def close
          @ws.close if @ws
        end
      end
    end
  end
end
