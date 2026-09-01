# frozen_string_literal: true

module ActiveScaffold
  module Actions
    module MCP
      def self.included(base)
        ActiveScaffold::MCP.generate_tools_for(
          base,
          base.active_scaffold_config.mcp
        )
      end
    end
  end
end
