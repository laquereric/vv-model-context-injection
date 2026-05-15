# frozen_string_literal: true

require "thread"

module Tesseron
  module Ruby
    module Protocol
      # Thread-safe registry of in-flight JSON-RPC requests.
      # Each entry holds a queue that the response writer unblocks.
      class PendingRequests
        # Raised when the transport closes while a request is pending.
        class TransportClosedError < StandardError
          def initialize
            super("Transport closed while waiting for response")
          end
        end

        def initialize
          @mutex = Mutex.new
          @pending = {}
        end

        # Register a new pending request and return its response queue.
        # @param id [Integer, String] the JSON-RPC request id
        # @return [Queue] a queue that will receive exactly one Hash (result or error)
        def register(id)
          queue = Queue.new
          @mutex.synchronize { @pending[id] = queue }
          queue
        end

        # Resolve a pending request with a response payload.
        # @param id [Integer, String]
        # @param response [Hash]
        def resolve(id, response)
          queue = @mutex.synchronize { @pending.delete(id) }
          queue&.push(response)
        end

        # Reject all pending requests because the transport closed.
        def reject_all
          @mutex.synchronize do
            @pending.each_value { |q| q.push(:transport_closed) }
            @pending.clear
          end
        end

        # Block the calling thread until the response arrives, then return it.
        # Raises TransportClosedError if the transport closes first.
        #
        # @param queue [Queue] returned by #register
        # @param timeout [Numeric, nil] seconds to wait (nil = forever)
        # @return [Hash] the JSON-RPC response
        def wait(queue, timeout: nil)
          response = if timeout
            # Use a timed thread join for Ruby < 3.2 compatibility
            result = nil
            t = Thread.new { result = queue.pop }
            t.join(timeout)
            t.kill if t.alive?
            result
          else
            queue.pop
          end

          raise TransportClosedError if response == :transport_closed || response.nil?

          response
        end
      end
    end
  end
end
