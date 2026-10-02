# frozen_string_literal: true

require "active_scaffold/mcp/filtered_tools"
require "set"

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
    autoload :ListViewsTool, "active_scaffold/mcp/list_views_tool"
    autoload :ShowToolGenerator, "active_scaffold/mcp/show_tool_generator"
    autoload :VERSION, "active_scaffold/mcp/version"

    class << self
      def generated_controller_names
        @generated_controller_names ||= Set.new
      end

      def generated_tool_classes
        @generated_tool_classes ||= Set.new
      end

      def generate_tools_for(controller_class, action_config)
        generator = ActiveScaffold::Config::MCP.tool_generator
        return [] unless generator

        generated_controller_names << controller_class.name if controller_class.name.present?
        generator.generate_tools_for(controller_class, action_config).tap do |tools|
          generated_tool_classes.merge(Array(tools).compact)
        end
      end

      def reload_generated_tools!
        controller_classes = generated_controller_names.filter_map(&:safe_constantize)
        stale_tool_classes = generated_tool_classes.dup
        ActionMCP::ToolsRegistry.items.delete_if { |_name, tool_class| stale_tool_classes.include?(tool_class) }
        generated_tool_classes.clear
        controller_classes.each do |controller_class|
          generate_tools_for(controller_class, controller_class.active_scaffold_config.mcp)
        end
      end
    end
  end
end
