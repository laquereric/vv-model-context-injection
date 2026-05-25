# frozen_string_literal: true

module Vv
  module Mcb
    module Protocol
      # Represents a MCB action: a named, typed, handler-backed operation
      # that the app exposes to the agent as an MCP tool.
      #
      # Usage (fluent builder):
      #
      #   action = Vv::Mcb::Protocol::Action.new("searchProducts")
      #     .describe("Search the product catalog")
      #     .input_schema({ type: "object", properties: { query: { type: "string" } }, required: ["query"] })
      #     .output_schema({ type: "object", properties: { items: { type: "array" } } })
      #     .annotate(read_only: true, destructive: false)
      #     .timeout(ms: 30_000)
      #     .handler { |input, ctx| { items: [] } }
      #
      class Action
        # @return [String] the action name (snake_case)
        attr_reader :name

        # @return [String, nil] human-readable description for the agent LLM
        attr_reader :description

        # @return [Hash, nil] JSON Schema for input validation
        attr_reader :input_json_schema

        # @return [Hash, nil] JSON Schema for output (advisory unless strict_output? is true)
        attr_reader :output_json_schema

        # @return [Hash] annotation flags: read_only, destructive, requires_confirmation
        attr_reader :annotations

        # @return [Integer] invocation timeout in milliseconds
        attr_reader :timeout_ms

        # @return [Boolean] whether output schema is strictly enforced
        def strict_output?
          @strict_output
        end

        # @param name [String] action name
        def initialize(name)
          @name = name.to_s
          @description = nil
          @input_json_schema = nil
          @output_json_schema = nil
          @annotations = {}
          @timeout_ms = 60_000
          @strict_output = false
          @handler_block = nil
        end

        # Set a human-readable description.
        # @param text [String]
        # @return [self]
        def describe(text)
          @description = text
          self
        end

        # Set the JSON Schema for input validation.
        # @param schema [Hash]
        # @return [self]
        def input_schema(schema)
          @input_json_schema = schema
          self
        end

        # Set the JSON Schema for output (advisory by default).
        # @param schema [Hash]
        # @return [self]
        def output_schema(schema)
          @output_json_schema = schema
          self
        end

        # Set annotation flags.
        # @param flags [Hash] keys: :read_only, :destructive, :requires_confirmation
        # @return [self]
        def annotate(**flags)
          @annotations = flags
          self
        end

        # Set the invocation timeout.
        # @param ms [Integer] milliseconds
        # @return [self]
        def timeout(ms:)
          @timeout_ms = ms
          self
        end

        # Enable strict output schema enforcement.
        # @return [self]
        def strict_output!
          @strict_output = true
          self
        end

        # Attach the handler block and finalise the builder.
        # @yieldparam input [Hash] validated input
        # @yieldparam ctx [ActionContext] per-invocation context
        # @return [self]
        def handler(&block)
          @handler_block = block
          self
        end

        # Invoke the action handler with the given input and context.
        # Raises ArgumentError if no handler has been registered.
        #
        # @param input [Hash]
        # @param ctx [ActionContext]
        # @return [Object] the handler's return value
        def call(input, ctx)
          raise ArgumentError, "No handler registered for action '#{@name}'" unless @handler_block

          @handler_block.call(input, ctx)
        end

        # Serialise this action to the wire format used in mcb/hello.
        #
        # @return [Hash]
        def to_wire
          h = { name: @name }
          h[:description] = @description if @description
          h[:inputSchema] = @input_json_schema if @input_json_schema
          h[:outputSchema] = @output_json_schema if @output_json_schema
          h[:annotations] = wire_annotations unless @annotations.empty?
          h[:timeoutMs] = @timeout_ms
          h
        end

        private

        def wire_annotations
          map = {
            read_only: :readOnly,
            destructive: :destructive,
            requires_confirmation: :requiresConfirmation
          }
          @annotations.transform_keys { |k| map.fetch(k, k) }
        end
      end
    end
  end
end
