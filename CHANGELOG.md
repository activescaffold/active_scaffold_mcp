# Changelog

## Unreleased

## 0.1.3 - 2026-11-17

### Added

- Allow presenter modules to handle ActiveScaffold UIs with
  `mcp_list_<list_ui>` and `mcp_show_<show_ui>` methods.
- Pass the UI-specific options to MCP presenter methods.
- Present Active Storage, Paperclip, CarrierWave, Dragonfly, and file-column
  attachments as structured metadata.

### Changed

- Let show presenters reuse the corresponding list UI method when there is no
  show-specific method, matching ActiveScaffold's UI inheritance.

## 0.1.2 - 2026-10-30

### Added

- Add a protected `render_result` hook to list and show tools so configured
  modules can customize MCP output without replacing tool logic.

### Changed

- Update the documented ActionMCP inspection commands.

## 0.1.1 - 2026-10-21

### Changed

- Require ActiveScaffold 4.4 or newer.
- Document the plugin's runtime requirements and installation.

## 0.1.0 - 2026-10-21

- Initial release with generated read-only list and show tools.
