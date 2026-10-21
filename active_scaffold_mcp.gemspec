# frozen_string_literal: true

require_relative "lib/active_scaffold/mcp/version"

Gem::Specification.new do |spec|
  spec.name = "active_scaffold_mcp"
  spec.version = ActiveScaffold::MCP::VERSION
  spec.authors = ["Sergio Cambra"]

  spec.summary = "Expose ActiveScaffold actions as MCP tools"
  spec.description = "An ActionMCP integration that generates MCP tools from ActiveScaffold configuration."
  spec.homepage = "https://github.com/activescaffold/active_scaffold_mcp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "LICENSE.txt", "README.md"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "actionmcp", ">= 0.200"
  spec.add_dependency "active_scaffold", ">= 4.4"
  spec.add_dependency "rails", ">= 8.1"
end
