# frozen_string_literal: true

require "test_helper"

class ActiveScaffoldMCPTest < Minitest::Test
  def test_has_a_version
    refute_nil ActiveScaffold::MCP::VERSION
  end

  def test_base_tool_is_abstract
    assert_predicate ActiveScaffold::MCP::Tool, :abstract?
  end

  def test_base_tool_supports_active_scaffold_result_state_and_flash
    tool = Class.new(ActiveScaffold::MCP::Tool).new

    assert tool.send(:successful?)
    tool.send(:successful=, false)
    refute tool.send(:successful?)

    tool.flash[:warning] = "Check this record"
    assert_equal ["Check this record"], tool.flash.messages
  end

  def test_base_tool_uses_top_level_action_controller_parameters
    created_nested_action_controller = !ActiveScaffold.const_defined?(:ActionController, false)
    ActiveScaffold.const_set(:ActionController, Module.new) if created_nested_action_controller
    tool = Class.new(ActiveScaffold::MCP::Tool).new

    assert_instance_of ::ActionController::Parameters, tool.params
  ensure
    ActiveScaffold.send(:remove_const, :ActionController) if created_nested_action_controller
  end

  def test_base_tool_uses_action_mcp_current_user
    previous_user = ActionMCP::Current.user
    user = Object.new
    ActionMCP::Current.user = user

    tool = Class.new(ActiveScaffold::MCP::Tool).new

    assert_same user, tool.send(:current_user)
    refute_respond_to ActiveScaffold::Config::MCP, :current_user
  ensure
    ActionMCP::Current.user = previous_user
  end

  def test_profile_user_resolves_class_and_id
    user = Object.new
    user_class = Class.new do
      define_singleton_method(:find) do |id|
        raise "unexpected id" unless id == "201"

        user
      end
    end
    Object.const_set(:MCPTestUser, user_class)

    assert_same user, ActiveScaffold::MCP::ProfileUser.resolve("MCPTestUser#201")
  ensure
    Object.send(:remove_const, :MCPTestUser) if Object.const_defined?(:MCPTestUser, false)
  end

  def test_profile_user_rejects_invalid_references
    error = assert_raises(ActiveScaffold::MCP::ProfileUser::InvalidReference) do
      ActiveScaffold::MCP::ProfileUser.resolve("User")
    end
    assert_includes error.message, "CLASS#ID"

    error = assert_raises(ActiveScaffold::MCP::ProfileUser::InvalidReference) do
      ActiveScaffold::MCP::ProfileUser.resolve("MissingMCPUser#201")
    end
    assert_includes error.message, "class does not exist"
  end

  def test_base_tool_allows_missing_base_tool_authorization_hook
    tool_class = Class.new(ActiveScaffold::MCP::Tool)

    assert tool_class.tool_authorized?(Object.new)
  end

  def test_base_tool_logs_and_notifies_an_exception_before_action_mcp_hides_it
    previous_logger = Rails.logger
    previous_application = Rails.application
    application = Struct.new(:config).new(Struct.new(:filter_parameters).new([:token]))
    Rails.define_singleton_method(:application) { application }
    logged = []
    logger = Object.new
    logger.define_singleton_method(:error) { |message| logged << message }
    notified = nil
    tool_class = Class.new(ActiveScaffold::MCP::Tool) do
      tool_name "failing_active_scaffold_tool"
    end
    tool_class.abstract!
    tool = tool_class.new
    tool.instance_variable_set(:@_wire_arguments, {"case_number" => "S0000007", "token" => "secret"})
    tool.define_singleton_method(:notify_active_scaffold_exception) { |exception| notified = exception }
    exception = RuntimeError.new("visible in the server log")
    exception.set_backtrace(["list_tool.rb:10:in 'perform'"])

    Rails.logger = logger
    tool.send(:report_active_scaffold_exception, exception)

    assert_equal "visible in the server log", notified.message
    assert_includes logged.join("\n"), "failing_active_scaffold_tool failed"
    assert_includes logged.join("\n"), '"case_number" => "S0000007"'
    assert_includes logged.join("\n"), '"token" => "[FILTERED]"'
    refute_includes logged.join("\n"), "secret"
    assert_includes logged.join("\n"), "visible in the server log"
  ensure
    Rails.logger = previous_logger
    Rails.define_singleton_method(:application) { previous_application }
  end

  def test_base_tool_reuses_parameter_filter_until_configuration_changes
    previous_application = Rails.application
    filter_parameters = [:token]
    application = Struct.new(:config).new(Struct.new(:filter_parameters).new(filter_parameters))
    Rails.define_singleton_method(:application) { application }

    first_filter = ActiveScaffold::MCP::Tool.parameter_filter

    assert_same first_filter, ActiveScaffold::MCP::Tool.parameter_filter

    filter_parameters << :password

    refute_same first_filter, ActiveScaffold::MCP::Tool.parameter_filter
  ensure
    Rails.define_singleton_method(:application) { previous_application }
  end

  def test_base_tool_class_authorization_hook_receives_tool_context
    calls = []
    controller_class = Class.new
    tool_class = Class.new(ActiveScaffold::MCP::Tool) do
      self.active_scaffold_controller_class = controller_class
      self.mcp_action_name = :list

      define_singleton_method(:active_scaffold_tool_authorized?) do |**arguments|
        calls << arguments
        false
      end
    end
    user = Object.new

    refute tool_class.tool_authorized?(user)
    assert_equal(
      [{controller_class: controller_class, action_name: :list, user: user}],
      calls
    )
  end

  def test_filtered_tools_keeps_manual_and_authorized_tools
    item = Struct.new(:klass)
    manual_tool = Class.new
    authorized_tool = Class.new do
      def self.tool_authorized?
        true
      end
    end
    denied_tool = Class.new do
      def self.tool_authorized?
        false
      end
    end
    base_configuration = Class.new do
      attr_accessor :tools

      def filtered_tools
        tools
      end
    end
    configuration_class = Class.new(base_configuration) do
      prepend ActiveScaffold::MCP::FilteredTools
    end
    configuration = configuration_class.new
    configuration.tools = [item.new(manual_tool), item.new(authorized_tool), item.new(denied_tool)]

    assert_equal [manual_tool, authorized_tool], configuration.filtered_tools.map(&:klass)
  end

  def test_mcp_action_config_is_resolved_by_active_scaffold
    assert_equal "MCP", "mcp".camelize
    assert_operator ActiveScaffold::Config::MCP, :<, ActiveScaffold::Config::Base
    assert_same ActiveScaffold::Config::MCP, ActiveScaffold::Config::Core.config_class(:mcp)
  end

  def test_mcp_config_stores_settings_per_action
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)

    refute config.exposed?(:list)

    config.actions = {
      list: {
        columns: %i[id name status],
        filter_columns: {id: :in, status: %i[equal in]},
        filters: %i[open overdue]
      },
      show: %i[id name status]
    }
    config.expose(:update, columns: %i[name status])

    assert config.exposed?(:list)
    refute config.exposed?(:delete)
    assert config.exposed?(:update)
    assert_equal %i[id name status], config.settings_for(:list)[:columns]
    assert_equal({id: :in, status: %i[equal in]}, config.settings_for(:list)[:filter_columns])
    assert_equal %i[open overdue], config.settings_for(:list)[:filters]
    assert_equal({columns: %i[id name status]}, config.settings_for(:show))
    assert_equal({columns: %i[name status]}, config.settings_for(:update))
  end

  def test_mcp_config_inherits_resource_name_and_plural_label_from_core
    model_name = Struct.new(:route_key).new("desk_cases")
    core = Struct.new(:model_id, :model) do
      def label(options)
        raise "expected plural label" unless options == {count: 2}

        "Desk cases"
      end
    end.new(:desk_cases, Struct.new(:model_name).new(model_name))
    config = ActiveScaffold::Config::MCP.new(core)

    assert_equal "desk_cases", config.name
    assert_equal "Desk cases", config.label

    config.name = :tickets
    config.label = "Support tickets"

    assert_equal "tickets", config.name
    assert_equal "Support tickets", config.label
  end

  def test_action_modules_are_validated_and_normalized
    extension = Module.new
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)

    config.expose(:list, modules: extension)

    assert_equal [extension], config.settings_for(:list)[:modules]
    assert_raises(ActiveScaffold::MCP::SettingsValidator::InvalidSetting) do
      config.list.modules = [extension, Object.new]
    end
  end

  def test_tool_name_and_label_are_common_settings
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)

    config.expose :list,
                  name: :list_tickets,
                  label: :Tickets,
                  description: :"Search the support ticket queue"

    assert_equal "list_tickets", config.list.name
    assert_equal "Tickets", config.list.label
    assert_equal "Search the support ticket queue", config.list.description
    assert_raises(ActiveScaffold::MCP::SettingsValidator::InvalidSetting) do
      config.show.name = ""
    end
  end

  def test_per_action_dsl_writes_to_actions_hash
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)

    config.list.columns = %i[id name]
    config.list.filters = :all
    config.list.search = false
    config.show.columns = %i[id name description]
    config.show.lookup_columns = %i[case_number]

    assert_equal %i[id name], config.actions.dig(:list, :columns)
    assert_equal :all, config.actions.dig(:list, :filters)
    assert_equal false, config.list.search
    assert_equal %i[id name description], config.show.columns
    assert_equal %i[case_number], config.show.lookup_columns
    assert_raises(ActiveScaffold::MCP::SettingsValidator::InvalidSetting) { config.list.search = :auto }
  end

  def test_custom_action_settings_are_validated_when_validator_defines_a_method
    validations = 0
    validator_class = Class.new(ActiveScaffold::MCP::SettingsValidator) do
      define_method(:valid_settings_for_publish?) do |setting, _value|
        validations += 1
        setting == :notify
      end
      private :valid_settings_for_publish?
    end
    previous_validator = ActiveScaffold::Config::MCP.settings_validator
    ActiveScaffold::Config::MCP.settings_validator = validator_class
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)
    config.actions = {publish: {}}

    config.publish.notify = true
    assert config.publish.notify
    assert_equal 1, validations
    assert_raises(ActiveScaffold::MCP::SettingsValidator::InvalidSetting) do
      config.publish.columns = %i[id]
    end
  ensure
    ActiveScaffold::Config::MCP.settings_validator = previous_validator
  end

  def test_unknown_custom_action_accepts_settings_by_default
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)
    config.actions = {archive: {retention_days: 30}}

    assert_equal 30, config.archive.retention_days
  end

  def test_expose_yields_config_for_an_unknown_custom_action
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)

    returned_config = config.expose :sepa_mandate do |action|
      action.columns = %i[account creditor_identifier]
      action.description = "Create a SEPA mandate"
    end

    assert_instance_of ActiveScaffold::MCP::ActionConfig, returned_config
    assert_equal :sepa_mandate, returned_config.action_name
    assert config.exposed?(:sepa_mandate)
    assert_equal %i[account creditor_identifier], config.actions.dig(:sepa_mandate, :columns)
    assert_equal "Create a SEPA mandate", config.actions.dig(:sepa_mandate, :description)
  end

  def test_expose_block_configures_common_action_defaults
    previous_actions = ActiveScaffold::Config::MCP.actions

    ActiveScaffold.defaults do |config|
      config.mcp.expose :list do |action|
        action.columns = %i[id name]
        action.filters = :all
      end
    end

    assert_equal %i[id name], ActiveScaffold::Config::MCP.actions.dig(:list, :columns)
    assert_equal :all, ActiveScaffold::Config::MCP.actions.dig(:list, :filters)
  ensure
    ActiveScaffold::Config::MCP.actions = previous_actions
  end

  def test_hash_defaults_are_validated_when_assigned
    previous_actions = ActiveScaffold::Config::MCP.actions

    assert_raises(ActiveScaffold::MCP::SettingsValidator::InvalidSetting) do
      ActiveScaffold::Config::MCP.actions = {show: {filters: :all}}
    end
  ensure
    ActiveScaffold::Config::MCP.actions = previous_actions
  end

  def test_controller_config_deep_copies_global_actions
    previous_actions = ActiveScaffold::Config::MCP.actions
    ActiveScaffold::Config::MCP.actions = {
      list: {filter_columns: {status: %i[equal]}}
    }
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)

    config.actions.dig(:list, :filter_columns, :status) << :in

    assert_equal %i[equal], ActiveScaffold::Config::MCP.actions.dig(:list, :filter_columns, :status)
  ensure
    ActiveScaffold::Config::MCP.actions = previous_actions
  end

  def test_resolved_settings_validator_is_cached
    initializations = 0
    validator_class = Class.new(ActiveScaffold::MCP::SettingsValidator) do
      define_method(:initialize) { initializations += 1 }
    end
    previous_validator = ActiveScaffold::Config::MCP.settings_validator
    ActiveScaffold::Config::MCP.settings_validator = validator_class

    first = ActiveScaffold::Config::MCP.resolved_settings_validator
    second = ActiveScaffold::Config::MCP.resolved_settings_validator

    assert_same first, second
    assert_equal 1, initializations
  ensure
    ActiveScaffold::Config::MCP.settings_validator = previous_validator
  end

  def test_filter_column_sets_are_class_defaults_for_list
    previous_sets = ActiveScaffold::Config::MCP.filter_column_sets
    ActiveScaffold::Config::MCP.filter_columns_sets = {foreign_keys: :in, timestamps: :range}
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)
    config.actions = {list: {columns: %i[id name]}}

    assert_equal(
      {foreign_keys: :in, timestamps: :range},
      config.settings_for(:list)[:filter_column_sets]
    )
  ensure
    ActiveScaffold::Config::MCP.filter_column_sets = previous_sets
  end

  def test_filter_column_sets_require_explicit_operators
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)

    error = assert_raises(ArgumentError) do
      config.expose :list, filter_column_sets: %i[foreign_keys timestamps]
    end

    assert_includes error.message, "filter_column_sets must be a hash"
    assert_includes error.message, "{foreign_keys: :in, timestamps: :range}"
  end

  def test_defaults_block_and_class_action_dsl
    previous_actions = ActiveScaffold::Config::MCP.actions
    previous_sets = ActiveScaffold::Config::MCP.filter_column_sets

    ActiveScaffold.defaults do |config|
      config.mcp.filter_column_sets = {foreign_keys: :in}
      config.mcp.list.columns = %i[id name]
    end

    assert_equal({foreign_keys: :in}, ActiveScaffold::Config::MCP.filter_column_sets)
    assert_equal %i[id name], ActiveScaffold::Config::MCP.actions.dig(:list, :columns)
  ensure
    ActiveScaffold::Config::MCP.actions = previous_actions
    ActiveScaffold::Config::MCP.filter_column_sets = previous_sets
  end

  def test_all_actions_can_be_exposed
    core = Struct.new(:model_id).new(:customers)
    config = ActiveScaffold::Config::MCP.new(core)

    config.exposed_actions = :all

    assert config.exposed?(:list)
    assert config.exposed?(:custom_action)
  end

  def test_including_action_module_calls_the_tool_generator
    calls = []
    action_config = Object.new
    scaffold_config = Struct.new(:mcp).new(action_config)
    controller = Class.new do
      define_singleton_method(:active_scaffold_config) { scaffold_config }
    end
    previous_generator = ActiveScaffold::Config::MCP.tool_generator
    generator = Object.new
    generator.define_singleton_method(:generate_tools_for) { |*args| calls << args }
    ActiveScaffold::Config::MCP.tool_generator = generator

    controller.include ActiveScaffold::Actions::MCP

    assert_equal [[controller, action_config]], calls
  ensure
    ActiveScaffold::Config::MCP.tool_generator = previous_generator
  end

  def test_generator_factory_prefers_explicit_action_generator
    generated_arguments = []
    explicit_generator = Object.new
    explicit_generator.define_singleton_method(:generate_tool_for) do |**arguments|
      generated_arguments << arguments
      :list_tool
    end
    fallback_generator = generator_returning(:fallback_tool)
    factory = ActiveScaffold::MCP::GeneratorFactory.new
    factory.register(fallback_generator, actions: :show)
    factory.register(explicit_generator, actions: :list)
    core = generator_factory_core(
      list: generator_factory_action_config(:read, %i[id name]),
      show: generator_factory_action_config(:read, %i[id name])
    )
    mcp_config = generator_factory_mcp_config(core, list: {}, show: {})

    tools = factory.generate_tools_for(Class.new, mcp_config)

    assert_equal %i[list_tool fallback_tool], tools
    assert_equal :list, generated_arguments.first[:action_name]
    assert_same mcp_config, generated_arguments.first[:mcp_config]
  end

  def test_generator_factory_registers_builtin_show_generator
    generators = ActiveScaffold::MCP::GeneratorFactory.new.instance_variable_get(:@action_generators)

    assert_same ActiveScaffold::MCP::ShowToolGenerator, generators[:show]
  end

  def test_generator_factory_skips_exposed_actions_disabled_in_the_scaffold
    generator = Object.new
    generator.define_singleton_method(:generate_tool_for) { |**| flunk "list generator must not be called" }
    factory = ActiveScaffold::MCP::GeneratorFactory.new
    factory.register(generator, actions: :list)
    core = generator_factory_core(show: generator_factory_action_config(:read, %i[id name]))
    mcp_config = generator_factory_mcp_config(core, list: {})

    assert_empty factory.generate_tools_for(Class.new, mcp_config)
  end

  def test_generator_factory_selects_most_specific_crud_rule
    factory = ActiveScaffold::MCP::GeneratorFactory.new
    factory.register_default(generator_returning(:generic_tool))
    factory.register_default(generator_returning(:read_columns_tool), crud_type: :read, columns: true)
    core = generator_factory_core(details: generator_factory_action_config(:read, %i[id name]))
    mcp_config = generator_factory_mcp_config(core, details: {})

    assert_equal [:read_columns_tool], factory.generate_tools_for(Class.new, mcp_config)
  end

  def test_generator_factory_supports_future_custom_action_rules
    custom_config = Struct.new(:submit_method, :columns, :destructive).new(:post, %i[reason], true)
    core = generator_factory_core({}, custom_actions: {archive: custom_config})
    mcp_config = generator_factory_mcp_config(core, archive: {})
    factory = ActiveScaffold::MCP::GeneratorFactory.new
    factory.register_custom(
      generator_returning(:destructive_form_tool),
      submit_method: :post,
      columns: true,
      destructive: true
    )

    assert_equal [:destructive_form_tool], factory.generate_tools_for(Class.new, mcp_config)
  end

  def test_list_tool_generator_builds_filter_schema_and_active_scaffold_params
    id_column = Struct.new(:name, :type).new("id", :integer)
    customer_column = Struct.new(:name, :type).new("customer_id", :integer)
    company_column = Struct.new(:name, :type).new("company_id", :integer)
    company_type_column = Struct.new(:name, :type).new("company_type", :string)
    created_column = Struct.new(:name, :type).new("created_at", :datetime)
    model_name = Struct.new(:route_key) do
      def human(count:)
        count == 2 ? "Widgets" : "Widget"
      end
    end.new("widgets")
    model = Struct.new(:model_name).new(model_name)
    reflection = Struct.new(:foreign_key, :foreign_type) do
      def polymorphic?
        true
      end
    end.new("company_id", "company_type")
    model.define_singleton_method(:reflect_on_all_associations) do |macro|
      macro == :belongs_to ? [reflection] : []
    end
    core = Struct.new(:model, :_columns_hash, :actions).new(
      model,
      {
        "id" => id_column,
        "customer_id" => customer_column,
        "company_id" => company_column,
        "company_type" => company_type_column,
        "created_at" => created_column
      },
      [:list]
    )
    configure_active_record_core(core)
    mcp_config = list_mcp_config(core)
    action_config = Struct.new(:per_page, :filters).new(20, [])
    settings = {
      columns: %i[id created_at],
      filter_columns: {id: %i[equal in], created_at: :between},
      filter_column_sets: {foreign_keys: :in}
    }

    controller_class = Class.new
    tool_class = ActiveScaffold::MCP::ListToolGenerator.generate_tool_for(
      controller_class: controller_class,
      action_name: :list,
      action_config: action_config,
      mcp_config: mcp_config,
      settings: settings
    )

    assert_operator tool_class, :<, ActiveScaffold::MCP::ListTool
    assert_same controller_class, tool_class.active_scaffold_controller_class
    assert_includes tool_class.ancestors, ActiveScaffold::Actions::List
    assert_equal "list_widgets", tool_class.tool_name
    assert_equal(
      %w[id id_in created_at_from created_at_to customer_id_in company_id_in company_type_in limit page],
      tool_class._schema_properties.keys
    )

    tool = tool_class.new(
      id_in: [1, 2],
      created_at_from: "2026-01-01T00:00:00Z",
      created_at_to: "2026-01-31T23:59:59Z",
      customer_id_in: [3, 4],
      company_id_in: [5],
      company_type_in: ["Customer"]
    )
    assert_equal [1, 2], tool.params[:id]
    assert_equal "2026-01-01T00:00:00Z..2026-01-31T23:59:59Z", tool.params[:created_at]
    assert_equal [3, 4], tool.params[:customer_id]
    assert_equal [5], tool.params[:company_id]
    assert_equal ["Customer"], tool.params[:company_type]
  end

  def test_list_tool_generator_exposes_named_filter_without_an_extra_prefix
    filter = ActiveScaffold::DataStructures::Filter.new(:filter_status, :select)
    filter.add(:not_closed)
    tool_class = build_list_tool_class(filters: :all, action_filters: [filter])

    assert_includes tool_class._schema_properties.keys, "filter_status"
    refute_includes tool_class._schema_properties.keys, "filter_filter_status"
    assert_includes tool_class.description, "named list filters"
    assert_equal(
      "Apply the filter_status list filter. When omitted, the server uses the default option 'not_closed'",
      tool_class._schema_properties.dig("filter_status", :description)
    )
    assert_equal "not_closed", tool_class.new(filter_status: "not_closed").params[:filter_status]
  end

  def test_list_tool_generator_warns_when_named_filter_may_be_disallowed
    filter = ActiveScaffold::DataStructures::Filter.new(:filter_status, :select)
    filter.description = "Choose which records to list"
    filter.add(:open)
    filter.add(:all, security_method: :all_allowed?)

    tool_class = build_list_tool_class(filters: :all, action_filters: [filter])

    assert_equal(
      "Choose which records to list. When omitted, the server uses the default option 'open'. " \
      "These options may be disallowed in the current context: all",
      tool_class._schema_properties.dig("filter_status", :description)
    )

    filter.define_singleton_method(:security_method_set?) { true }
    tool_class = build_list_tool_class(filters: :all, action_filters: [filter])
    assert_equal(
      "Choose which records to list. When omitted, the server uses the default option 'open'. " \
      "This filter may be disallowed in the current context",
      tool_class._schema_properties.dig("filter_status", :description)
    )
  end

  def test_list_tool_generator_rejects_named_filter_conflicting_with_a_column_filter
    option = Struct.new(:name).new(:open)
    filter = Struct.new(:name, :description, :default_option, :options) do
      include Enumerable

      def each(&block)
        options.each(&block)
      end
    end.new(:id, nil, :open, [option])

    error = assert_raises(ArgumentError) do
      build_list_tool_class(filter_columns: {id: :equal}, filters: :all, action_filters: [filter])
    end
    assert_includes error.message, "conflicts with an MCP column filter"
  end

  def test_show_tool_generator_builds_required_primary_key_schema_and_params
    tool_class = build_show_tool_class(columns: %i[id name])

    assert_operator tool_class, :<, ActiveScaffold::MCP::ShowTool
    assert_includes tool_class.ancestors, ActiveScaffold::Actions::Show
    assert_equal "show_widget", tool_class.tool_name
    assert_equal "Show Widget", tool_class.title
    assert_equal %w[id], tool_class._schema_properties.keys
    assert_equal ["id"], tool_class._required_properties
    assert_equal "integer", tool_class._schema_properties.dig("id", :type)
    assert_equal 7, tool_class.new(id: 7).params[:id]
  end

  def test_show_tool_uses_shared_record_serialization
    column = Struct.new(:name, :association).new(:name, nil)
    record = Struct.new(:name) do
      def authorized_for?(_options)
        true
      end
    end.new("Widget 7")
    rendered = nil
    tool = build_show_tool_class.new(id: 7)
    tool.define_singleton_method(:do_show) { @record = record }
    tool.define_singleton_method(:mcp_output_columns) { [column] }
    tool.define_singleton_method(:render) { |text:| rendered = JSON.parse(text) }

    tool.perform

    assert_equal({"record" => {"name" => "Widget 7"}}, rendered)
  end

  def test_show_tool_flattens_grouped_output_columns
    column = Struct.new(:name, :association).new(:name, nil)
    action_columns = Object.new
    action_columns.define_singleton_method(:visible_columns) do |options = {}|
      options[:flatten] ? [column] : [self]
    end
    config = Struct.new(:show).new(Struct.new(:columns).new(action_columns))
    tool = build_show_tool_class.new(id: 7)
    tool.define_singleton_method(:active_scaffold_config) { config }

    assert_equal [column], tool.send(:mcp_default_output_columns)
  end

  def test_show_tool_generator_supports_exactly_one_lookup_column
    tool_class = build_show_tool_class(columns: %i[name], lookup_columns: %i[case_number])

    assert_equal %w[id case_number], tool_class._schema_properties.keys
    assert_empty tool_class._required_properties
    assert_includes tool_class.description, "by id or case number"
    assert_includes tool_class.description, "exactly one of `id` or `case_number`"
    assert_equal "Case number of the Widget to return", tool_class._schema_properties.dig("case_number", :description)
    refute tool_class.new.valid?
    refute tool_class.new(id: 7, case_number: "S0000007").valid?
    assert tool_class.new(case_number: "S0000007").valid?
    assert_equal "S0000007", tool_class.new(case_number: "S0000007").params[:case_number]
  end

  def test_show_lookup_columns_use_shared_json_schema_types_and_formats
    tool_class = build_show_tool_class(lookup_columns: %i[active reported_at])

    assert_equal "boolean", tool_class._schema_properties.dig("active", :type)
    assert_equal "string", tool_class._schema_properties.dig("reported_at", :type)
    assert_equal "date-time", tool_class._schema_properties.dig("reported_at", :format)
  end

  def test_show_tool_resolves_lookup_column_to_primary_key
    where_arguments = []
    relation = Object.new
    relation.define_singleton_method(:where) { |arguments| where_arguments << arguments; relation }
    relation.define_singleton_method(:limit) { |value| raise "unexpected limit" unless value == 2; relation }
    relation.define_singleton_method(:pluck) { |column| raise "unexpected primary key" unless column == :id; [7] }
    resolved_id = nil
    rendered = nil
    tool = build_show_tool_class(lookup_columns: %i[case_number]).new(case_number: "S0000007")
    tool.define_singleton_method(:beginning_of_chain) { relation }
    tool.define_singleton_method(:filtered_query) { flunk "lookup resolution must not apply list filters" }
    tool.define_singleton_method(:do_show) do
      resolved_id = params[:id]
      @record = Object.new
    end
    tool.define_singleton_method(:mcp_output_columns) { [] }
    tool.define_singleton_method(:render) { |text:| rendered = JSON.parse(text) }

    tool.perform

    assert_equal [{case_number: "S0000007"}], where_arguments
    assert_equal 7, resolved_id
    assert_equal({"record" => {}}, rendered)
  end

  def test_show_tool_reports_an_ambiguous_lookup_to_mcp
    relation = Object.new
    relation.define_singleton_method(:where) { |_arguments| relation }
    relation.define_singleton_method(:limit) { |_value| relation }
    relation.define_singleton_method(:pluck) { |_column| [7, 8] }
    tool = build_show_tool_class(lookup_columns: %i[case_number]).new(case_number: "duplicate")
    tool.define_singleton_method(:beginning_of_chain) { relation }
    tool.define_singleton_method(:do_show) { flunk "show must not run for an ambiguous lookup" }
    tool.define_singleton_method(:with_active_scaffold_context) { |&block| block.call }

    response = tool.call

    assert response.error?
    assert_equal true, response.to_h[:isError]
    assert_includes response.to_h.dig(:content, 0, :text), "More than one record found for case_number"
    assert_includes response.to_h.dig(:content, 0, :text), "use id instead"
  end

  def test_show_tool_reports_a_missing_lookup_to_mcp
    relation = Object.new
    relation.define_singleton_method(:where) { |_arguments| relation }
    relation.define_singleton_method(:limit) { |_value| relation }
    relation.define_singleton_method(:pluck) { |_column| [] }
    tool = build_show_tool_class(lookup_columns: %i[case_number]).new(case_number: "missing")
    tool.define_singleton_method(:beginning_of_chain) { relation }
    tool.define_singleton_method(:do_show) { flunk "show must not run for a missing lookup" }
    tool.define_singleton_method(:with_active_scaffold_context) { |&block| block.call }

    response = tool.call

    assert response.error?
    assert_equal true, response.to_h[:isError]
    assert_includes response.to_h.dig(:content, 0, :text), "No record found for case_number"
  end

  def test_show_tool_reports_a_missing_id_to_mcp
    tool = build_show_tool_class.new(id: 99)
    tool.define_singleton_method(:do_show) { raise ActiveRecord::RecordNotFound }
    tool.define_singleton_method(:with_active_scaffold_context) { |&block| block.call }

    response = tool.call

    assert response.error?
    assert_equal true, response.to_h[:isError]
    assert_includes response.to_h.dig(:content, 0, :text), "No record found for id 99"
  end

  def test_show_tool_applies_show_authorization
    tool = build_show_tool_class.new(id: 7)
    tool.define_singleton_method(:show_authorized?) { false }

    refute tool.send(:tool_authorized?)
  end

  def test_list_tool_generator_includes_shared_action_modules_after_list
    extension = Module.new do
      def list_authorized?
        false
      end

      def conditions_for_collection
        {account_id: current_user.account_id}
      end
    end
    tool_class = build_list_tool_class(modules: [extension])
    tool = tool_class.new

    refute tool.send(:list_authorized?)
    refute tool.send(:tool_authorized?)
    assert_operator tool_class.ancestors.index(extension), :<,
                    tool_class.ancestors.index(ActiveScaffold::Actions::List)
  end

  def test_list_tool_generator_includes_config_list_and_uses_its_list_columns
    config_list_module = Module.new do
      def list_columns
        [:config_list_column]
      end
    end
    ActiveScaffold::Actions.const_set(:ConfigList, config_list_module)

    tool_class = build_list_tool_class(config_list_action: true)

    assert_includes tool_class.ancestors, config_list_module
    assert_operator tool_class.ancestors.index(config_list_module), :<,
                    tool_class.ancestors.index(ActiveScaffold::Actions::List)
    assert_equal [:config_list_column], tool_class.new.send(:mcp_default_output_columns)
  ensure
    if defined?(config_list_module) && ActiveScaffold::Actions.const_defined?(:ConfigList, false) &&
        ActiveScaffold::Actions.const_get(:ConfigList, false).equal?(config_list_module)
      ActiveScaffold::Actions.send(:remove_const, :ConfigList)
    end
  end

  def test_list_tool_generator_uses_configured_name_and_label
    tool_class = build_list_tool_class(name: "list_tickets", label: "Support tickets")

    assert_equal "list_tickets", tool_class.tool_name
    assert_equal "List Support tickets", tool_class.title
    assert_equal "List Support tickets as a paginated collection. Use limit and page for pagination.", tool_class.description
    assert_equal "List Support tickets", tool_class.to_h.dig(:annotations, "title")
  end

  def test_list_tool_generator_uses_mcp_resource_name_and_label
    tool_class = build_list_tool_class(mcp_name: "tickets", mcp_label: "Support tickets")

    assert_equal "list_tickets", tool_class.tool_name
    assert_equal "List Support tickets", tool_class.title
  end

  def test_list_tool_description_summarizes_supported_filter_arguments
    tool_class = build_list_tool_class(filter_columns: {id: :equal})

    assert_equal(
      "List Widgets as a paginated collection. Supports column filters. Use limit and page for pagination.",
      tool_class.description
    )
  end

  def test_list_tool_generator_adds_search_when_active_scaffold_search_is_enabled
    tool_class = build_list_tool_class(search_action: true)

    assert_includes tool_class.ancestors, ActiveScaffold::Actions::Search
    assert_equal "%?%", tool_class.like_pattern(:full)
    assert_includes tool_class._schema_properties.keys, "search"
    assert_equal(
      "Search text across Case number and Summary",
      tool_class._schema_properties.dig("search", :description)
    )
    assert_equal "router", tool_class.new(search: "router").params[:search]
    assert_includes tool_class.description, "full-text search"
    assert_includes tool_class.description, "Search text across Case number and Summary"
  end

  def test_list_tool_search_can_be_disabled_for_mcp
    tool_class = build_list_tool_class(search_action: true, search: false)

    refute_includes tool_class.ancestors, ActiveScaffold::Actions::Search
    refute_includes tool_class._schema_properties.keys, "search"
  end

  def test_list_tool_prepares_search_before_listing_when_search_is_provided
    pager = Struct.new(:count, :number_of_pages).new(0, 0)
    page = Struct.new(:number, :pager).new(1, pager)
    calls = []
    tool = build_list_tool_class(search_action: true).new(search: "router")
    tool.define_singleton_method(:store_search_params_into_session) { calls << :store_search }
    tool.define_singleton_method(:do_search) { calls << :search }
    tool.define_singleton_method(:do_list) do
      calls << :list
      @page = page
      @records = []
    end
    tool.define_singleton_method(:mcp_output_columns) { [] }
    tool.define_singleton_method(:render) { |text:| JSON.parse(text) }

    tool.perform

    assert_equal %i[store_search search list], calls
  end

  def test_list_tool_provides_active_scaffold_session_storage_for_search
    tool = build_list_tool_class(search_action: true).new(search: "router")
    config = Struct.new(:store_user_settings).new(true)
    tool.define_singleton_method(:active_scaffold_config) { config }
    tool.define_singleton_method(:session) { Object.new }

    tool.send(:store_search_params_into_session)

    assert_equal "router", tool.send(:search_params)
    refute tool.params.key?(:search)
  end

  def test_list_tool_checks_search_authorization_only_for_a_search_call
    tool_class = build_list_tool_class(search_action: true)
    search_tool = tool_class.new(search: "router")
    search_tool.define_singleton_method(:list_authorized?) { true }
    search_tool.define_singleton_method(:search_authorized?) { false }
    refute search_tool.send(:tool_authorized?)

    list_tool = tool_class.new
    list_tool.define_singleton_method(:list_authorized?) { true }
    list_tool.define_singleton_method(:search_authorized?) { flunk "search authorization must not be checked" }
    assert list_tool.send(:tool_authorized?)
  end

  def test_list_tool_generator_uses_configured_description
    tool_class = build_list_tool_class(
      label: "Tickets",
      description: "Find support tickets using queue filters and pagination."
    )

    assert_equal "List Tickets", tool_class.title
    assert_equal "Find support tickets using queue filters and pagination.", tool_class.description
  end

  def test_list_tool_returns_total_count_and_total_pages
    pager = Struct.new(:count, :number_of_pages).new(57, 3)
    page = Struct.new(:number, :pager).new(2, pager)
    rendered = nil
    tool = build_list_tool_class.new
    tool.define_singleton_method(:do_list) do
      @page = page
      @records = []
    end
    tool.define_singleton_method(:mcp_output_columns) { [] }
    tool.define_singleton_method(:render) { |text:| rendered = JSON.parse(text) }

    tool.perform

    assert_equal [], rendered.fetch("records")
    assert_equal 2, rendered.fetch("page")
    assert_equal 57, rendered.fetch("total_count")
    assert_equal 3, rendered.fetch("total_pages")
  end

  def test_list_tool_reports_requested_filters_disallowed_by_active_scaffold
    filter = ActiveScaffold::DataStructures::Filter.new(:filter, :select)
    filter.add(:all)
    used_filter = ActiveScaffold::DataStructures::Filter.new(:used_filter, :select)
    used_filter.add(:all)
    tool = build_list_tool_class(filters: :all, action_filters: [filter, used_filter]).new(
      filter: "all",
      used_filter: "all"
    )
    tool.define_singleton_method(:do_list) do
      @filter_states = {
        filter: {option: filter[:all], status: :applied, default: true, requested: true},
        used_filter: {option: used_filter[:all], status: :disallowed, default: true, requested: true}
      }
    end
    tool.define_singleton_method(:mcp_output_columns) { flunk "disallowed results must not be serialized" }
    tool.define_singleton_method(:with_active_scaffold_context) { |&block| block.call }

    response = tool.call

    assert response.error?
    assert_equal true, response.to_h[:isError]
    assert_includes response.to_h.dig(:content, 0, :text), '`used_filter="all"`'
    assert_includes response.to_h.dig(:content, 0, :text), "No records were returned"
    assert_includes response.to_h.dig(:content, 0, :text), "only `used_filter` omitted"
    assert_includes response.to_h.dig(:content, 0, :text), "keep all other arguments unchanged"
    assert_includes response.to_h.dig(:content, 0, :text), "may be allowed with different arguments"
  end

  def test_list_tool_reports_default_filter_disallowed_by_active_scaffold
    filter = ActiveScaffold::DataStructures::Filter.new(:filter, :select)
    filter.add(:all)
    used_filter = ActiveScaffold::DataStructures::Filter.new(:used_filter, :select)
    used_filter.add(:used)
    tool = build_list_tool_class(filters: :all, action_filters: [filter, used_filter]).new(filter: "all")
    pager = Struct.new(:count, :number_of_pages).new(0, 0)
    page = Struct.new(:number, :pager).new(1, pager)
    rendered = nil
    tool.define_singleton_method(:do_list) do
      @filter_states = {
        filter: {option: filter[:all], status: :applied, default: true, requested: true},
        used_filter: {option: used_filter[:used], status: :disallowed, default: true, requested: false}
      }
      @page = page
      @records = []
    end
    tool.define_singleton_method(:mcp_output_columns) { [] }
    tool.define_singleton_method(:report_error) { |message| flunk "unexpected error: #{message}" }
    tool.define_singleton_method(:render) { |text:| rendered = JSON.parse(text) }

    tool.perform

    assert_equal [], rendered.fetch("records")
    assert_equal 0, rendered.fetch("total_count")
  end

  def test_list_tool_disables_controller_conditional_get_support
    tool = build_list_tool_class.new

    refute tool.send(:conditional_get_support?)
    refute_respond_to tool, :request
  end

  def test_list_tool_filters_class_and_record_authorized_output_columns
    tool_class = build_list_tool_class(columns: %i[id secret])
    model = Object.new
    model.define_singleton_method(:authorized_for?) { |options| options[:column] == :id }
    model.define_singleton_method(:primary_key) { :id }
    column_class = Struct.new(:name, :association)
    id_column = column_class.new(:id, nil)
    secret_column = column_class.new(:secret, nil)
    config = Struct.new(:model, :columns).new(model, {id: id_column, secret: secret_column})
    tool = tool_class.new
    tool.define_singleton_method(:active_scaffold_config) { config }

    assert_equal [id_column], tool.send(:mcp_output_columns)

    record = Struct.new(:id, :secret) do
      def authorized_for?(options)
        options[:column] == :id
      end

      def has_attribute?(name)
        %i[id secret].include?(name.to_sym)
      end
    end.new(1, "private")
    assert_equal({id: 1}, tool.send(:mcp_record_hash, record, [id_column, secret_column]))
  end

  def test_output_columns_always_include_the_primary_key
    tool_class = build_list_tool_class(columns: %i[name])
    model = Object.new
    model.define_singleton_method(:authorized_for?) { |_options| true }
    model.define_singleton_method(:primary_key) { :id }
    column_class = Struct.new(:name, :association)
    id_column = column_class.new(:id, nil)
    name_column = column_class.new(:name, nil)
    config = Struct.new(:model, :columns).new(model, {id: id_column, name: name_column})
    tool = tool_class.new
    tool.define_singleton_method(:active_scaffold_config) { config }

    assert_equal [id_column, name_column], tool.send(:mcp_output_columns)
  end

  def test_list_tool_serializes_singular_and_collection_associations_as_id_and_label
    association_class = Struct.new(:name, :collection?, :polymorphic?)
    column_class = Struct.new(:name, :association)
    singular_column = column_class.new(:customer, association_class.new(:customer, false, false))
    collection_column = column_class.new(:tags, association_class.new(:tags, true, false))
    collection_column.define_singleton_method(:associated_limit) { nil }
    collection_column.define_singleton_method(:associated_number?) { true }
    associated_record_class = Struct.new(:id, :label) do
      def to_label
        label
      end
    end
    customer = associated_record_class.new(7, "Acme")
    tags = [associated_record_class.new(2, "Important"), associated_record_class.new(3, "Open")]
    record = Struct.new(:customer, :tags) do
      def authorized_for?(_options)
        true
      end
    end.new(customer, tags)
    tool = build_list_tool_class.new

    assert_equal(
      {
        customer: {id: 7, label: "Acme"},
        tags: [{id: 2, label: "Important"}, {id: 3, label: "Open"}]
      },
      tool.send(:mcp_record_hash, record, [singular_column, collection_column])
    )
    assert_equal(
      {customer: nil, tags: []},
      tool.send(:mcp_record_hash, record.class.new(nil, []), [singular_column, collection_column])
    )
  end

  def test_collection_associations_honor_associated_limit_and_number
    association = Struct.new(:name, :collection?).new(:tags, true)
    column = Struct.new(:name, :association, :associated_limit, :associated_number?).new(:tags, association, 2, true)
    associated_record_class = Struct.new(:id, :label) do
      def to_label
        label
      end
    end
    tags = [
      associated_record_class.new(2, "Important"),
      associated_record_class.new(3, "Open"),
      associated_record_class.new(4, "Customer visible")
    ]
    record = Struct.new(:id, :tags) do
      def authorized_for?(_options)
        true
      end
    end.new(1, tags)

    assert_equal(
      {
        tags: {
          first_records: [{id: 2, label: "Important"}, {id: 3, label: "Open"}],
          count: 3
        }
      },
      build_list_tool_class.new.send(:mcp_record_hash, record, [column])
    )
  end

  def test_collection_associations_can_return_only_the_cached_count
    association = Struct.new(:name, :collection?, :primary_key).new(:tags, true, :account_id)
    column = Struct.new(:name, :association, :associated_limit, :associated_number?).new(:tags, association, 0, true)
    record = Struct.new(:id, :account_id, :tags) do
      def authorized_for?(_options)
        true
      end
    end.new(1, 9, Object.new)
    tool = build_list_tool_class.new
    tool.instance_variable_set(:@counts, {tags: {9 => 37}})
    tool.define_singleton_method(:count_on_association_class?) { |_column| true }

    assert_equal({tags: 37}, tool.send(:mcp_record_hash, record, [column]))
  end

  def test_positive_associated_limit_does_not_load_the_whole_collection
    association = Struct.new(:name, :collection?).new(:tags, true)
    column = Struct.new(:name, :association, :associated_limit, :associated_number?).new(:tags, association, 2, false)
    associated_record = Struct.new(:id) do
      def to_label
        "Tag #{id}"
      end
    end
    limited_relation = Object.new
    limited_relation.define_singleton_method(:to_a) do
      [associated_record.new(1), associated_record.new(2), associated_record.new(3)]
    end
    collection = Object.new
    collection.define_singleton_method(:loaded?) { false }
    collection.define_singleton_method(:limit) do |limit|
      raise "unexpected limit" unless limit == 3

      limited_relation
    end
    collection.define_singleton_method(:map) { raise "the whole collection must not be loaded" }
    record = Struct.new(:tags) do
      def authorized_for?(_options)
        true
      end
    end.new(collection)

    assert_equal(
      {
        tags: {
          first_records: [{id: 1, label: "Tag 1"}, {id: 2, label: "Tag 2"}],
          count: ">2"
        }
      },
      build_list_tool_class.new.send(:mcp_record_hash, record, [column])
    )
  end

  def test_positive_associated_limit_reports_when_all_records_were_loaded_without_counting
    association = Struct.new(:name, :collection?).new(:tags, true)
    column = Struct.new(:name, :association, :associated_limit, :associated_number?).new(:tags, association, 3, false)
    associated_record = Struct.new(:id) do
      def to_label
        "Tag #{id}"
      end
    end
    record = Struct.new(:tags) do
      def authorized_for?(_options)
        true
      end
    end.new([associated_record.new(1), associated_record.new(2)])

    assert_equal(
      {
        tags: {
          records: [{id: 1, label: "Tag 1"}, {id: 2, label: "Tag 2"}],
          count: 2
        }
      },
      build_list_tool_class.new.send(:mcp_record_hash, record, [column])
    )
  end

  def test_polymorphic_singular_association_includes_its_model
    association = Struct.new(:name, :collection?, :polymorphic?).new(:record, false, true)
    column = Struct.new(:name, :association).new(:record, association)
    associated_record_class = Class.new do
      extend ActiveModel::Naming

      attr_reader :id

      def initialize(id)
        @id = id
      end

      def to_label
        "Router 7"
      end
    end
    associated_record_class.define_singleton_method(:name) { "Router" }
    record = Struct.new(:record) do
      def authorized_for?(_options)
        true
      end
    end.new(associated_record_class.new(7))

    assert_equal(
      {record: {id: 7, label: "Router 7", model: "Router"}},
      build_list_tool_class.new.send(:mcp_record_hash, record, [column])
    )
  end

  def test_mcp_uses_tool_generator_interface
    calls = []
    generated_tool = Class.new
    generator = Object.new
    generator.define_singleton_method(:generate_tools_for) do |*args|
      calls << args
      [generated_tool]
    end
    previous_generator = ActiveScaffold::Config::MCP.tool_generator
    ActiveScaffold::Config::MCP.tool_generator = generator
    controller = Class.new
    config = Object.new

    ActiveScaffold::MCP.generate_tools_for(controller, config)

    assert_equal [[controller, config]], calls
    assert_includes ActiveScaffold::MCP.generated_tool_classes, generated_tool
  ensure
    ActiveScaffold::MCP.generated_tool_classes.delete(generated_tool) if generated_tool
    ActiveScaffold::Config::MCP.tool_generator = previous_generator
  end

  def test_mcp_tracks_named_controllers_for_reload
    controller = Class.new
    Object.const_set(:MCPTrackedWidgetsController, controller)
    generator = Object.new
    generator.define_singleton_method(:generate_tools_for) { |_controller, _config| [] }
    previous_generator = ActiveScaffold::Config::MCP.tool_generator
    ActiveScaffold::Config::MCP.tool_generator = generator

    ActiveScaffold::MCP.generate_tools_for(controller, Object.new)

    assert_includes ActiveScaffold::MCP.generated_controller_names, "MCPTrackedWidgetsController"
  ensure
    ActiveScaffold::MCP.generated_controller_names.delete("MCPTrackedWidgetsController")
    ActiveScaffold::Config::MCP.tool_generator = previous_generator
    Object.send(:remove_const, :MCPTrackedWidgetsController) if Object.const_defined?(:MCPTrackedWidgetsController, false)
  end

  def test_mcp_reload_replaces_generated_tools_using_current_controller
    original_tools = ActionMCP::ToolsRegistry.items.dup
    stale_tool = Class.new(ActiveScaffold::MCP::Tool)
    manual_tool = Class.new(ActionMCP::Tool) do
      tool_name "manual_reload_test"
    end
    manual_active_scaffold_tool = Class.new(ActiveScaffold::MCP::Tool) do
      tool_name "manual_active_scaffold_reload_test"
    end
    ActionMCP::ToolsRegistry.clear!
    ActionMCP::ToolsRegistry.register(manual_tool)
    ActionMCP::ToolsRegistry.register(manual_active_scaffold_tool)
    ActionMCP::ToolsRegistry.items["stale"] = stale_tool
    ActiveScaffold::MCP.generated_tool_classes << stale_tool
    ActiveScaffold::MCP.generated_controller_names << "MCPReloadedWidgetsController"

    action_config = Object.new
    active_scaffold_config = Struct.new(:mcp).new(action_config)
    current_controller = Class.new
    current_controller.define_singleton_method(:active_scaffold_config) { active_scaffold_config }
    Object.const_set(:MCPReloadedWidgetsController, current_controller)
    calls = []
    generator = Object.new
    generator.define_singleton_method(:generate_tools_for) do |*arguments|
      calls << arguments
      []
    end
    previous_generator = ActiveScaffold::Config::MCP.tool_generator
    ActiveScaffold::Config::MCP.tool_generator = generator

    ActiveScaffold::MCP.reload_generated_tools!

    assert_equal [[current_controller, action_config]], calls
    assert_same manual_tool, ActionMCP::ToolsRegistry.items["manual_reload_test"]
    assert_same manual_active_scaffold_tool, ActionMCP::ToolsRegistry.items["manual_active_scaffold_reload_test"]
    refute ActionMCP::ToolsRegistry.items.key?("stale")
  ensure
    ActiveScaffold::MCP.generated_controller_names.delete("MCPReloadedWidgetsController")
    ActiveScaffold::MCP.generated_tool_classes.delete(stale_tool) if stale_tool
    ActiveScaffold::Config::MCP.tool_generator = previous_generator
    ActionMCP::ToolsRegistry.clear!
    original_tools&.each_value { |tool_class| ActionMCP::ToolsRegistry.register(tool_class) }
    Object.send(:remove_const, :MCPReloadedWidgetsController) if Object.const_defined?(:MCPReloadedWidgetsController, false)
  end

  def test_configured_base_tool_is_resolved_from_a_class_name_or_callable
    previous_base = ActiveScaffold::Config::MCP.base_tool
    ActiveScaffold::Config::MCP.base_tool = "ActionMCP::Tool"
    assert_same ActionMCP::Tool, ActiveScaffold::Config::MCP.resolve_tool(:base)

    custom_base = Class.new(ActionMCP::Tool)
    ActiveScaffold::Config::MCP.base_tool = -> { custom_base }
    assert_same custom_base, ActiveScaffold::Config::MCP.resolve_tool(:base)
  ensure
    ActiveScaffold::Config::MCP.base_tool = previous_base
  end

  private

  def build_list_tool_class(settings = {})
    settings = settings.dup
    mcp_name = settings.delete(:mcp_name)
    mcp_label = settings.delete(:mcp_label)
    action_filters = settings.delete(:action_filters) || []
    search_action = settings.delete(:search_action)
    config_list_action = settings.delete(:config_list_action)
    column = Struct.new(:name, :type).new("id", :integer)
    model_name = Struct.new(:route_key) do
      def human(count:)
        count == 2 ? "Widgets" : "Widget"
      end
    end.new("widgets")
    model = Struct.new(:model_name, :primary_key).new(model_name, "id")
    search_column = Struct.new(:name, :label)
    configured_search_columns = [
      search_column.new(:case_number, "Case number"),
      search_column.new(:summary, nil)
    ]
    search_columns = Struct.new(:columns) do
      delegate :any?, to: :columns

      def visible_columns(**options)
        raise "search description must not apply authorization" unless options[:skip_authorization]
        raise "search columns must be flattened" unless options[:flatten]

        columns
      end
    end.new(configured_search_columns)
    search_config = Struct.new(:columns).new(search_columns)
    actions = [:list]
    actions << :search if search_action
    actions << :config_list if config_list_action
    core = Struct.new(:model, :_columns_hash, :actions, :search).new(
      model,
      {"id" => column},
      actions,
      search_config
    )
    configure_active_record_core(core)
    mcp_config = list_mcp_config(core, name: mcp_name, label: mcp_label)
    action_config = Struct.new(:per_page, :filters).new(20, action_filters)

    ActiveScaffold::MCP::ListToolGenerator.generate_tool_for(
      controller_class: Class.new,
      action_name: :list,
      action_config: action_config,
      mcp_config: mcp_config,
      settings: settings
    )
  end

  def build_show_tool_class(settings = {})
    settings = settings.dup
    id_column = Struct.new(:name, :type).new("id", :integer)
    case_number_column = Struct.new(:name, :type).new("case_number", :string)
    name_column = Struct.new(:name, :type).new("name", :string)
    active_column = Struct.new(:name, :type).new("active", :boolean)
    reported_at_column = Struct.new(:name, :type).new("reported_at", :datetime)
    model_name = Struct.new(:route_key) do
      def human(count:)
        count == 2 ? "Widgets" : "Widget"
      end
    end.new("widgets")
    model = Struct.new(:model_name, :primary_key).new(model_name, "id")
    model.define_singleton_method(:authorized_for?) { |_options| true }
    core = Struct.new(:model, :_columns_hash, :actions).new(
      model,
      {
        "id" => id_column,
        "case_number" => case_number_column,
        "name" => name_column,
        "active" => active_column,
        "reported_at" => reported_at_column
      },
      [:show]
    )
    configure_active_record_core(core)
    mcp_config = list_mcp_config(core)
    action_config = Struct.new(:columns).new([])

    ActiveScaffold::MCP::ShowToolGenerator.generate_tool_for(
      controller_class: Class.new,
      action_name: :show,
      action_config: action_config,
      mcp_config: mcp_config,
      settings: settings
    )
  end

  def list_mcp_config(core, name: nil, label: nil)
    Struct.new(:core, :name, :label).new(
      core,
      name || core.model.model_name.route_key,
      label || core.model.model_name.human(count: 2)
    )
  end

  def configure_active_record_core(core)
    core.define_singleton_method(:active_record?) { true }
    core.define_singleton_method(:mongoid?) { false }
    core
  end

  def generator_factory_action_config(crud_type, columns)
    Struct.new(:crud_type, :columns).new(crud_type, columns)
  end

  def generator_returning(result)
    Object.new.tap do |generator|
      generator.define_singleton_method(:generate_tool_for) { |**| result }
    end
  end

  def generator_factory_core(configs = {}, custom_actions: nil, **keyword_configs)
    configs = configs.merge(keyword_configs)
    Struct.new(:actions, :custom_actions) do
      define_method(:initialize) do |action_configs, custom|
        @action_configs = action_configs
        super(action_configs.keys, custom)
      end

      define_method(:[]) { |action_name| @action_configs[action_name.to_sym] }
    end.new(configs, custom_actions)
  end

  def generator_factory_mcp_config(core, actions = {}, **keyword_actions)
    actions = actions.merge(keyword_actions)
    Struct.new(:core, :actions) do
      define_method(:settings_for) { |action_name| actions[action_name.to_sym] || {} }
    end.new(core, actions)
  end
end
