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
        do_list
        columns = mcp_output_columns
        render(text: JSON.generate(
          records: @records.map { |record| mcp_record_hash(record, columns) },
          page: @page.number,
          total_count: @page.pager.count,
          total_pages: @page.pager.number_of_pages
        ))
      end

      private

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
    end
  end
end
