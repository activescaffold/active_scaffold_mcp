# frozen_string_literal: true

require "active_scaffold/mcp/filtered_tools"

module ActiveScaffold
  module Actions
    autoload :MCP, "active_scaffold/actions/mcp"
  end

  module Config
    autoload :MCP, "active_scaffold/config/mcp"
  end

  module MCP
    autoload :ActionConfig, "active_scaffold/mcp/action_config"
    autoload :Flash, "active_scaffold/mcp/flash"
    autoload :GeneratorFactory, "active_scaffold/mcp/generator_factory"
    autoload :ListToolGenerator, "active_scaffold/mcp/list_tool_generator"
    autoload :ProfileUser, "active_scaffold/mcp/profile_user"
    autoload :SettingsValidator, "active_scaffold/mcp/settings_validator"
    autoload :Tool, "active_scaffold/mcp/tool"
    autoload :ToolGenerator, "active_scaffold/mcp/tool_generator"
    autoload :ListTool, "active_scaffold/mcp/list_tool"
    autoload :ShowTool, "active_scaffold/mcp/show_tool"
    autoload :ShowToolGenerator, "active_scaffold/mcp/show_tool_generator"
    autoload :VERSION, "active_scaffold/mcp/version"

    class << self
      def generate_tools_for(controller_class, action_config)
        generator = ActiveScaffold::Config::MCP.tool_generator
        return [] unless generator

        generator.generate_tools_for(controller_class, action_config)
      end
    end
  end
end
