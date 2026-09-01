# frozen_string_literal: true

require "json"

module ActiveScaffold
  module MCP
    class ListTool < Tool
      DEFAULT_LIMIT = 25
      MAX_LIMIT = 100

      abstract!

      class_attribute :mcp_output_column_names, instance_accessor: false

      include ActiveScaffold::Actions::List

      def find_page_options
        super.merge(
          pagination: true,
          per_page: limit.to_i.clamp(1, MAX_LIMIT),
          page: [page.to_i, 1].max
        )
      end

      def perform
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
        super && list_authorized?
      end

      def mcp_output_columns
        configured_columns = self.class.mcp_output_column_names
        return list_columns unless configured_columns

        configured_columns.filter_map do |column_name|
          next unless active_scaffold_config.model.authorized_for?(crud_type: :read, column: column_name)

          active_scaffold_config.columns[column_name]
        end
      end

      def mcp_record_hash(record, columns)
        columns.each_with_object({}) do |column, result|
          column_name = column.name
          next unless record.authorized_for?(crud_type: :read, column: column_name)

          result[column_name] = mcp_column_value(record, column)
        end
      end

      def mcp_column_value(record, column)
        return mcp_association_value(record.public_send(column.association.name), column) if column.association
        return record.public_send(column.name) if record.respond_to?(column.name)
      end

      def mcp_association_value(value, column)
        if column.association.collection?
          value.map { |associated_record| mcp_associated_record_hash(associated_record) }
        elsif value
          mcp_associated_record_hash(value)
        end
      end

      def mcp_associated_record_hash(record)
        {id: record.id, label: record.to_label}
      end
    end
  end
end
