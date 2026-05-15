# frozen_string_literal: true

module Tesseron
  module Ruby
    module Protocol
      # Represents a Tesseron resource: a readable, subscribable piece of app state.
      #
      # Usage (fluent builder):
      #
      #   resource = Tesseron::Ruby::Protocol::Resource.new("currentRoute")
      #     .describe("URL the user is currently viewing")
      #     .read { "/home" }
      #     .subscribe { |emit| emit.call("/home") }
      #
      class Resource
        # @return [String] the resource name (camelCase)
        attr_reader :name

        # @return [String, nil] human-readable description
        attr_reader :description

        # @return [Boolean] whether a subscribe handler has been registered
        def subscribable?
          !@subscribe_block.nil?
        end

        # @param name [String] resource name
        def initialize(name)
          @name = name.to_s
          @description = nil
          @read_block = nil
          @subscribe_block = nil
          @subscribers = []
        end

        # Set a human-readable description.
        # @param text [String]
        # @return [self]
        def describe(text)
          @description = text
          self
        end

        # Register the read handler.
        # @yieldreturn [Object] the current resource value
        # @return [self]
        def read(&block)
          @read_block = block
          self
        end

        # Register the subscribe handler.
        # The block receives an emit callable. Call emit.call(value) to push updates.
        # @yieldparam emit [Proc]
        # @return [self]
        def subscribe(&block)
          @subscribe_block = block
          self
        end

        # Read the current value of this resource.
        # @return [Object]
        def current_value
          raise ArgumentError, "No read handler registered for resource '#{@name}'" unless @read_block

          @read_block.call
        end

        # Add a subscriber callback.
        # @param callback [Proc] called with the new value whenever it changes
        def add_subscriber(callback)
          @subscribers << callback
          return unless @subscribe_block && @subscribers.size == 1

          # Start the subscription loop when the first subscriber arrives
          emit = ->(value) { notify_subscribers(value) }
          @subscribe_block.call(emit)
        end

        # Remove a subscriber callback.
        # @param callback [Proc]
        def remove_subscriber(callback)
          @subscribers.delete(callback)
        end

        # Serialise this resource to the wire format used in tesseron/hello.
        # @return [Hash]
        def to_wire
          h = { name: @name }
          h[:description] = @description if @description
          h[:subscribable] = true if subscribable?
          h
        end

        private

        def notify_subscribers(value)
          @subscribers.each { |cb| cb.call(value) }
        end
      end
    end
  end
end
