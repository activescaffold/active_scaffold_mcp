# frozen_string_literal: true

require "json"

module ActiveScaffold
  module MCP
    class ListTool < Tool
      DEFAULT_LIMIT = 25
      MAX_LIMIT = 100

      abstract!

      include ActiveScaffold::Actions::List

      def find_page_options
        super.merge(
          pagination: true,
          per_page: limit.to_i.clamp(1, MAX_LIMIT),
          page: [page.to_i, 1].max
        )
      end

      def perform
        if mcp_argument_provided?(:search)
          store_search_params_into_session
          do_search
        end
        set_default_sorting if mcp_argument_provided?(:list_view)
        do_list
        return if report_disallowed_filters

        columns = mcp_output_columns
        render(text: JSON.generate(
          records: @records.map { |record| mcp_record_hash(record, columns) },
          page: @page.number,
          total_count: @page.pager.count,
          total_pages: @page.pager.number_of_pages
        ))
      end

      private

      def build_active_scaffold_params
        super.tap do |active_scaffold_params|
          if mcp_argument_provided?(:list_view)
            active_scaffold_params[:config_list_view] = list_view
          end
          next unless mcp_argument_provided?(:sort)

          active_scaffold_params[:sort] = sort
          active_scaffold_params[:sort_direction] = sort_direction.presence || "asc"
        end
      end

      def report_disallowed_filters
        disallowed_filters = Array(@filter_states).filter_map do |name, state|
          next unless state[:requested] && state[:status] == :disallowed

          selection = (state[:option]&.name || params[name]).to_s
          ["`#{name}`", "`#{name}=#{selection.inspect}`"]
        end
        return false if disallowed_filters.empty?

        filter_names = disallowed_filters.map(&:first)
        filter_selections = disallowed_filters.map(&:last)

        report_error(
          "The following requested filter selections could not be applied in this call because they were not allowed " \
          "for its current arguments and context: #{filter_selections.to_sentence}. No records were returned. " \
          "Retry the same call with only #{filter_names.to_sentence} omitted and keep all other arguments unchanged. " \
          "Filter availability is evaluated for each call, so the selection may be allowed with different arguments " \
          "or context."
        )
        true
      end

      def action_not_allowed_message
        return super unless params[:config_list_view].present?

        "List view #{params[:config_list_view].inspect} is not allowed for the current user."
      end

      # MCP tools render their own result and do not participate in HTTP
      # conditional GET handling. Disabling it also avoids the controller-only
      # request dependency while ActiveScaffold builds a page.
      def conditional_get_support?
        false
      end

      def tool_authorized?
        super && list_authorized? && (!mcp_argument_provided?(:search) || search_authorized?)
      end

      def mcp_default_output_columns
        list_columns
      end

      def mcp_configured_output_column_names
        return if mcp_argument_provided?(:list_view)

        super
      end

      def controller_name
        self.class.active_scaffold_controller_class.controller_name
      end

      def active_scaffold_session_storage_key(id = nil)
        id ||= params[:eid] || self.class.active_scaffold_controller_class.controller_path
        "as:#{id}"
      end
    end
  end
end
