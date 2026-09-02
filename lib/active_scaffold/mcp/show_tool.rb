# frozen_string_literal: true

require "json"

module ActiveScaffold
  module MCP
    class ShowTool < Tool
      class LookupNotFound < StandardError; end
      class AmbiguousLookup < StandardError; end

      abstract!

      class_attribute :mcp_lookup_column_names, instance_accessor: false, default: [].freeze
      class_attribute :mcp_primary_key_name, instance_accessor: false

      validate :exactly_one_lookup_argument

      def perform
        resolve_lookup_id
        do_show
        render(text: JSON.generate(record: mcp_record_hash(@record, mcp_output_columns)))
      end

      private

      def tool_authorized?
        super && show_authorized?
      end

      def mcp_default_output_columns
        active_scaffold_config.show.columns.visible_columns
      end

      def exactly_one_lookup_argument
        provided_names = lookup_argument_names.select { |name| mcp_argument_provided?(name) }
        return if provided_names.one?

        errors.add(:base, "Provide exactly one of #{lookup_argument_names.to_sentence}")
      end

      def lookup_argument_names
        [:id, *self.class.mcp_lookup_column_names]
      end

      def resolve_lookup_id
        return if mcp_argument_provided?(:id)

        column_name = self.class.mcp_lookup_column_names.find { |name| mcp_argument_provided?(name) }
        ids = filtered_query.where(column_name => public_send(column_name))
                            .limit(2)
                            .pluck(self.class.mcp_primary_key_name)
        raise LookupNotFound, "No record found for #{column_name}" if ids.empty?
        raise AmbiguousLookup, "More than one record found for #{column_name}" if ids.many?

        params[:id] = ids.first
      end
    end
  end
end
