# frozen_string_literal: true

module Vv
  module Mcb
    module Protocol
      # MCB protocol version
      PROTOCOL_VERSION = "1.1.0"

      # JSON-RPC 2.0 error codes used by the MCB protocol
      module ErrorCodes
        PARSE_ERROR       = -32_700
        INVALID_REQUEST   = -32_600
        METHOD_NOT_FOUND  = -32_601
        INVALID_PARAMS    = -32_602
        INTERNAL_ERROR    = -32_603

        # MCB-specific codes
        PROTOCOL_MISMATCH = -32_000
        CANCELLED         = -32_001
        TIMEOUT           = -32_002
        NOT_FOUND         = -32_003
        INPUT_VALIDATION  = -32_004
        HANDLER_ERROR     = -32_005
      end

      # Builds a JSON-RPC 2.0 request envelope
      #
      # @param id [Integer, String] unique request identifier
      # @param method [String] the method name
      # @param params [Hash] method parameters
      # @return [Hash] JSON-RPC request object
      def self.request(id:, method:, params: nil)
        msg = { jsonrpc: "2.0", id: id, method: method }
        msg[:params] = params if params
        msg
      end

      # Builds a JSON-RPC 2.0 notification envelope (no id, no response expected)
      #
      # @param method [String] the method name
      # @param params [Hash] method parameters
      # @return [Hash] JSON-RPC notification object
      def self.notification(method:, params: nil)
        msg = { jsonrpc: "2.0", method: method }
        msg[:params] = params if params
        msg
      end

      # Builds a JSON-RPC 2.0 success response
      #
      # @param id [Integer, String] echoed request identifier
      # @param result [Object] the result payload
      # @return [Hash] JSON-RPC success response
      def self.success_response(id:, result:)
        { jsonrpc: "2.0", id: id, result: result }
      end

      # Builds a JSON-RPC 2.0 error response
      #
      # @param id [Integer, String] echoed request identifier
      # @param code [Integer] error code
      # @param message [String] human-readable error message
      # @param data [Object, nil] optional additional error data
      # @return [Hash] JSON-RPC error response
      def self.error_response(id:, code:, message:, data: nil)
        error = { code: code, message: message }
        error[:data] = data if data
        { jsonrpc: "2.0", id: id, error: error }
      end
    end
  end
end
