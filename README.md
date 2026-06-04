# Notion2LLMcouncil Plus

Notion2LLMcouncil Plus is a small public integration launcher for running:

- [notion2api](https://github.com/maverickxone/notion2api) as a local OpenAI-compatible Notion AI gateway
- [the-ai-counsel](https://github.com/jacob-bd/the-ai-counsel) as the council UI

The launcher starts both projects and automatically configures LLM Council Plus to use Notion2API as its custom OpenAI-compatible provider.

Current bundled LLM Council Plus features include the standard 3-stage council flow, Advisor debates, Advisor MCP tools, and backend-mounted MCP SSE at `/mcp/sse` on the Council backend port.

## What It Does

- Reuses existing local checkouts or clones both upstream repos into `vendor/`
- Validates the Notion login with `python login.py --check`
- Refreshes the Notion browser login flow when needed, or when `-RefreshLogin` is passed
- Generates or preserves a local Notion2API `API_KEY`
- Forces Notion2API to `APP_MODE=standard`
- Starts Notion2API on `http://127.0.0.1:8000`
- Starts LLM Council backend on `http://127.0.0.1:8001`
- Starts LLM Council frontend on `http://127.0.0.1:5173`
- Exposes LLM Council MCP SSE through the backend at `http://127.0.0.1:8001/mcp/sse`
- Configures LLM Council custom provider:
  - name: `Notion2API`
  - URL: `http://127.0.0.1:8000/v1`
  - API key: the generated/preserved Notion2API `API_KEY`
  - provider enabled: `custom`
  - council models: `custom:gpt-5.5`, `custom:claude-opus4.7`, `custom:gemini-3.1pro`, `custom:kimi-2.6`
  - chairman: `custom:claude-opus4.7`
  - member filters: `Remote` for all four council members
- Leaves Notion2API streaming available for OpenAI-compatible clients that send `stream: true`

The default local paths, clone URLs, ports, and provider model list live in `config/default.json`.
Create `config/local.json` with the same shape to override them without committing local machine paths or private settings.

## Requirements

- Windows PowerShell
- Git
- Python 3.10+
- Node.js 18+
- npm

The upstream projects provide their own dependency files. This launcher does not vendor credentials or tokens.

## Quick Start

From this repo:

```powershell
.\setup.bat
```

Then:

```powershell
.\launch.bat
```

Open:

```text
http://127.0.0.1:5173/
```

The first run may open a Chrome/Edge window for Notion login. Complete the Notion login there. The generated credentials stay in the local Notion2API checkout and are ignored by git.

`setup.bat` is the one-time initializer. It checks or refreshes the Notion browser login flow and writes a local Notion2API API key if one is missing. `launch.bat` starts the services and configures LLM Council to use that same key.

Before cleaning or replacing anything under `vendor\the-ai-counsel`, read [Runtime Data Recovery](#runtime-data-recovery). That checkout contains local Council settings and conversation history.

## Common Commands

Start without opening the browser UI:

```powershell
.\launch.bat -NoBrowser
```

Force a fresh Notion login:

```powershell
.\launch.bat -RefreshLogin
```

The launcher handles the Notion login flow by checking `python login.py --check` before startup. If the session is invalid, it runs the browser-assisted login flow with the configured timeout, then starts Notion2API only after the token check passes.

Stop launcher-managed services:

```powershell
.\stop.bat
```

Back up local Council settings and conversation history before cleaning or replacing the Council vendor checkout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\backup-runtime-data.ps1
```

Use existing local checkouts:

```powershell
.\launch.bat -NotionRoot X:\Code\notion2api-pub -CouncilRoot X:\Code\the-ai-counsel
```

Or set those defaults once in `config/local.json`:

```json
{
  "notion": {
    "localRoot": "D:\\Code\\notion2api-pub"
  },
  "council": {
    "localRoot": "D:\\Code\\the-ai-counsel"
  }
}
```

Use a specific config file:

```powershell
.\launch.bat -ConfigPath .\config\my-machine.json
```

Clone/use checkouts under this repo's `vendor/` folder:

```powershell
.\launch.bat -UseVendor
```

Until the Notion2API auto-login PR is merged upstream, vendor mode clones the PR branch from `Sanity-Cloud/notion2api`. To override that:

```powershell
.\launch.bat -UseVendor -NotionRepoUrl https://github.com/maverickxone/notion2api.git -NotionBranch main
```

## Ports

| Service | URL |
|---|---|
| Notion2API | `http://127.0.0.1:8000` |
| LLM Council backend | `http://127.0.0.1:8001` |
| LLM Council frontend | `http://127.0.0.1:5173` |
| LLM Council MCP SSE | `http://127.0.0.1:8001/mcp/sse` |

## Credential Safety

This repo does not store Notion cookies, `token_v2`, `.env`, or `accounts.json`.

Notion2API's `login.py` uses browser cookies transiently during local login to derive the active Notion account and workspace. The resulting `accounts.json` and `.env` stay in the Notion2API checkout and should not be committed.

## Runtime Data Recovery

The Council backend stores local runtime state under its checkout:

```text
vendor\the-ai-counsel\data\
```

Important files include:

- `data\settings.json`: provider settings, selected council models, prompt settings, and the custom endpoint API key.
- `data\conversations\*.json`: conversation history.

If you restore `settings.json` from an older runtime, make sure the restored `custom_endpoint_api_key` matches the active Notion2API key in:

```text
vendor\notion2api\.env
```

The launcher verifies this during startup. If the Council custom provider URL, enabled flag, or API key drift from the active Notion2API configuration, the launcher logs a sanitized warning, backs up the exported Council settings to `vendor\the-ai-counsel\data\settings.launcher-backup-*.json`, and rewrites the Council custom provider settings to use the active Notion2API `API_KEY`. Repair events are also appended to `logs\launcher-events.log`. If verification still fails after repair, startup stops without printing the raw key. A stale key causes Notion2API to return `401` errors such as `API KEY doesn't match`.

This auto-repair behavior treats `config/default.json` plus `config/local.json` as the launcher source of truth for the Notion2API-backed custom provider. Because this wrapper exists to run Council through Notion2API, a disabled custom provider is treated as drift and re-enabled when repair is enabled. To deliberately manage the Council custom provider yourself, disable repair in `config/local.json`:

```json
{
  "provider": {
    "autoRepair": false
  }
}
```

With repair disabled, the launcher leaves drifted Council settings unchanged and logs the drift instead of importing corrected settings.

Launcher-created settings backups are plaintext restore copies and may contain API keys from Council settings. They are ignored by git, but should still be treated as private local secrets. The launcher keeps the latest 10 `settings.launcher-backup-*.json` files and rotates `logs\launcher-events.log` at about 1 MB.

To restore one of those settings backups:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch.ps1 -Stop
Copy-Item "vendor\the-ai-counsel\data\settings.launcher-backup-YYYYMMDD-HHMMSS.json" "vendor\the-ai-counsel\data\settings.json" -Force
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch.ps1 -NoBrowser
```

The relaunch will re-sync the custom endpoint API key to the active Notion2API `.env` value unless `provider.autoRepair` is disabled.

Launcher smoke tests send real requests through the Council backend and may create visible conversation records. Treat small conversation-count increases during validation as expected operator activity.

Before cleaning or replacing a vendor checkout, copy runtime data outside the repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\backup-runtime-data.ps1
```

Do not run `git -C vendor\the-ai-counsel clean -fdx` unless every untracked runtime file in that checkout has been verified and backed up. The `-x` flag removes ignored files too, including local runtime data and virtual environments.

## Streaming

Notion2API supports OpenAI-compatible streaming when the caller sends:

```json
{
  "stream": true
}
```

The integration exposes this as `provider.supportsStreaming` in `config/default.json` so the capability is visible and configurable. It does not force streaming globally because non-streaming clients should keep receiving normal JSON responses.

## Logs

Launcher logs are written to:

```text
logs\
```

The most useful files are:

- `logs\notion2api.err.log`
- `logs\council-backend.err.log`
- `logs\council-frontend.out.log`

## Development

For information about the application architecture, security practices, and modular structure, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Notes

This is an integration wrapper. It does not replace either upstream project. Update or contribute to each upstream repository independently.
