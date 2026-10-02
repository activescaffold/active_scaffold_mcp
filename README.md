# ActiveScaffold MCP

`active_scaffold_mcp` generates ActionMCP tools from ActiveScaffold controller configuration.

The gem is under initial development. The first implementation will provide a configuration DSL, a generated-tool registry, and read-only list and show tools.

Association columns use ActiveScaffold's list settings in MCP results. An
unlimited collection (`associated_limit = nil`) is returned as an array. A
positive limit returns `{records: [...], count: N}` when the complete
association fits. A truncated association uses `first_records` instead of
`records`. The count is exact when `associated_number` is enabled; otherwise
MCP loads one extra record and reports a lower bound such as `count: ">3"`.
A zero limit is count-only (or `null` when `associated_number` is disabled).
Singular polymorphic associations also include their human model name as
`model`.

Configure the actions that may become MCP tools in the controller:

```ruby
active_scaffold :ticket do |config|
  config.mcp.actions = {
    list: {
      columns: %i[id subject status customer_id],
      filter_columns: {
        id: %i[equal in between],
        status: %i[equal in]
      },
      filters: %i[open overdue]
    },
    show: {
      columns: %i[subject status description],
      lookup_columns: %i[case_number]
    },
    update: {columns: %i[status description]}
  }
end
```

The same configuration can be written with the per-action DSL:

```ruby
active_scaffold :ticket do |config|
  config.mcp.name = :support_tickets
  config.mcp.label = "Support tickets"
  config.mcp.expose :list,
                    description: "Find support tickets using queue filters and pagination.",
                    columns: %i[id subject status customer_id],
                    filter_columns: {status: %i[equal in]},
                    filters: %i[open overdue]
  config.mcp.show.columns = %i[id subject status description]
  config.mcp.show.lookup_columns = %i[case_number]
end
```

`config.mcp.name` is the stable resource name shared by its generated tools.
When omitted, it uses `model.model_name.route_key`. Generators prefix it with
their action, producing names such as `list_support_tickets`; future action
generators can use the same value for names such as `show_support_ticket`.

`config.mcp.label` is the human-facing resource label shared by exposed
actions. Like ActiveScaffold's list label, it falls back to
`config.core.label(count: 2)`. In the example above the list title is
`List Support tickets`.

Both values can still be overridden for one action. An action-level `name` is
the complete tool identifier rather than a resource name:

```ruby
config.mcp.expose :list,
                  name: :search_support_tickets,
                  label: "Searchable support tickets"
```

ActionMCP's `title` DSL stores `annotations.title`: a human-readable display
name that MCP clients may show. It is separate from `description`, which tells
the model what the tool does. The generated list description also states which
filter categories are available and that `limit` and `page` control pagination.
Set `description` explicitly when business-specific guidance would be more
useful. `name` remains the protocol identifier.

Use `expose` to introduce and configure a custom action that does not yet have
an MCP configuration entry:

```ruby
active_scaffold :customer do |config|
  config.mcp.expose :sepa_mandate do |action|
    action.columns = %i[account creditor_identifier]
    action.description = "Create a SEPA mandate"
  end
end
```

Set `config.mcp.actions = :all` to expose all enabled ActiveScaffold actions.
No actions are exposed by default. The configured tool generator is called when
the MCP action module is included in the controller.

Common actions can be exposed globally:

```ruby
ActiveScaffold.defaults do |config|
  config.mcp.expose :list do |action|
    action.filter_columns = {id: %i[equal in]}
  end
  config.mcp.expose :show
end
```

Controller-specific custom actions should be exposed in that controller's
`active_scaffold` block.

Controller behavior that must also apply to an MCP tool should live in a shared
module. Include it in the controller and configure it for the action:

```ruby
module TicketListBehavior
  def list_authorized?
    current_user.has_right?("tickets", "index")
  end

  def beginning_of_chain
    super.where(account_id: current_user.account_id)
  end
end

class TicketsController < ApplicationController
  active_scaffold :ticket do |config|
    # Included in the controller after all ActiveScaffold action modules.
    config.custom_modules << TicketListBehavior

    # Included in the generated list tool after Actions::List.
    config.mcp.expose :list, modules: TicketListBehavior
  end
end
```

Configured modules are included after the ActiveScaffold action module, so they
can override hooks such as `list_authorized?`, `beginning_of_chain`,
`conditions_for_collection`, and named-filter security methods. Keep HTTP-only
methods out of shared modules.

Default filter-column sets can be configured globally:

```ruby
ActiveScaffold.defaults do |config|
  config.mcp.filter_column_sets = {
    foreign_keys: :in,
    timestamps: :range
  }
end
```

`filter_column_sets` requires a hash so every set has an explicit operator; the
gem does not assume whether a foreign key should use equality or membership, or
whether a timestamp should use equality or a range:

```ruby
config.mcp.expose :list,
                  filters: :all,
                  filter_column_sets: {foreign_keys: :in, timestamps: :range}
```

The generated base tool inherits from `ApplicationMCPTool` when that constant is
available, falling back to `ActionMCP::Tool`. It can be configured explicitly
before any generated tools are built:

```ruby
ActiveScaffold.defaults do |config|
  config.mcp.base_tool = "ApplicationMCPTool"
end
```

An application base tool may define the class method
`active_scaffold_tool_authorized?` to filter generated tools for the current
user and apply the same application-level authorization before execution:

```ruby
class ApplicationMCPTool < ActionMCP::Tool
  def self.active_scaffold_tool_authorized?(controller_class:, action_name:, user:)
    user.has_right?(controller_class.controller_path_for_rights, action_name)
  end
end
```

The hook is optional and should be a cheap check independent of tool arguments.
`ActionMCP::Configuration#filtered_tools` applies the active profile first and
then calls it using `ActionMCP::Current.user`. Tools without a class-level
authorization predicate are left unchanged. ActionMCP stores that filtered list
in the session, so a client must reconnect after its permissions change.

Before execution the generated tool checks the hook again inside
ActiveScaffold's current-user context. Action-specific instance checks are then
added by each tool type; for example, list tools also call `list_authorized?`.

When any execution-level authorization check returns `false`, the generated
tool calls the private instance method `unauthorized_tool!` instead of running
`perform`. By default it raises `ActiveScaffold::ActionNotAllowed`. The
configured application base tool may implement the method to use an
application-specific exception or message:

```ruby
class ApplicationMCPTool < ActionMCP::Tool
  private

  def unauthorized_tool!
    raise ActiveScaffold::ActionNotAllowed,
          "You are not allowed to use #{self.class.tool_name}"
  end
end
```

The application implementation replaces the default fallback and should not
call `super`. If it returns normally, the callback still stops before
`perform`; ActionMCP will report the operation as aborted unless the hook has
already reported an error. This hook applies only during execution. Discovery
authorization is handled by the class-level `tool_authorized?` predicate.

### Inspecting registered and authorized tools

`action_mcp:list_tools` reads the complete ActionMCP registry and therefore
lists generated tools without applying profiles or per-user authorization.
`action_mcp:show_profile[profile_name]` calls
`ActionMCP::Configuration#filtered_tools`. If
`active_scaffold_tool_authorized?` requires a user, the generated tools are not
shown because a Rake task does not establish `ActionMCP::Current.user`.

ActionMCP's `show_profile` task accepts only `profile_name`. The gem adds a
prerequisite that can resolve the current user from `MCP_USER=CLASS#ID` before
the original task runs. The class may be namespaced and must respond to `find`;
the gem does not assume a particular user class or persistence library:

```sh
READONLY=1 RAILS_ENV=production MCP_USER='User#123' \
  bin/rails 'action_mcp:show_profile[primary]'
```

For a namespaced class, use a value such as
`MCP_USER='Accounts::User#123'`. Without `MCP_USER`, the task leaves
`ActionMCP::Current.user` unset and retains ActionMCP's normal behavior.

The full accepted arguments are in each tool's `inputSchema`. ActionMCP can
print all registered schemas as JSON:

```sh
READONLY=1 RAILS_ENV=production bin/rails action_mcp:apps:schema |
  jq '.tools[] | select(.name == "list_support_tickets")'
```

Known ActiveScaffold actions validate their supported settings. Settings for an
unknown custom action are accepted unless the configured validator implements a
matching validation method:

```ruby
class ApplicationMCPSettingsValidator < ActiveScaffold::MCP::SettingsValidator
  private

  def valid_settings_for_publish?(setting, value)
    setting == :notify && [true, false].include?(value)
  end
end

ActiveScaffold.defaults do |config|
  config.mcp.settings_validator = ApplicationMCPSettingsValidator
end
```

## Tool generators

`config.mcp.tool_generator` defaults to an
`ActiveScaffold::MCP::GeneratorFactory`. Generators may be registered for exact
actions or selected from action metadata:

```ruby
ActiveScaffold.defaults do |config|
  factory = config.mcp.tool_generator

  factory.register(ListToolGenerator, actions: :list)
  factory.register(ShowToolGenerator, actions: %i[show details])

  factory.register_default(
    FormToolGenerator,
    crud_type: :create,
    columns: true
  )

  factory.register_custom(
    DestructiveActionToolGenerator,
    submit_method: :post,
    columns: false,
    destructive: true
  )
end
```

An action-specific generator implements:

```ruby
def self.generate_tool_for(
  controller_class:,
  action_name:,
  action_config:,
  mcp_config:,
  settings:
)
  # Return a generated tool class, an array of tool classes, or nil.
end
```

The factory uses `generate_tools_for`.

The built-in `ListToolGenerator` is registered explicitly for `:list`, and
`ShowToolGenerator` is registered for `:show`. The list generator
generates a read-only subclass of `ActiveScaffold::MCP::ListTool`. The base list
tool reuses ActiveScaffold's `do_list` and owns execution, pagination,
authorization, and result serialization. The generator builds the concrete
tool metadata, input schema, parameter mappings, and configured extensions.
Generated list tools support:

- Explicit `filter_columns`, with `equal`, `in`, `between`, `null` and their
  negated variants.
- The `foreign_keys`, `dates`, and `timestamps` filter-column sets.
- Selected named list filters or `filters: :all`. Named filters keep their
  ActiveScaffold parameter name (for example, `filter_status`) in the tool schema.
- A `search` argument whenever ActiveScaffold's search action is enabled. It
  uses the configured `config.search.columns` and can be combined with the other
  list filters. Set `config.mcp.list.search = false` to omit it for MCP.
- Configurable output columns plus bounded `limit` and `page` arguments.

When a selected foreign key belongs to a polymorphic association, its type
column is exposed with the same operators. For example, selecting `company_id`
also exposes `company_type` (or `company_id_in` and `company_type_in` when using
the `in` operator).

The model primary key is always included in list and show output, even when it
is omitted from the configured MCP output columns, subject to the same column
and record authorization as every other value. Output columns selected from the
normal list configuration already pass through
ActiveScaffold's class-level visibility checks. Explicit MCP output columns are
checked with the model's `authorized_for?`, and every output value is also
checked with the individual record's `authorized_for?` before serialization.
Association columns have a stable representation: a singular association is
`{"id": ..., "label": ...}` or `null`, and a collection association is an
array of those objects. Labels use the associated record's `to_label`.

### Virtual output columns

When MCP `columns` are not configured explicitly, list and show tools reuse the
visible columns from `config.list.columns` and `config.show.columns`,
respectively. Those ActiveScaffold action columns may include virtual columns
which exist only for the HTML view and are rendered by helpers such as
`status_column(record, column)`.

MCP does not call ActiveScaffold column helpers. They are view-layer methods
which may return HTML, links, images, or other browser-specific output. During
list and show serialization, a non-association column is included only when the
record responds to the column name. Consequently, a helper-only virtual column
is omitted from the MCP record instead of being returned as `null`:

```ruby
active_scaffold :device do |config|
  config.list.columns = %i[id name status_badge]
  config.show.columns = %i[id name status_badge]
end

module DevicesHelper
  def status_badge_column(record, column)
    content_tag(:span, record.status, class: "badge")
  end
end
```

In this example, generated list and show results contain `id` and `name`, but
not `status_badge`. The same rule applies when the virtual column is selected
explicitly with `config.mcp.list.columns`, `config.mcp.show.columns`, or the
`columns:` option passed to `config.mcp.expose`.

A virtual column backed by a public model instance method is included, using
the method's raw return value rather than a column helper. Model-backed columns
whose value is `nil` are still included as JSON `null`; omission is reserved
for columns which are neither associations nor readable from the record. If an
MCP tool needs a value that currently exists only as HTML presentation logic,
expose a presentation-independent value from the model or another
non-view-layer interface and select that column for MCP output.

The result includes the records and ActiveScaffold's pagination metadata. The
total reuses the count already calculated by ActiveScaffold rather than issuing
another count query:

```json
{
  "records": [],
  "page": 2,
  "total_count": 57,
  "total_pages": 3
}
```

The show generator creates a read-only `show_<singular-resource>` tool. By default it
requires `id`, whose JSON type follows the model primary key. Configure
`lookup_columns` to expose alternative identifiers such as `case_number`:

```ruby
config.mcp.show.lookup_columns = %i[case_number]
```

Callers must provide exactly one of `id` or the configured lookup columns. A
lookup must resolve to exactly one record; a missing or ambiguous value returns
an error. Lookup columns are explicit because application-level uniqueness is
often more meaningful than database-index introspection. The tool reuses
ActiveScaffold's filtered query, `do_show`, show authorization, configured show
columns, and the same record and association serialization as list. Its result
contains one record:

```json
{
  "record": {
    "id": 7,
    "name": "Widget 7"
  }
}
```

For example, an `in` comparator creates `<column>_in`, while `between` creates
`<column>_from` and `<column>_to`. These are translated back to the parameter
shape consumed by ActiveScaffold's `conditions_from_params`.

## Development

The Servpac application loads the gem from `vendor/active_scaffold_mcp`:

```ruby
gem "active_scaffold_mcp", path: "vendor/active_scaffold_mcp"
```

Run its tests from the gem directory with:

```sh
bundle exec rake test
```
