# frozen_string_literal: true

namespace :action_mcp do
  task load_profile_user: :environment do
    next if ENV["MCP_USER"].blank?

    ActionMCP::Current.user = ActiveScaffold::MCP::ProfileUser.resolve(ENV.fetch("MCP_USER"))
  end

  task show_profile: :load_profile_user
end
