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
