# frozen_string_literal: true

module ActiveScaffold
  module MCP
    module ProfileUser
      class InvalidReference < ArgumentError; end

      module_function

      def resolve(reference)
        class_name, separator, id = reference.to_s.rpartition("#")
        if separator.empty? || class_name.empty? || id.empty?
          raise InvalidReference, "MCP_USER must use CLASS#ID, for example: User#201"
        end

        user_class = class_name.safe_constantize
        raise InvalidReference, "MCP_USER class does not exist: #{class_name}" unless user_class

        unless user_class.respond_to?(:find)
          raise InvalidReference, "MCP_USER class must respond to find: #{class_name}"
        end

        user_class.find(id)
      end
    end
  end
end
