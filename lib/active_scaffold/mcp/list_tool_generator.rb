# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class ListToolGenerator < ToolGenerator
      OPERATOR_ALIASES = {
        eq: :equal,
        equality: :equal,
        range: :between,
        not_eq: :not_equal,
        neq: :not_equal,
        not_range: :not_between
      }.freeze

      class << self
        def generate_tool_for(controller_class:, action_name:, action_config:, mcp_config:, settings:)
          core_config = mcp_config.core
          mappings = {}

          list_tool = Class.new(ActiveScaffold::MCP::ListTool).tap do |tool_class|
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

          return list_tool unless saved_views_enabled?(core_config)

          [
            list_tool,
            build_list_views_tool(
              controller_class:, action_name:, core_config:, mcp_config:, settings:, list_tool:
            )
          ]
        end

        private

        def include_config_list(tool_class, core_config)
          return unless core_config.actions.include?(:config_list)

          tool_class.include "ActiveScaffold::Actions::ConfigList".constantize
        end

        def description(title, mappings, sortable_columns, action_config, list_views)
          filter_types = []
          filter_types << "column filters" if mappings.any? { |_name, mapping| mapping[:source].nil? }
          filter_types << "named list filters" if mappings.any? { |_name, mapping| mapping[:source] == :named_filter }
          filter_types << "full-text search" if mappings.any? { |_name, mapping| mapping[:source] == :search }

          sentences = ["#{title} as a paginated collection"]
          sentences << "Supports #{filter_types.to_sentence}" if filter_types.any?
          search_mapping = mappings.values.find { |mapping| mapping[:source] == :search }
          sentences << search_mapping[:description] if search_mapping
          if sortable_columns.any?
            sentences << "Supports sorting by #{formatted_column_names(sortable_columns)}"
            sentences << default_sorting_description(action_config)
          end
          sentences << list_views[:description] if list_views
          sentences << "Use limit and page for pagination"
          "#{sentences.join('. ')}."
        end

        def add_list_view_property(tool_class, core_config, views_tool_name)
          return unless core_config.actions.include?(:config_list)

          config_list = core_config.config_list
          configured_names = config_list.named_views.map { |view| view.name.to_s }
          saved_views = saved_views_enabled?(core_config)
          return if configured_names.empty? && !saved_views

          sentences = ["Select a named list view to change the returned columns and default sorting"]
          sentences << "Configured views: #{formatted_column_names(configured_names)}" if configured_names.any?
          if saved_views
            sentences << "Call `#{views_tool_name}` to get all views available to the current user"
          end
          description = sentences.join(". ")
          property_options = {type: "string", description: description}
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
              "Pass a returned `value` to its `list_view` argument; omit `list_view` to use the default columns."
            )
            include_config_list(tool_class, core_config)
            tool_class.read_only
            include_extensions(tool_class, settings)
          end
        end

        def add_column_filter_properties(tool_class, core_config, settings, mappings)
          configured_filter_columns(core_config, settings).each do |column_name, operators|
            column = core_config._columns_hash[column_name.to_s]
            next unless column

            Array(operators).each do |operator|
              add_operator_properties(tool_class, column_name, column, normalize_operator(operator), mappings)
            end
          end
        end

        def configured_filter_columns(core_config, settings)
          result = case settings[:filter_columns]
                   when Hash
                     settings[:filter_columns].transform_keys(&:to_sym)
                   when nil
                     {}
                   else
                     Array(settings[:filter_columns]).to_h { |name| [name.to_sym, :equal] }
                   end

          settings.fetch(:filter_column_sets, {}).each do |set_name, operators|
            columns_for_set(core_config, set_name).each { |name| result[name] ||= operators }
          end
          add_polymorphic_type_columns(core_config, result)
          result
        end

        def add_polymorphic_type_columns(core_config, filter_columns)
          model = core_config.model
          return unless model.respond_to?(:reflect_on_all_associations)

          model.reflect_on_all_associations(:belongs_to).select(&:polymorphic?).each do |association|
            foreign_key = association.foreign_key.to_sym
            foreign_type = association.foreign_type.to_sym
            next unless filter_columns.key?(foreign_key)
            next unless core_config._columns_hash.key?(foreign_type.to_s)

            filter_columns[foreign_type] ||= filter_columns[foreign_key]
          end
        end

        def columns_for_set(core_config, set_name)
          columns = core_config._columns_hash.values
          selected_columns = case set_name.to_sym
                             when :foreign_keys
                               columns.select { |column| column.name.end_with?("_id") }
                             when :dates
                               columns.select { |column| column.type.to_sym == :date }
                             when :timestamps
                               columns.select { |column| %i[datetime timestamp timestamptz].include?(column.type.to_sym) }
                             else
                               raise ArgumentError, "unknown MCP filter column set: #{set_name}"
                             end
          selected_columns.map { |column| column.name.to_sym }
        end

        def normalize_operator(operator)
          operator = operator.to_sym
          OPERATOR_ALIASES.fetch(operator, operator)
        end

        def add_operator_properties(tool_class, column_name, column, operator, mappings)
          case operator
          when :equal, :not_equal
            property_name = operator == :equal ? column_name : :"#{column_name}_not"
            add_scalar_property(tool_class, property_name, column, "Filter by #{column_name}")
            mappings[property_name.to_sym] = {target: column_name.to_sym, operator: operator}
          when :in, :not_in
            property_name = operator == :in ? :"#{column_name}_in" : :"#{column_name}_not_in"
            tool_class.collection property_name,
                                  type: json_type(column),
                                  description: "Filter #{column_name} by a list of values"
            mappings[property_name] = {target: column_name.to_sym, operator: operator}
          when :between, :not_between
            prefix = operator == :between ? column_name : :"#{column_name}_not"
            %i[from to].each do |endpoint|
              property_name = :"#{prefix}_#{endpoint}"
              add_scalar_property(tool_class, property_name, column, "#{endpoint.to_s.humanize} value for #{column_name}")
              mappings[property_name] = {
                target: column_name.to_sym,
                operator: :"#{'not_' if operator == :not_between}between_#{endpoint}"
              }
            end
          when :null, :not_null
            property_name = operator == :null ? :"#{column_name}_null" : :"#{column_name}_not_null"
            tool_class.property property_name,
                                type: "boolean",
                                description: "Match records where #{column_name} is #{'not ' if operator == :not_null}null"
            mappings[property_name] = {target: column_name.to_sym, operator: operator}
          else
            raise ArgumentError, "unsupported MCP filter operator for #{column_name}: #{operator}"
          end
        end

        def add_scalar_property(tool_class, property_name, column, description)
          tool_class.property(property_name, **schema_options(column), description: description)
        end

        def add_named_filter_properties(tool_class, action_config, settings, mappings)
          selected_filters(action_config, settings[:filters]).each do |filter|
            property_name = filter.name.to_sym
            if mappings.key?(property_name)
              raise ArgumentError, "named list filter #{filter.name} conflicts with an MCP column filter"
            end

            option_names = filter.map { |option| option.name.to_s }
            tool_class.property property_name,
                                type: "string",
                                description: named_filter_description(filter),
                                default: filter.default_option&.to_s,
                                enum: option_names
            mappings[property_name] = {target: filter.name, operator: :equal, source: :named_filter}
          end
        end

        def named_filter_description(filter)
          sentences = [filter.description || "Apply the #{filter.name} list filter"]
          sentences << "When omitted, the server uses the default option '#{filter.default_option}'"
          if filter.security_method_set?
            sentences << "This filter may be disallowed in the current context"
          else
            secured_options = filter.select(&:security_method_set?).map { |option| option.name.to_s }
            if secured_options.any?
              sentences << "These options may be disallowed in the current context: #{secured_options.to_sentence}"
            end
          end
          sentences.join(". ")
        end

        def selected_filters(action_config, configured_filters)
          return [] if configured_filters.nil? || !action_config.respond_to?(:filters)
          return action_config.filters.to_a if configured_filters == :all

          Array(configured_filters).filter_map { |name| action_config.filters[name] }
        end

        def add_search_property(tool_class, core_config, settings, mappings)
          return unless search_enabled?(core_config, settings)

          description = search_property_description(core_config)
          tool_class.include ActiveScaffold::Actions::Search
          tool_class.property :search,
                              type: "string",
                              description: description
          mappings[:search] = {target: :search, operator: :equal, source: :search, description: description}
        end

        def search_property_description(core_config)
          columns = core_config.search.columns.visible_columns(skip_authorization: true, flatten: true)
          labels = columns.map { |column| column.label.presence || column.name.to_s.humanize }
          return "Search text across the configured ActiveScaffold search columns" if labels.empty?

          displayed_labels = labels.first(12)
          remaining_count = labels.length - displayed_labels.length
          description = "Search text across #{displayed_labels.to_sentence}"
          description += " and #{remaining_count} more" if remaining_count.positive?
          description
        end

        def search_enabled?(core_config, settings)
          settings.fetch(:search, true) && core_config.actions.include?(:search)
        end

        def add_sorting_properties(tool_class, core_config, action_config)
          columns = core_config.columns.select(&:sortable?)
          column_names = columns.map { |column| column.name.to_s }
          return [] if column_names.empty?

          tool_class.property :sort,
                              type: "string",
                              description: "Column to sort by. Allowed columns: #{formatted_column_names(column_names)}. " \
                                           "#{default_sorting_description(action_config)}.",
                              enum: column_names
          tool_class.property :sort_direction,
                              type: "string",
                              description: "Sort direction used when sort is provided; defaults to asc",
                              default: "asc",
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
            "When sort is omitted, the configured ActiveScaffold default sorting is used"
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
                              type: "integer",
                              description: "Maximum records to return",
                              default: default_limit,
                              minimum: 1,
                              maximum: ActiveScaffold::MCP::ListTool::MAX_LIMIT
          tool_class.property :page,
                              type: "integer",
                              description: "Page number",
                              default: 1,
                              minimum: 1
        end

      end
    end
  end
end
