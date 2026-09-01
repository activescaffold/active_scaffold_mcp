# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class ActionConfig
      attr_reader :action_name

      def initialize(owner, action_name)
        @owner = owner
        @action_name = action_name.to_sym
      end

      def [](setting)
        @owner.mcp_setting_for(@action_name, setting)
      end

      def []=(setting, value)
        @owner.validate_mcp_setting!(@action_name, setting, value)
        @owner.set_mcp_setting(@action_name, setting, value)
      end

      def method_missing(name, *args)
        method_name = name.to_s
        if method_name.end_with?("=") && args.one?
          self[method_name.delete_suffix("=")] = args.first
        elsif args.empty?
          self[name]
        else
          super
        end
      end

      def respond_to_missing?(_name, _include_all = false)
        true
      end
    end
  end
end
