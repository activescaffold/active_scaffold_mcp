# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class ShowToolGenerator < ToolGenerator
      class << self
        def generate_tool_for(controller_class:, action_name:, action_config:, mcp_config:, settings:)
          core_config = mcp_config.core
          primary_key = core_config.model.primary_key
          raise ArgumentError, "cannot generate a show tool without a primary key" if primary_key.blank?
          raise ArgumentError, "composite primary keys are not supported by the show tool" if primary_key.is_a?(Array)
          lookup_columns = Array(settings[:lookup_columns]).map(&:to_sym).uniq - [primary_key.to_sym]
          validate_lookup_columns!(core_config, lookup_columns)

          Class.new(ActiveScaffold::MCP::ShowTool).tap do |tool_class|
            configure_tool_class(tool_class, controller_class:, action_name:, core_config:, mcp_config:, settings:)
            tool_class.mcp_lookup_column_names = lookup_columns.freeze
            tool_class.mcp_primary_key_name = primary_key.to_sym
            tool_class.include ActiveScaffold::Actions::List if core_config.actions.include?(:list)
            tool_class.include ActiveScaffold::Actions::Show
            tool_class.description(settings[:description] || description(tool_class.title, lookup_columns))
            tool_class.read_only
            tool_class.property :id,
                                **schema_options(core_config._columns_hash[primary_key.to_s]),
                                description: "Database ID of the #{singular_label(mcp_config)} to return",
                                required: lookup_columns.empty?
            mappings = {id: {target: :id, operator: :equal}}
            lookup_columns.each do |column_name|
              tool_class.property column_name,
                                  **schema_options(core_config._columns_hash[column_name.to_s]),
                                  description: "#{column_name.to_s.humanize} of the #{singular_label(mcp_config)} to return"
              mappings[column_name] = {target: column_name, operator: :equal}
            end
            tool_class.mcp_param_mappings = mappings.freeze

            include_extensions(tool_class, settings)
          end
        end

        private

        def validate_lookup_columns!(core_config, lookup_columns)
          unknown_columns = lookup_columns.reject { |name| core_config._columns_hash.key?(name.to_s) }
          return if unknown_columns.empty?

          raise ArgumentError, "unknown show lookup columns: #{unknown_columns.to_sentence}"
        end

        def tool_resource_name(mcp_config)
          super.singularize
        end

        def tool_resource_label(mcp_config, settings)
          super.singularize
        end

        def description(generated_title, lookup_columns)
          identifiers = ["id", *lookup_columns.map(&:to_s)]
          human_identifiers = identifiers.map { |name| name.humanize.downcase }
          arguments = identifiers.map { |name| "`#{name}`" }
          resource_label = generated_title.delete_prefix("Show ").singularize
          "Retrieve one #{resource_label} by #{human_identifiers.to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')}. " \
            "Use this tool when the user supplies one of these identifiers. " \
            "Pass exactly one of #{arguments.to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')}."
        end
      end
    end
  end
end
