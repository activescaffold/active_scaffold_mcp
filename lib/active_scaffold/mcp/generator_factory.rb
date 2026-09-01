# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class GeneratorFactory
      class GeneratorNotFound < StandardError; end

      Rule = Data.define(:generator, :attributes, :position) do
        def matches?(values)
          attributes.all? { |name, expected| expected.nil? || values[name] == expected }
        end

        def specificity
          attributes.values.count { |value| !value.nil? }
        end
      end

      def initialize
        @action_generators = {}
        @crud_rules = []
        @custom_action_rules = []
        @registration_position = 0
        register ActiveScaffold::MCP::ListToolGenerator, actions: :list
      end

      def register(generator, actions:)
        Array(actions).each { |action_name| @action_generators[action_name.to_sym] = generator }
        self
      end

      def register_default(generator, crud_type: nil, columns: nil)
        add_rule(@crud_rules, generator, crud_type: crud_type&.to_sym, columns: columns)
      end

      # This registry is ready for ActiveScaffold's future custom_actions
      # configuration. nil values are wildcards.
      def register_custom(generator, submit_method: nil, columns: nil, destructive: nil)
        add_rule(
          @custom_action_rules,
          generator,
          submit_method: submit_method&.to_sym,
          columns: columns,
          destructive: destructive
        )
      end

      def generate_tools_for(controller_class, mcp_config)
        exposed_action_names(mcp_config).flat_map do |action_name|
          action_config, custom = action_config_for(mcp_config.core, action_name)
          generator = generator_for(action_name, action_config, custom: custom)
          unless generator
            raise GeneratorNotFound,
                  "no MCP tool generator registered for #{controller_class.name}##{action_name}"
          end

          result = generate_tool(
            generator,
            controller_class: controller_class,
            action_name: action_name,
            action_config: action_config,
            mcp_config: mcp_config,
            settings: mcp_config.settings_for(action_name)
          )
          Array(result).compact
        end
      end

      private

      def add_rule(collection, generator, **attributes)
        @registration_position += 1
        collection << Rule.new(generator:, attributes:, position: @registration_position)
        self
      end

      def exposed_action_names(mcp_config)
        names = mcp_config.actions.keys - [:all]
        available_names = (
          mcp_config.core.actions.to_a + custom_action_names(mcp_config.core)
        ).uniq
        return names & available_names unless mcp_config.actions.key?(:all)

        (names + available_names).uniq & available_names
      end

      def action_config_for(core_config, action_name)
        custom_config = custom_action_config_for(core_config, action_name)
        return [custom_config, true] if custom_config

        action_config = core_config[action_name] if core_config.actions.include?(action_name.to_sym)
        [action_config, false]
      end

      def generator_for(action_name, action_config, custom:)
        explicit_generator = @action_generators[action_name.to_sym]
        return explicit_generator if explicit_generator

        if custom
          matching_rule(
            @custom_action_rules,
            submit_method: value_for(action_config, :submit_method)&.to_sym,
            columns: columns?(action_config),
            destructive: value_for(action_config, :destructive)
          )
        elsif action_config
          matching_rule(
            @crud_rules,
            crud_type: value_for(action_config, :crud_type)&.to_sym,
            columns: columns?(action_config)
          )
        end
      end

      def matching_rule(rules, **values)
        rules.select { |rule| rule.matches?(values) }
             .max_by { |rule| [rule.specificity, rule.position] }
             &.generator
      end

      def columns?(action_config)
        return false unless action_config.respond_to?(:columns)

        columns = action_config.columns
        !columns.respond_to?(:empty?) || !columns.empty?
      end

      def value_for(config, name)
        config.public_send(name) if config.respond_to?(name)
      end

      def custom_action_names(core_config)
        custom_actions = value_for(core_config, :custom_actions)
        return [] unless custom_actions

        if custom_actions.respond_to?(:keys)
          custom_actions.keys.map(&:to_sym)
        elsif custom_actions.respond_to?(:names)
          custom_actions.names.map(&:to_sym)
        else
          []
        end
      end

      def custom_action_config_for(core_config, action_name)
        custom_actions = value_for(core_config, :custom_actions)
        return unless custom_actions&.respond_to?(:[])

        custom_actions[action_name.to_sym] || custom_actions[action_name.to_s]
      end

      def generate_tool(generator, **arguments)
        generator.generate_tool_for(**arguments)
      end
    end
  end
end
