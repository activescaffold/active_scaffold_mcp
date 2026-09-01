# frozen_string_literal: true

module ActiveScaffold
  module Config
    class MCP < Base
      def initialize(core_config)
        super
        @actions = self.class.duplicate_actions(self.class.actions)
        self.filter_column_sets = self.class.filter_column_sets
      end

      # Global defaults. These are available through config.mcp in an
      # ActiveScaffold.defaults block.
      cattr_accessor :actions, instance_accessor: false, default: {}.freeze
      cattr_accessor :filter_column_sets, instance_accessor: false, default: {}.freeze
      cattr_accessor :base_tool, instance_accessor: false,
                    default: -> { "ApplicationMCPTool".safe_constantize || ActionMCP::Tool }
      cattr_accessor :settings_validator, instance_accessor: false,
                    default: ActiveScaffold::MCP::SettingsValidator
      cattr_accessor :tool_generator, instance_accessor: false,
                    default: ActiveScaffold::MCP::GeneratorFactory.new

      class << self
        alias unvalidated_actions= actions=
        alias filter_columns_sets filter_column_sets
        alias filter_columns_sets= filter_column_sets=

        def actions=(value)
          self.unvalidated_actions = normalize_actions(value)
        end
        private :unvalidated_actions=

        def resolve_tool(name)
          configured_tool = public_send(:"#{name}_tool")
          configured_tool = configured_tool.call if configured_tool.respond_to?(:call)
          configured_tool.is_a?(String) ? configured_tool.constantize : configured_tool
        end

        def resolved_settings_validator
          configured_validator = settings_validator
          if !defined?(@resolved_settings_validator_source) || @resolved_settings_validator_source != configured_validator
            @resolved_settings_validator_source = configured_validator
            @resolved_settings_validator = configured_validator.is_a?(Class) ? configured_validator.new : configured_validator
          end

          @resolved_settings_validator
        end

        def validate_mcp_setting!(action_name, setting, value)
          resolved_settings_validator.validate!(action_name, setting.to_sym => value)
        end

        def mcp_setting_for(action_name, setting)
          action_settings = actions.fetch(:all, {}).merge(actions.fetch(action_name.to_sym, {}))
          action_settings[setting.to_sym]
        end

        def set_mcp_setting(action_name, setting, value)
          action_name = action_name.to_sym
          setting = setting.to_sym
          updated_actions = actions.transform_keys(&:to_sym)
          action_settings = updated_actions.fetch(action_name, {}).merge(setting => value)
          updated_actions[action_name] = normalize_settings(action_settings)
          self.unvalidated_actions = updated_actions
          value
        end

        def expose(action_name, settings = nil)
          action_name = action_name.to_sym
          updated_actions = actions.transform_keys(&:to_sym)
          unless settings.nil? && updated_actions.key?(action_name)
            updated_actions[action_name] = normalize_action_settings(action_name, settings)
          end
          self.unvalidated_actions = updated_actions

          action_config = ActiveScaffold::MCP::ActionConfig.new(self, action_name)
          yield action_config if block_given?
          action_config
        end

        # These methods are also used by per-controller MCP config instances,
        # keeping global defaults and local configuration normalized identically.
        def normalize_actions(value)
          return {all: {}} if all?(value)

          case value
          when nil
            {}
          when Hash
            value.each_with_object({}) do |(action_name, settings), result|
              result[action_name.to_sym] = normalize_action_settings(action_name, settings)
            end
          else
            Array(value).each_with_object({}) do |action_name, result|
              result[action_name.to_sym] = {}
            end
          end
        end

        def normalize_action_settings(action_name, value)
          settings = case value
                     when nil, true
                       {}
                     when Array
                       {columns: normalize_names(value)}
                     when Hash
                       value.to_h.transform_keys(&:to_sym)
                     else
                       raise ArgumentError, "settings for #{action_name} must be an array or hash"
                     end

          resolved_settings_validator.validate!(action_name, settings)
          normalize_settings(settings)
        end

        def normalize_settings(settings)
          settings.each_with_object({}) do |(name, value), result|
            result[name] = case name
                           when :description, :label, :name
                             value.to_s
                           when :columns
                             normalize_names(value)
                           when :filter_columns
                             value.is_a?(Hash) ? normalize_operator_map(value) : normalize_names(value)
                           when :filter_column_sets
                             normalize_filter_column_sets(value)
                           when :filters
                             all?(value) ? :all : normalize_names(value)
                           when :modules
                             Array(value).compact
                           else
                             duplicate_setting(value)
                           end
          end
        end

        def duplicate_actions(configured_actions)
          configured_actions.each_with_object({}) do |(action_name, settings), result|
            result[action_name] = duplicate_settings(settings)
          end
        end

        def duplicate_settings(settings)
          settings.each_with_object({}) do |(name, value), result|
            result[name] = name.to_sym == :modules ? Array(value).dup : duplicate_setting(value)
          end
        end

        def normalize_operator_map(value)
          return {} if value.nil?

          value.to_h.each_with_object({}) do |(name, operators), result|
            result[name.to_sym] = operators.is_a?(Array) ? normalize_names(operators) : operators.to_sym
          end
        end

        def normalize_filter_column_sets(value)
          return {} if value.nil?

          unless value.is_a?(Hash)
            raise ArgumentError,
                  "filter_column_sets must be a hash mapping set names to operators, " \
                  "for example: {foreign_keys: :in, timestamps: :range}"
          end

          normalize_operator_map(value)
        end

        def method_missing(name, *args)
          if args.empty? && mcp_action?(name)
            ActiveScaffold::MCP::ActionConfig.new(self, name)
          else
            super
          end
        end

        def respond_to_missing?(name, include_all = false)
          mcp_action?(name) || super
        end

        def mcp_action?(name)
          ActiveScaffold::Config::Core.config_class?(name) || actions.key?(name.to_sym)
        end

        def all?(value)
          value == :all || value == "all"
        end

        def normalize_names(value)
          Array(value).flatten.compact.map(&:to_sym).uniq
        end

        def duplicate_setting(value)
          value.respond_to?(:deep_dup) ? value.deep_dup : value
        end

        private :mcp_action?, :all?, :normalize_names, :duplicate_setting
      end

      attr_reader :actions, :filter_column_sets
      attr_writer :label, :name
      alias exposed_actions actions
      alias filter_columns_sets filter_column_sets

      def label(core: @core)
        @label ? as_(@label, count: 2) : core.label(count: 2)
      end

      def name
        (@name || core.model.model_name.route_key).to_s
      end

      def actions=(value)
        @actions = self.class.normalize_actions(value)
      end
      alias exposed_actions= actions=

      def filter_column_sets=(value)
        @filter_column_sets = self.class.normalize_filter_column_sets(value)
      end
      alias filter_columns_sets= filter_column_sets=

      def expose(action_name, settings = nil)
        action_name = action_name.to_sym
        unless settings.nil? && @actions.key?(action_name)
          @actions[action_name] = self.class.normalize_action_settings(action_name, settings)
        end

        action_config = ActiveScaffold::MCP::ActionConfig.new(self, action_name)
        yield action_config if block_given?
        action_config
      end

      def exposed?(action_name)
        @actions.key?(:all) || @actions.key?(action_name.to_sym)
      end

      def settings_for(action_name)
        return unless exposed?(action_name)

        settings = self.class.duplicate_settings(
          @actions.fetch(:all, {}).merge(@actions.fetch(action_name.to_sym, {}))
        )

        if action_name.to_sym == :list && !settings.key?(:filter_column_sets) && @filter_column_sets.any?
          settings[:filter_column_sets] = @filter_column_sets.deep_dup
        end

        settings
      end
      alias action_settings settings_for

      def mcp_setting_for(action_name, setting)
        settings_for(action_name)&.[](setting.to_sym)
      end

      def set_mcp_setting(action_name, setting, value)
        action_name = action_name.to_sym
        setting = setting.to_sym
        settings = @actions.fetch(action_name, {}).merge(setting => value)
        @actions[action_name] = self.class.normalize_settings(settings)
        value
      end

      def validate_mcp_setting!(action_name, setting, value)
        self.class.validate_mcp_setting!(action_name, setting, value)
      end

      def method_missing(name, *args)
        if args.empty? && mcp_action?(name)
          ActiveScaffold::MCP::ActionConfig.new(self, name)
        else
          super
        end
      end

      def respond_to_missing?(name, include_all = false)
        mcp_action?(name) || super
      end

      private

      def mcp_action?(name)
        ActiveScaffold::Config::Core.config_class?(name) || @actions.key?(name.to_sym)
      end
    end
  end
end
