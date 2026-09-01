# frozen_string_literal: true

module ActiveScaffold
  module MCP
    module FilteredTools
      def filtered_tools
        super.select do |entry|
          tool_class = entry.klass
          !tool_class.respond_to?(:tool_authorized?) || tool_class.tool_authorized?
        end
      end
    end
  end
end

unless ActionMCP::Configuration.ancestors.include?(ActiveScaffold::MCP::FilteredTools)
  ActionMCP::Configuration.prepend(ActiveScaffold::MCP::FilteredTools)
end
