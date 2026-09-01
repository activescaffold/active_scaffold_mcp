# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class ListToolGenerator
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

          Class.new(ActiveScaffold::MCP::ListTool).tap do |tool_class|
            tool_class.active_scaffold_config = core_config
            tool_class.active_scaffold_controller_class = controller_class
            tool_class.mcp_action_name = action_name
            tool_class.mcp_output_column_names = settings[:columns]&.map(&:to_sym)
            tool_class.tool_name(settings[:name] || tool_name(mcp_config))
            generated_title = "List #{settings[:label] || mcp_config.label}"
            tool_class.title(generated_title)
            tool_class.read_only

            add_column_filter_properties(tool_class, core_config, settings, mappings)
            add_named_filter_properties(tool_class, action_config, settings, mappings)
            add_pagination_properties(tool_class, action_config)
            tool_class.description(settings[:description] || description(generated_title, mappings))
            tool_class.mcp_param_mappings = mappings.freeze

            Array(settings[:modules]).each { |extension| tool_class.include extension }
          end
        end

        private

        def tool_name(mcp_config)
          "list_#{mcp_config.name}"
        end

        def description(title, mappings)
          filter_types = []
          filter_types << "column filters" if mappings.any? { |_name, mapping| mapping[:source] != :named_filter }
          filter_types << "named list filters" if mappings.any? { |_name, mapping| mapping[:source] == :named_filter }

          sentences = [title]
          sentences << "Supports #{filter_types.to_sentence}" if filter_types.any?
          sentences << "Use limit and page for pagination"
          "#{sentences.join('. ')}."
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
          options = {type: json_type(column), description: description}
          options[:format] = json_format(column) if json_format(column)
          tool_class.property(property_name, **options)
        end

        def json_type(column)
          case column.type.to_sym
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
          case column.type.to_sym
          when :date
            "date"
          when :datetime, :timestamp, :timestamptz
            "date-time"
          end
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
                                description: filter.description || "Apply the #{filter.name} list filter",
                                default: filter.default_option&.to_s,
                                enum: option_names
            mappings[property_name] = {target: filter.name, operator: :equal, source: :named_filter}
          end
        end

        def selected_filters(action_config, configured_filters)
          return [] if configured_filters.nil? || !action_config.respond_to?(:filters)
          return action_config.filters.to_a if configured_filters == :all

          Array(configured_filters).filter_map { |name| action_config.filters[name] }
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
