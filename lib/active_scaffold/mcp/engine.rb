# frozen_string_literal: true

module ActiveScaffold
  module MCP
    class Engine < Rails::Engine
      rake_tasks do
        load File.expand_path("../../tasks/active_scaffold_mcp_tasks.rake", __dir__)
      end

      initializer "active_scaffold_mcp.initialize", after: "initialize_active_scaffold" do
        ActiveScaffold.defaults do |config|
          config.actions << :mcp unless config.actions.include?(:mcp)
        end
      end

      config.to_prepare do
        if Rails.application.config.reloading_enabled?
          ActiveScaffold::MCP.reload_generated_tools!
        end
      end
    end
  end
end
