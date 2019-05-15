module ZuoraConnect
  module Exceptions

    class HoldingPattern < StandardError; end
    class Error < StandardError; end
    class AuthorizationNotPerformed < Error; end

    class SessionInvalid < Error
      attr_writer :default_message

      def initialize(message = nil)
        @message = message
        @default_message = "Session data invalid."
      end

      def to_s
        @message || @default_message
      end
    end

    class ConnectCommunicationError < Error
      attr_reader :code, :response
      attr_writer :default_message

      def initialize(message = nil,response=nil, code =nil)
        @code = code
        @message = message
        @response = response
        @default_message = "Error communication with Connect."
      end

      def to_s
        @message || @default_message
      end
    end

    class APIError < Error
      attr_reader :code, :response
      attr_writer :default_message

      def initialize(message: nil,response: nil, code: nil)
        @code = code
        @message = message
        @response = response
        @default_message = "Connect update error."
      end

      def to_s
        @message || @default_message
      end

    end

    class AccessDenied < Error
      attr_writer :default_message

      def initialize(message = nil)
        @message = message
        @default_message = "You are not authorized to access this page."
      end

      def to_s
        @message || @default_message
      end
    end
  end
end
