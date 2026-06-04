# Changelog

All notable changes to Notion2LLMcouncil Plus will be documented in this file.

## [0.4.3] - 2026-06-04

### Changed
- Migrated the council UI repository reference and vendor path from `llm-council-plus` to `the-ai-counsel` due to upstream repository renaming by the author.
- Updated launcher, electron configuration, patch scripts, and documentation references.

## [0.4.0] - 2026-05-30

### Added
- Bundled LLM Council Plus Advisors backend/frontend integration.
- Bundled Advisor MCP tools for persona CRUD, advisor settings, and advisor debate execution.
- Bundled backend-mounted MCP SSE at `/mcp/sse` on the existing Council backend port.

### Changed
- Updated the `vendor/llm-council-plus` pointer through the Advisors, Advisor MCP, and single-port MCP integration stack.
- Release artifact metadata now targets `0.4.0`.

### Fixed
- Launcher runtime now strips IPv6 loopback entries from proxy bypass environment values before startup to avoid local `httpx` proxy parsing failures.
- Advisor verdict save-to-Notion support is included through the bundled LLM Council Plus pointer.
