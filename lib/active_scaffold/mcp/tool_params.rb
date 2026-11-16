# frozen_string_literal: true

module ActiveScaffold
  module MCP
    module ToolParams
      private

      def build_active_scaffold_params
        filter_values = {}
        ranges = Hash.new { |hash, key| hash[key] = {} }

        self.class.mcp_param_mappings.each do |property_name, mapping|
          next unless @provided_mcp_arguments.include?(property_name.to_s)

          add_mapped_filter_value(filter_values, ranges, mapping, public_send(property_name))
        end

        add_range_filter_values(filter_values, ranges)

        filter_values.merge(format: 'json')
      end

      def add_mapped_filter_value(filter_values, ranges, mapping, value)
        target = mapping.fetch(:target).to_s
        operator = mapping.fetch(:operator)
        case operator
        when :equal, :in then filter_values[target] = value
        when :not_equal, :not_in then filter_values["#{target}!"] = value
        when :between_from, :between_to, :not_between_from, :not_between_to
          operator_name = operator.to_s
          range_key = [target, operator_name.start_with?('not_')]
          ranges[range_key][operator_name.end_with?('from') ? :from : :to] = value
        when :null then filter_values[target] = '' if value
        when :not_null then filter_values["#{target}!"] = '' if value
        end
      end

      def add_range_filter_values(filter_values, ranges)
        ranges.each do |(target, negated), endpoints|
          filter_values["#{target}#{'!' if negated}"] = "#{endpoints[:from]}..#{endpoints[:to]}"
        end
      end

      def mcp_argument_provided?(name)
        @provided_mcp_arguments.include?(name.to_s)
      end
    end
  end
end
