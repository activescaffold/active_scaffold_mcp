# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class SettingsValidator
      class InvalidSetting < ArgumentError; end

      COLUMN_SETTING = %i[columns].freeze
      COMMON_SETTINGS = %i[description label modules name presenter presenter_modules].freeze
      LIST_SETTINGS = %i[columns filter_columns filter_column_sets filters search].freeze
      SHOW_SETTINGS = %i[columns lookup_columns].freeze

      def validate!(action_name, settings)
        settings.each do |setting, value|
          next if valid?(action_name, setting, value)

          raise InvalidSetting, "unsupported MCP setting for #{action_name}: #{setting}"
        end

        settings
      end

      def valid?(action_name, setting, value = nil)
        setting = setting.to_sym
        return valid_common_setting?(setting, value) if COMMON_SETTINGS.include?(setting)

        validator = :"valid_settings_for_#{action_name}?"
        return true unless respond_to?(validator, true)

        send(validator, setting, value)
      end

      private

      def valid_common_setting?(setting, value)
        case setting
        when :description, :label, :name
          (value.is_a?(String) || value.is_a?(Symbol)) && value.to_s.present?
        when :modules, :presenter_modules
          Array(value).all? { |extension| extension.is_a?(Module) }
        when :presenter
          value.is_a?(Class)
        end
      end

      def valid_settings_for_list?(setting, value)
        return [true, false].include?(value) if setting == :search

        LIST_SETTINGS.include?(setting)
      end

      def valid_settings_for_show?(setting, _value)
        SHOW_SETTINGS.include?(setting)
      end

      def valid_settings_for_create?(setting, _value)
        COLUMN_SETTING.include?(setting)
      end

      def valid_settings_for_update?(setting, _value)
        COLUMN_SETTING.include?(setting)
      end

      def valid_settings_for_delete?(_setting, _value)
        false
      end

      def valid_settings_for_search?(_setting, _value)
        false
      end

      def valid_settings_for_nested?(_setting, _value)
        false
      end

      def valid_settings_for_subform?(_setting, _value)
        false
      end
    end
  end
end
