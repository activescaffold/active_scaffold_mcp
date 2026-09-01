# frozen_string_literal: true

require "active_scaffold/mcp/action_config"
require "active_scaffold/mcp/filtered_tools"
require "active_scaffold/mcp/flash"
require "active_scaffold/mcp/profile_user"
require "active_scaffold/mcp/version"

module ActiveScaffold
  module MCP
    autoload :Tool, "active_scaffold/mcp/tool"
    autoload :ListTool, "active_scaffold/mcp/list_tool"

    class << self
      def generate_tools_for(controller_class, action_config)
        generator = ActiveScaffold::Config::MCP.tool_generator
        return [] unless generator

        generator.generate_tools_for(controller_class, action_config)
      end
    end
  end
end

require "active_scaffold/mcp/list_tool_generator"
require "active_scaffold/mcp/generator_factory"
require "active_scaffold/mcp/settings_validator"

require "active_scaffold/config/mcp"
require "active_scaffold/actions/mcp"
