# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class Presenter
      attr_reader :tool

      def initialize(tool)
        @tool = tool
      end

      def presentable_column?(column)
        return true if column.association || presentation_method_name(column)
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

      def ui_method_names(column)
        action_name = tool.action_name
        return [] unless %w[list show].include?(action_name)

        ui_method = :"#{action_name}_ui"
        ui = column.public_send(ui_method)
        return [] unless ui

        methods = [:"mcp_#{action_name}_#{ui}"]
        methods << :"mcp_list_#{ui}" if action_name == 'show'
        methods.uniq
      end

      def ui_options(column)
        column.public_send(:"#{tool.action_name}_ui_options") || column.options
      end

      def presentation_method_name(column)
        @presentation_method_names ||= {}.compare_by_identity
        @presentation_method_names.fetch(column) do
          @presentation_method_names[column] = resolve_presentation_method_name(column)
        end
      end

      def resolve_presentation_method_name(column)
        column_method = column_method_name(column)
        return column_method if respond_to?(column_method, true)

        ui_method_names(column).find { |method_name| respond_to?(method_name, true) }
      end

      def column_value(record, column, counts)
        presentation_method = presentation_method_name(column)
        if presentation_method == column_method_name(column)
          return send(presentation_method, record, column)
        elsif presentation_method
          return send(
            presentation_method,
            record,
            column,
            ui_options: ui_options(column)
          )
        end
        if column.association
          return association_value(record, record.public_send(column.association.name), column,
                                   counts)
        end

        record.public_send(column.name)
      end

      def mcp_list_active_storage_has_one(record, column, ui_options:)
        attached = record.public_send(column.name)
        return unless attached.attached?

        active_storage_attachment_metadata(attached.attachment)
      end

      def mcp_list_active_storage_has_many(record, column, ui_options:)
        attached = record.public_send(column.name)
        return unless attached.attached?

        attached.attachments.map { |attachment| active_storage_attachment_metadata(attachment) }
      end

      def mcp_list_paperclip(record, column, ui_options:)
        attachment = record.public_send(column.name)
        return unless attachment.file?

        attachment_metadata(
          filename: attachment.original_filename,
          content_type: attachment.content_type,
          byte_size: attachment.size,
          updated_at: metadata_value(attachment, :updated_at)
        )
      end

      def mcp_list_carrierwave(record, column, ui_options:)
        uploader = record.public_send(column.name)
        file = uploader.file
        return if file.blank?

        attachment_metadata(
          filename: metadata_value(uploader, :identifier) || metadata_value(file, :filename),
          content_type: metadata_value(file, :content_type),
          byte_size: metadata_value(file, :size)
        )
      end

      def mcp_list_dragonfly(record, column, ui_options:)
        attachment = record.public_send(column.name)
        return if attachment.blank?

        attachment_metadata(
          filename: metadata_value(attachment, :name),
          content_type: metadata_value(attachment, :mime_type, :content_type),
          byte_size: metadata_value(attachment, :size)
        )
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

      def active_storage_attachment_metadata(attachment)
        blob = attachment.blob
        attachment_metadata(
          filename: blob.filename,
          content_type: blob.content_type,
          byte_size: blob.byte_size
        )
      end

      def file_column_attachment_metadata(record, column)
        value = record.public_send(column.name)
        return unless value

        attachment_metadata(filename: File.basename(value.to_s))
      end

      def attachment_metadata(filename:, content_type: nil, byte_size: nil, updated_at: nil)
        updated_at = updated_at.iso8601 if updated_at.respond_to?(:iso8601)
        {
          filename: filename&.to_s,
          content_type: content_type,
          byte_size: byte_size,
          updated_at: updated_at
        }.compact
      end

      def metadata_value(object, *methods)
        method = methods.find { |method_name| object.respond_to?(method_name) }
        object.public_send(method) if method
      end
    end
  end
end
