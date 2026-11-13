# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class Presenter
      attr_reader :tool

      def initialize(tool)
        @tool = tool
      end

      def presentable_column?(column)
        return true if column.association || respond_to?(column_method_name(column), true)
        return false unless model.public_method_defined?(column.name)

        model.instance_method(column.name).parameters.none? { |type, _| %i[req keyreq].include?(type) }
      end

      def record(record, columns, counts = nil)
        columns.to_h do |column|
          [column.name, column_value(record, column, counts)]
        end
      end

      delegate :active_scaffold_config, :current_user, :params, to: :tool

      private

      def column_method_name(column)
        :"#{column.name}_column"
      end

      def column_value(record, column, counts)
        column_method = column_method_name(column)
        return send(column_method, record, column) if respond_to?(column_method, true)
        if column.association
          return association_value(record, record.public_send(column.association.name), column,
                                   counts)
        end

        record.public_send(column.name)
      end

      def association_value(record, value, column, counts)
        if column.association.collection?
          collection_association_value(record, value, column, counts)
        elsif value
          associated_record_hash(value, polymorphic: column.association.polymorphic?)
        end
      end

      def collection_association_value(record, value, column, counts)
        associated_limit = column.associated_limit
        associated_number = column.associated_number?

        if associated_limit.nil?
          return value.map { |associated_record| associated_record_hash(associated_record) }
        end

        count = association_size(record, value, column, counts) if associated_number
        return associated_number ? count : nil if associated_limit.zero?

        limited_collection_association_value(value, associated_limit, associated_number, count)
      end

      def limited_collection_association_value(value, associated_limit, associated_number, count)
        loaded_limit = associated_number ? associated_limit : associated_limit + 1
        associated_records = limited_associated_records(value, loaded_limit)
        more_records = associated_number ? count > associated_limit : associated_records.size > associated_limit
        associated_records = associated_records.first(associated_limit)
        records = associated_records.map { |associated_record| associated_record_hash(associated_record) }

        {
          (more_records ? :first_records : :records) => records,
          count: displayed_association_count(records, associated_limit, associated_number, count, more_records)
        }
      end

      def displayed_association_count(records, associated_limit, associated_number, count, more_records)
        if associated_number
          count
        elsif more_records
          ">#{associated_limit}"
        else
          records.size
        end
      end

      def limited_associated_records(value, limit)
        return value.first(limit) if value.respond_to?(:loaded?) && value.loaded?
        return value.limit(limit).to_a if value.respond_to?(:limit)

        value.first(limit)
      end

      def association_size(_record, value, column, counts)
        return counts[column.name] if counts&.key?(column.name)

        value.size
      end

      def associated_record_hash(record, polymorphic: false)
        result = {id: record.id, label: record.to_label}
        result[:model] = record.class.model_name.human if polymorphic
        result
      end

      def model
        active_scaffold_config.model
      end
    end
  end
end
