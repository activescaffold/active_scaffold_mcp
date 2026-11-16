# frozen_string_literal: true

require 'active_scaffold/mcp/list_tool_filters'

module ActiveScaffold
  module MCP
    class ListToolGenerator < ToolGenerator
      extend ListToolFilters

      class << self
        def generate_tool_for(controller_class:, action_name:, action_config:, mcp_config:, settings:)
          core_config = mcp_config.core
          mappings = {}
          list_tool = build_list_tool(
            controller_class:, action_name:, action_config:, core_config:, mcp_config:, settings:, mappings:
          )

          return list_tool unless saved_views_enabled?(core_config)

          [
            list_tool,
            build_list_views_tool(
              controller_class:, action_name:, core_config:, mcp_config:, settings:, list_tool:
            )
          ]
        end

        private

        def build_list_tool(controller_class:, action_name:, action_config:, core_config:, mcp_config:, settings:,
                            mappings:)
          Class.new(ActiveScaffold::MCP::ListTool).tap do |tool_class|
            configure_tool_class(tool_class, controller_class:, action_name:, core_config:, mcp_config:, settings:)
            include_config_list(tool_class, core_config)
            tool_class.read_only
            views_tool_name = "#{tool_class.tool_name}_views" if saved_views_enabled?(core_config)
            list_views = add_list_view_property(tool_class, core_config, views_tool_name)
            add_column_filter_properties(tool_class, core_config, settings, mappings)
            add_named_filter_properties(tool_class, action_config, settings, mappings)
            add_search_property(tool_class, core_config, settings, mappings)
            sortable_columns = add_sorting_properties(tool_class, core_config, action_config)
            add_pagination_properties(tool_class, action_config)
            generated_description = description(tool_class.title, mappings, sortable_columns, action_config, list_views)
            tool_class.description(settings[:description] || generated_description)
            tool_class.mcp_param_mappings = mappings.freeze
            include_extensions(tool_class, settings)
          end
        end

        def include_config_list(tool_class, core_config)
          return unless core_config.actions.include?(:config_list)

          tool_class.include 'ActiveScaffold::Actions::ConfigList'.constantize
        end

        def description(title, mappings, sortable_columns, action_config, list_views)
          filter_types = filter_types_for(mappings)
          sentences = ["#{title} as a paginated collection"]
          sentences << "Supports #{filter_types.to_sentence}" if filter_types.any?
          search_mapping = mappings.values.find { |mapping| mapping[:source] == :search }
          sentences << search_mapping[:description] if search_mapping
          if sortable_columns.any?
            sentences << "Supports sorting by #{formatted_column_names(sortable_columns)}"
            sentences << default_sorting_description(action_config)
          end
          sentences << list_views[:description] if list_views
          sentences << 'Use limit and page for pagination'
          "#{sentences.join('. ')}."
        end

        def filter_types_for(mappings)
          sources = mappings.values.pluck(:source)
          filter_types = []
          filter_types << 'column filters' if sources.include?(nil)
          filter_types << 'named list filters' if sources.include?(:named_filter)
          filter_types << 'full-text search' if sources.include?(:search)
          filter_types
        end

        def add_list_view_property(tool_class, core_config, views_tool_name)
          return unless core_config.actions.include?(:config_list)

          config_list = core_config.config_list
          configured_names = config_list.named_views.map { |view| view.name.to_s }
          saved_views = saved_views_enabled?(core_config)
          return if configured_names.empty? && !saved_views

          sentences = ['Select a named list view to change the returned columns and default sorting']
          sentences << "Configured views: #{formatted_column_names(configured_names)}" if configured_names.any?
          if saved_views
            sentences << "Call `#{views_tool_name}` to get all views available to the current user"
          end
          description = sentences.join('. ')
          property_options = {type: 'string', description: description}
          property_options[:enum] = configured_names unless saved_views
          tool_class.property :list_view, **property_options
          {description: description}
        end

        def saved_views_enabled?(core_config)
          return false unless core_config.actions.include?(:config_list)

          config_list = core_config.config_list
          config_list.named_views_method.present? && config_list.save_to_user.present?
        end

        def build_list_views_tool(controller_class:, action_name:, core_config:, mcp_config:, settings:, list_tool:)
          Class.new(ActiveScaffold::MCP::ListViewsTool).tap do |tool_class|
            configure_tool_class(tool_class, controller_class:, action_name:, core_config:, mcp_config:, settings:)
            tool_class.tool_name("#{list_tool.tool_name}_views")
            tool_class.title("List views for #{tool_resource_label(mcp_config, settings)}")
            tool_class.description(
              "List all named views available to the current user for `#{list_tool.tool_name}`. " \
              'Pass a returned `value` to its `list_view` argument; omit `list_view` to use the default columns.'
            )
            include_config_list(tool_class, core_config)
            tool_class.read_only
            include_extensions(tool_class, settings)
          end
        end

        def add_sorting_properties(tool_class, core_config, action_config)
          columns = core_config.columns.select(&:sortable?)
          column_names = columns.map { |column| column.name.to_s }
          return [] if column_names.empty?

          description = "Column to sort by. Allowed columns: #{formatted_column_names(column_names)}. " \
                        "#{default_sorting_description(action_config)}."
          tool_class.property :sort,
                              type: 'string',
                              description: description,
                              enum: column_names
          tool_class.property :sort_direction,
                              type: 'string',
                              description: 'Sort direction used when sort is provided; defaults to asc',
                              default: 'asc',
                              enum: %w[asc desc]
          column_names
        end

        def formatted_column_names(column_names)
          column_names.map { |name| "`#{name}`" }.to_sentence
        end

        def default_sorting_description(action_config)
          sorting = action_config.sorting if action_config.respond_to?(:sorting)
          clauses = Array(sorting).map do |column, direction|
            "`#{column.name}` #{direction.to_s.upcase}"
          end
          if clauses.any?
            "When sort is omitted, the ActiveScaffold default sorting is #{clauses.to_sentence}"
          else
            'When sort is omitted, the configured ActiveScaffold default sorting is used'
          end
        end

        def add_pagination_properties(tool_class, action_config)
          configured_limit = action_config.per_page.to_i
          default_limit = if configured_limit.positive?
                            [configured_limit, ActiveScaffold::MCP::ListTool::MAX_LIMIT].min
                          else
                            ActiveScaffold::MCP::ListTool::DEFAULT_LIMIT
                          end
          tool_class.property :limit,
                              type: 'integer',
                              description: 'Maximum records to return',
                              default: default_limit,
                              minimum: 1,
                              maximum: ActiveScaffold::MCP::ListTool::MAX_LIMIT
          tool_class.property :page,
                              type: 'integer',
                              description: 'Page number',
                              default: 1,
                              minimum: 1
        end
      end
    end
  end
end
