# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class Flash < ActiveSupport::HashWithIndifferentAccess
      def messages
        values.flatten.compact
      end
    end
  end
end
