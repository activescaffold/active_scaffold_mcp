# frozen_string_literal: true

require "json"
require "set"

module ActiveScaffold
  module MCP
    class ListViewsTool < ListTool
      abstract!

      def perform
        render(text: JSON.generate(views: mcp_available_list_views))
      end

      private

      def mcp_available_list_views
        configured_views = active_scaffold_config.config_list.named_views.filter_map do |view|
          next if view.security_method && !send(view.security_method)

          {
            label: view.name.to_s,
            value: view.name.to_s,
            source: "configured"
          }.tap do |result|
            result[:description] = view.tooltip.to_s if view.respond_to?(:tooltip) && view.tooltip.present?
          end
        end
        configured_values = configured_views.to_set { |view| view[:value] }
        saved_views = config_list_named_views.filter_map do |item|
          label, value = Array(item)
          value ||= label
          next if configured_values.include?(value.to_s)

          {
            label: label.to_s,
            value: value.to_s,
            source: "saved"
          }
        end
        configured_views + saved_views
      end
    end
  end
end
