# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class ToolGenerator
      class << self
        private

        def configure_tool_class(tool_class, controller_class:, action_name:, core_config:, mcp_config:, settings:)
          tool_class.active_scaffold_config = core_config
          # Finder is included by the base MCP tool before a controller's
          # ActiveScaffold config is known. Re-extending its class methods now
          # lets Finder select the configured persistence adapter (and provide
          # adapter-specific helpers such as like_pattern).
          tool_class.extend ActiveScaffold::Finder::ClassMethods
          tool_class.active_scaffold_controller_class = controller_class
          tool_class.mcp_action_name = action_name
          tool_class.mcp_output_column_names = settings[:columns]&.map(&:to_sym)
          tool_class.tool_name(settings[:name] || default_tool_name(action_name, mcp_config))
          tool_class.title("#{action_name.to_s.humanize} #{tool_resource_label(mcp_config, settings)}")
        end

        def default_tool_name(action_name, mcp_config)
          "#{action_name}_#{tool_resource_name(mcp_config)}"
        end

        def tool_resource_name(mcp_config)
          mcp_config.name
        end

        def tool_resource_label(mcp_config, settings)
          settings[:label] || mcp_config.label
        end

        def include_extensions(tool_class, settings)
          Array(settings[:modules]).each { |extension| tool_class.include extension }
        end

        def singular_label(mcp_config)
          mcp_config.label.to_s.singularize
        end

        def schema_options(column)
          options = {type: json_type(column)}
          format = json_format(column)
          options[:format] = format if format
          options
        end

        def json_type(column)
          case column&.type&.to_sym
          when :integer, :bigint
            "integer"
          when :float, :decimal
            "number"
          when :boolean
            "boolean"
          else
            "string"
          end
        end

        def json_format(column)
          case column&.type&.to_sym
          when :date
            "date"
          when :datetime, :timestamp, :timestamptz
            "date-time"
          end
        end
      end
    end
  end
end
