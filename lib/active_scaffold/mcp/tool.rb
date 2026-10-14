# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class Tool < ActiveScaffold::Config::MCP.resolve_tool(:base)
      abstract!

      class_attribute :active_scaffold_config, instance_accessor: false
      class_attribute :active_scaffold_controller_class, instance_accessor: false
      class_attribute :mcp_action_name, instance_accessor: false
      class_attribute :mcp_output_column_names, instance_accessor: false
      class_attribute :mcp_param_mappings, instance_accessor: false, default: {}

      class << self
        def parameter_filter
          filters = Rails.application&.config&.filter_parameters || []
          return @parameter_filter if @parameter_filter_filters == filters

          @parameter_filter_filters = filters.dup.freeze
          @parameter_filter = ActiveSupport::ParameterFilter.new(filters)
        end

        def tool_authorized?(user = ActionMCP::Current.user)
          return true unless respond_to?(:active_scaffold_tool_authorized?)

          active_scaffold_tool_authorized?(
            controller_class: active_scaffold_controller_class,
            action_name: mcp_action_name,
            user: user
          )
        end

        # ActiveScaffold action modules declare Rails controller callbacks and
        # helpers when included. MCP tools invoke their operation methods
        # directly, so these declarations intentionally do nothing.
        def before_action(...); end
        def prepend_before_action(...); end
        def after_action(...); end
        def around_action(...); end
        def helper_method(...); end
        def rescue_from(...); end
      end

      include ActiveScaffold::Finder
      include ActiveScaffold::Constraints
      include ActiveScaffold::Actions::Core

      around_perform :with_active_scaffold_context

      def initialize(attributes = {})
        @provided_mcp_arguments = attributes.respond_to?(:keys) ? attributes.keys.map(&:to_s) : []
        super
      end

      def active_scaffold_config
        @active_scaffold_config ||= begin
          config = self.class.active_scaffold_config
          config.new_user_settings({}, params)
          config.user
        end
      end

      def params
        @params ||= ::ActionController::Parameters.new(build_active_scaffold_params)
      end

      def flash
        @flash ||= ActiveScaffold::MCP::Flash.new
      end

      def action_name
        self.class.mcp_action_name.to_s
      end

      def active_scaffold_session_storage(_id = nil)
        @active_scaffold_session_storage ||= ActiveSupport::HashWithIndifferentAccess.new
      end

      private

      def with_active_scaffold_context
        previous_user_proc = ActiveScaffold::Registry.current_user_proc
        ActiveScaffold::Registry.current_user_proc = -> { current_user }
        if tool_authorized?
          yield
        else
          unauthorized_tool!
        end
      rescue ActiveScaffold::ActionNotAllowed
        report_error(action_not_allowed_message)
      rescue StandardError => exception
        report_active_scaffold_exception(exception)
        raise
      ensure
        ActiveScaffold::Registry.current_user_proc = previous_user_proc
      end

      def report_active_scaffold_exception(exception)
        arguments = mcp_exception_arguments
        Rails.logger.error(
          "[ActiveScaffold::MCP] #{self.class.tool_name} failed with arguments #{arguments.inspect}: " \
          "#{exception.full_message(highlight: false, order: :top)}"
        )
        notify_active_scaffold_exception(exception) if respond_to?(:notify_active_scaffold_exception, true)
      rescue StandardError => notification_exception
        Rails.logger.error(
          "[ActiveScaffold::MCP] exception notification failed for #{self.class.tool_name}: " \
          "#{notification_exception.full_message(highlight: false, order: :top)}"
        )
      end

      def action_not_allowed_message
        "The requested #{action_name.humanize.downcase} action is not allowed for the current user or request context."
      end

      def mcp_exception_arguments
        arguments = if defined?(@_wire_arguments)
                      @_wire_arguments
                    else
                      attributes.compact.merge(@_provided_additional_attributes)
                    end
        ActiveScaffold::MCP::Tool.parameter_filter.filter(arguments.deep_dup)
      end

      # Let the configured base tool customize execution authorization failures.
      # Its implementation replaces this fallback and is responsible for
      # reporting the failure, normally by raising an application-specific error.
      def unauthorized_tool!
        return super if defined?(super)

        raise ActiveScaffold::ActionNotAllowed
      end

      def tool_authorized?
        self.class.tool_authorized?(current_user)
      end

      def build_active_scaffold_params
        filter_values = {}
        ranges = Hash.new { |hash, key| hash[key] = {} }

        self.class.mcp_param_mappings.each do |property_name, mapping|
          next unless @provided_mcp_arguments.include?(property_name.to_s)

          value = public_send(property_name)
          target = mapping.fetch(:target).to_s
          case mapping.fetch(:operator)
          when :equal, :in
            filter_values[target] = value
          when :not_equal, :not_in
            filter_values["#{target}!"] = value
          when :between_from, :between_to, :not_between_from, :not_between_to
            ranges[[target, mapping[:operator].to_s.start_with?("not_")]][mapping[:operator].to_s.end_with?("from") ? :from : :to] = value
          when :null
            filter_values[target] = "" if value
          when :not_null
            filter_values["#{target}!"] = "" if value
          end
        end

        ranges.each do |(target, negated), endpoints|
          filter_values["#{target}#{'!' if negated}"] = "#{endpoints[:from]}..#{endpoints[:to]}"
        end

        filter_values.merge(format: "json")
      end

      def mcp_output_columns
        configured_columns = mcp_configured_output_column_names
        columns = if configured_columns
                    configured_columns.filter_map do |column_name|
                      next unless active_scaffold_config.model.authorized_for?(crud_type: :read, column: column_name)

                      active_scaffold_config.columns[column_name]
                    end
                  else
                    mcp_default_output_columns
                  end

        (mcp_primary_key_columns + columns).uniq(&:name).select { |column| mcp_output_column?(column) }
      end

      def mcp_output_column?(column)
        return true if column.association || respond_to?(mcp_column_method_name(column), true)

        model = active_scaffold_config.model
        return false unless model.public_method_defined?(column.name)

        model.instance_method(column.name).parameters.none? { |type, _| type == :req || type == :keyreq }
      end

      def mcp_column_method_name(column)
        :"#{column.name}_column"
      end

      def mcp_configured_output_column_names
        self.class.mcp_output_column_names
      end

      def mcp_primary_key_columns
        Array(active_scaffold_config.model.primary_key).filter_map do |column_name|
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
        column_method = mcp_column_method_name(column)
        return send(column_method, record, column) if respond_to?(column_method, true)
        return mcp_association_value(record, record.public_send(column.association.name), column) if column.association

        record.public_send(column.name)
      end

      def mcp_association_value(record, value, column)
        if column.association.collection?
          mcp_collection_association_value(record, value, column)
        elsif value
          mcp_associated_record_hash(value, polymorphic: column.association.polymorphic?)
        end
      end

      def mcp_collection_association_value(record, value, column)
        associated_limit = column.associated_limit
        associated_number = column.associated_number?

        if associated_limit.nil?
          return value.map { |associated_record| mcp_associated_record_hash(associated_record) }
        end

        count = mcp_association_size(record, value, column) if associated_number
        return associated_number ? count : nil if associated_limit.zero?

        loaded_limit = associated_number ? associated_limit : associated_limit + 1
        associated_records = mcp_limited_associated_records(value, loaded_limit)
        more_records = associated_number ? count > associated_limit : associated_records.size > associated_limit
        associated_records = associated_records.first(associated_limit)
        records = associated_records.map { |associated_record| mcp_associated_record_hash(associated_record) }
        displayed_count = if associated_number
                            count
                          elsif more_records
                            ">#{associated_limit}"
                          else
                            records.size
                          end

        {
          (more_records ? :first_records : :records) => records,
          count: displayed_count
        }
      end

      def mcp_limited_associated_records(value, limit)
        if value.respond_to?(:loaded?) && value.loaded?
          value.first(limit)
        elsif value.respond_to?(:limit)
          value.limit(limit).to_a
        else
          value.first(limit)
        end
      end

      def mcp_association_size(record, value, column)
        cached_counts = @counts&.dig(column.name)
        return value.size unless cached_counts

        key = column.association.primary_key if count_on_association_class?(column)
        cached_counts[record.public_send(key || :id)] || 0
      end

      def mcp_associated_record_hash(record, polymorphic: false)
        result = {id: record.id, label: record.to_label}
        result[:model] = record.class.model_name.human if polymorphic
        result
      end

      def mcp_default_output_columns
        raise NotImplementedError
      end

      def mcp_argument_provided?(name)
        @provided_mcp_arguments.include?(name.to_s)
      end

      # The controller implementation branches on request methods and renders
      # an HTTP response. MCP operations already represent the submitted branch.
      def process_action_link_action(_render_action = :action_update, crud_type_or_security_options = nil)
        @action_link = active_scaffold_config.action_links[action_name]
        if params[:id]
          security_options = crud_type_or_security_options || {crud_type: :update, action: action_name.to_sym}
          get_row(security_options)
          if @record
            yield @record
          else
            self.successful = false
            flash[:error] = "Record is not available for #{action_name}"
          end
        else
          raise ActiveScaffold::ActionNotAllowed unless action_link_authorized?(@action_link)

          yield
        end
      end
    end
  end
end
