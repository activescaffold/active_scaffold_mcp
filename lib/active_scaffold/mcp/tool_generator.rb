# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class ToolGenerator
      class << self
        private

        def configure_tool_class(tool_class, controller_class:, action_name:, core_config:, mcp_config:, settings:)
          tool_class.active_scaffold_config = core_config
          tool_class.active_scaffold_controller_class = controller_class
          tool_class.mcp_action_name = action_name
          tool_class.mcp_output_column_names = settings[:columns]&.map(&:to_sym)
          tool_class.tool_name(settings[:name] || "#{action_name}_#{mcp_config.name}")
          tool_class.title("#{action_name.to_s.humanize} #{settings[:label] || mcp_config.label}")
        end

        def include_extensions(tool_class, settings)
          Array(settings[:modules]).each { |extension| tool_class.include extension }
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
