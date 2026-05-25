# frozen_string_literal: true

module Vv
  module Mcb
    module Protocol
      # Per-invocation context passed to action handlers.
      # Mirrors the ctx object described in the MCB Action model spec.
      class ActionContext
        # @return [String] the invocation ID assigned by the gateway
        attr_reader :invocation_id

        # @return [Hash, nil] agent identity { id:, name: }
        attr_reader :agent

        # @return [Hash] capabilities declared by the agent at handshake
        attr_reader :agent_capabilities

        # @return [Hash] client context { origin:, route:, user_agent: }
        attr_reader :client

        # @return [Boolean] whether the invocation has been cancelled
        def cancelled?
          @cancelled
        end

        # @param invocation_id [String]
        # @param agent [Hash]
        # @param agent_capabilities [Hash]
        # @param client [Hash]
        # @param progress_callback [Proc] called with (message:, percent:, data:)
        # @param sampling_callback [Proc] called with a sampling request hash
        # @param elicitation_callback [Proc] called with an elicitation request hash
        # @param log_callback [Proc] called with (level:, message:, meta:)
        def initialize(
          invocation_id:,
          agent: {},
          agent_capabilities: {},
          client: {},
          progress_callback: nil,
          sampling_callback: nil,
          elicitation_callback: nil,
          log_callback: nil
        )
          @invocation_id = invocation_id
          @agent = agent
          @agent_capabilities = agent_capabilities
          @client = client
          @progress_callback = progress_callback
          @sampling_callback = sampling_callback
          @elicitation_callback = elicitation_callback
          @log_callback = log_callback
          @cancelled = false
        end

        # Emit a streaming progress notification back to the gateway.
        # All fields are optional; send any combination.
        #
        # @param message [String, nil] human-readable status
        # @param percent [Integer, nil] 0-100
        # @param data [Hash, nil] arbitrary extra payload
        def progress(message: nil, percent: nil, data: nil)
          return if @cancelled

          @progress_callback&.call(
            invocation_id: @invocation_id,
            message: message,
            percent: percent,
            data: data
          )
        end

        # Ask the agent's LLM for a reasoning step (sampling round-trip).
        # Blocks until the gateway returns a result.
        #
        # @param messages [Array<Hash>] conversation messages
        # @param system_prompt [String, nil]
        # @param max_tokens [Integer, nil]
        # @return [Hash] the LLM response
        def sample(messages:, system_prompt: nil, max_tokens: nil)
          raise "Agent does not support sampling" unless @agent_capabilities[:sampling]

          @sampling_callback&.call(
            invocation_id: @invocation_id,
            messages: messages,
            system_prompt: system_prompt,
            max_tokens: max_tokens
          )
        end

        # Ask the user a yes/no question through the agent UI (elicitation).
        # Returns false when the client cannot prompt.
        #
        # @param question [String]
        # @return [Boolean]
        def confirm(question:)
          return false unless @agent_capabilities[:elicitation]

          result = @elicitation_callback&.call(
            invocation_id: @invocation_id,
            type: "confirm",
            question: question
          )
          result == true
        end

        # Ask the user for structured content matching a schema.
        #
        # @param message [String]
        # @param schema [Hash] JSON Schema for the expected input
        # @return [Hash] the user-provided data
        def elicit(message:, schema:)
          raise "Agent does not support elicitation" unless @agent_capabilities[:elicitation]

          @elicitation_callback&.call(
            invocation_id: @invocation_id,
            type: "elicit",
            message: message,
            schema: schema
          )
        end

        # Emit a structured log message forwarded to MCP logging.
        #
        # @param level [String] one of debug/info/notice/warning/error/critical/alert/emergency
        # @param message [String]
        # @param meta [Hash, nil]
        def log(level:, message:, meta: nil)
          @log_callback&.call(level: level, message: message, meta: meta)
        end

        # Mark this invocation as cancelled. Called by the server when it
        # receives an actions/cancel notification from the gateway.
        def cancel!
          @cancelled = true
        end
      end
    end
  end
end
