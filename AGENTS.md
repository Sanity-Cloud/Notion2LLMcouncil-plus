# AGENTS.md

Operational guidance for AI agents, automation tools, and maintainers working on `Sanity-Cloud/Notion2LLMcouncil-plus`.

This repository is a Windows-first Electron desktop wrapper and PowerShell orchestrator for running Notion2API and LLM Council Plus together as a local Notion-powered council interface.

## SigMap context tools

Run `sigmap ask "<your question>"` or `sigmap --query "<topic>"` before searching for files relevant to a task.

Available SigMap commands:

```json
[
  {
    "name": "sigmap_ask",
    "description": "Rank source files by relevance to a natural-language query. Run before exploring the codebase.",
    "command": "sigmap ask \"$QUERY\""
  },
  {
    "name": "sigmap_validate",
    "description": "Validate SigMap config and measure context coverage. Run after changing config or source dirs.",
    "command": "sigmap validate"
  },
  {
    "name": "sigmap_judge",
    "description": "Score an LLM response for groundedness against source context. Use to verify answer quality.",
    "command": "sigmap judge --response \"$RESPONSE\" --context \"$CONTEXT\""
  },
  {
    "name": "sigmap_query",
    "description": "Rank all files by relevance using TF-IDF and write a focused mini-context.",
    "command": "sigmap --query \"$QUERY\" --context"
  },
  {
    "name": "sigmap_weights",
    "description": "Show learned file-ranking multipliers accumulated from past sessions.",
    "command": "sigmap weights"
  }
]
```

## Repository purpose

Notion2Council does not replace either upstream project. It coordinates them:

- `notion2api` runs as a local OpenAI-compatible Notion AI gateway.
- `llm-council-plus` runs as the council backend/frontend.
- The launcher validates Notion login, generates/preserves the local Notion2API API key, starts both services, and configures LLM Council's custom provider to point at Notion2API.

Default runtime ports:

| Service | Default URL |
|---|---|
| Notion2API | `http://127.0.0.1:8000` |
| LLM Council backend | `http://127.0.0.1:8001` |
| LLM Council frontend | `http://127.0.0.1:5173` |

## Current architecture

```text
Notion2LLMcouncil-plus/
├─ electron/                  # Electron desktop shell
│  ├─ main.js                 # Main process lifecycle, tray, hotkeys, shutdown
│  ├─ preload.js              # Safe renderer bridge
│  ├─ hotkeys.html            # Internal hotkey settings page with CSP
│  ├─ hotkeys-renderer.js     # Renderer logic for hotkey capture/save/reset
│  ├─ lib/
│  │  ├─ config.js            # Hotkey/config helpers
│  │  ├─ launcher.js          # PowerShell launch/stop bridge
│  │  ├─ logger.js            # Desktop log writer
│  │  └─ utils.js             # App-root and URL readiness helpers
│  └─ windows/
│     ├─ main.js              # Main BrowserWindow creation/show/hide
│     └─ hotkeys.js           # Hotkey settings window
│
├─ scripts/                   # PowerShell orchestration
│  ├─ launch.ps1              # Main service start/stop/setup entry point
│  ├─ setup-desktop.ps1       # Desktop setup helper
│  ├─ package-release.ps1     # Local release/source bundle packager
│  ├─ create-electron-icons.ps1
│  ├─ validate-release.ps1    # Validation gate for local/CI/release builds
│  └─ lib/
│     ├─ CommonUtils.psm1
│     ├─ ConfigManager.psm1
│     ├─ NetworkUtils.psm1
│     ├─ ProcessManager.psm1
│     ├─ RepoManager.psm1
│     └─ StateManager.psm1
│
├─ config/
│  ├─ default.json            # Portable defaults; repo-local vendor paths
│  ├─ local.example.json      # Template for machine-specific overrides
│  └─ schema.json             # Config schema
│
├─ .github/workflows/
│  ├─ validate.yml            # Normal push/PR validation
│  └─ release.yml             # Manual/tag Windows release publisher
│
├─ package.json               # Electron build/release scripts
├─ package-lock.json
├─ electron-builder.portable.json
├─ README.md
├─ DEVELOPMENT.md
└─ AGENTS.md
```

## Agent operating rules

### 1. Treat `master` as shared state

This repository may be edited by multiple tools or agents. Before editing a tracked file:

1. Fetch the current file from GitHub.
2. Record the current blob SHA.
3. Apply the smallest safe patch.
4. Write with the current SHA.
5. If the SHA changed, re-read and rebase the edit manually instead of overwriting.

Do not blindly rewrite large files if another tool may be working in the same area.

### 2. Keep changes scoped

Prefer small, reviewable commits. Good commit scopes:

- `electron/*` lifecycle or UI hardening
- `scripts/lib/*` PowerShell orchestration hardening
- `.github/workflows/*` CI/release changes
- `config/*` schema/default changes
- documentation updates

Avoid mixing runtime refactors, release workflow changes, and docs in the same commit unless they are inseparable.

### 3. Validate before committing

Run the validation gate before committing when working locally:

```powershell
npm run validate
```

At minimum, syntax-check touched subsystems:

```powershell
# PowerShell scripts/modules
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-release.ps1

# Electron JavaScript
node --check electron/main.js
```

The CI validation gate checks JSON syntax, package-lock/package version parity, PowerShell script/module parsing, module imports, Electron JavaScript parsing, and release workflow safety.

### 4. Do not commit secrets or machine state

Never commit:

- Notion cookies
- `token_v2`
- Notion `accounts.json`
- `.env` files from upstream repos
- local logs
- `config/local.json`
- generated vendor checkouts under `vendor/`

Machine-specific paths belong in `config/local.json`, not `config/default.json`.

### 5. Preserve Windows-first assumptions

This project is Windows-first:

- PowerShell is the service orchestrator.
- Electron packages Windows artifacts.
- Batch wrappers are part of the user-facing workflow.
- The release workflow runs on `windows-latest`.

Do not remove Windows compatibility to make cross-platform behavior cleaner. Cross-platform improvements are acceptable only if Windows behavior remains intact.

## Runtime flow

### Electron startup

1. Electron waits for `app.whenReady()`.
2. The main window is created hidden.
3. Tray menu and global hotkeys are registered.
4. `electron/lib/launcher.js` starts `scripts/launch.ps1 -NoBrowser`.
5. Electron waits for the Council frontend URL.
6. The Council UI loads into the main window.
7. The main window is shown.

### Electron shutdown

1. `before-quit` sets a guarded quitting state.
2. Electron calls `stopStack()`.
3. `stopStack()` runs `scripts/launch.ps1 -Stop`.
4. PowerShell stops tracked service process trees.
5. Electron finishes quit after the stop command exits/errors or after the timeout guard.

### PowerShell startup

`scripts/launch.ps1`:

1. Imports modules from `scripts/lib/`.
2. Reads `config/default.json` and optional local config.
3. Resolves repo/vendor paths.
4. Ensures upstream repos exist and are on the expected branch.
5. Ensures Notion2API `.env` values.
6. Validates or refreshes Notion login.
7. Starts/reuses Notion2API.
8. Starts/reuses LLM Council backend.
9. Applies custom provider settings.
10. Starts/reuses LLM Council frontend.
11. Writes launcher state for later stop operations.

## Important files and responsibilities

### Electron

| File | Responsibility |
|---|---|
| `electron/main.js` | App lifecycle, tray, menus, hotkeys, chat focus, startup/shutdown sequencing. |
| `electron/lib/launcher.js` | Runs PowerShell launch/stop scripts and returns the child process. |
| `electron/lib/utils.js` | Resolves app root and waits for URLs. Must reject roots missing `scripts/launch.ps1`. |
| `electron/windows/main.js` | Creates the main BrowserWindow with sandbox/context isolation. |
| `electron/windows/hotkeys.js` | Creates/manages the hotkey settings window. |
| `electron/hotkeys.html` | Internal hotkey UI. Keep CSP strict; avoid inline scripts. |
| `electron/hotkeys-renderer.js` | Hotkey capture, validation, save/reset/test behavior. |

### PowerShell

| File | Responsibility |
|---|---|
| `scripts/launch.ps1` | Main orchestration entry point. Keep business flow readable. |
| `scripts/lib/CommonUtils.psm1` | Shared console/output and JSON helpers. |
| `scripts/lib/ConfigManager.psm1` | Config loading and nested property lookup. |
| `scripts/lib/NetworkUtils.psm1` | HTTP health checks and wait loops. |
| `scripts/lib/ProcessManager.psm1` | Port probing, listener PID lookup, process-tree stop. |
| `scripts/lib/RepoManager.psm1` | Clone/reuse/sync upstream repos and branches. |
| `scripts/lib/StateManager.psm1` | Read/write launcher state. Use UTF-8 without BOM. |
| `scripts/validate-release.ps1` | Local/CI/release validation gate. |
| `scripts/package-release.ps1` | Local packaging for source/runtime bundle. |

### Configuration

| File | Responsibility |
|---|---|
| `config/default.json` | Portable defaults. Must not contain personal drive paths. |
| `config/local.example.json` | Safe user template. |
| `config/local.json` | Local override file; should remain ignored/uncommitted. |
| `config/schema.json` | Config validation schema. |

### CI and release

| File | Responsibility |
|---|---|
| `.github/workflows/validate.yml` | Run validation on `master` pushes and PRs. Must not publish releases. |
| `.github/workflows/release.yml` | Build and publish Windows release on `workflow_dispatch` or `v*` tags. |

## Release process

The release workflow is tag/manual only. Normal pushes should validate but not publish.

To publish a release:

```powershell
npm run validate
git status

# Example release tag
git tag v0.1.2
git push origin v0.1.2
```

The workflow should:

1. Install dependencies.
2. Generate Electron icons.
3. Run `npm run validate:ci`.
4. Build portable EXE, ZIP, and MSI.
5. Create the source/runtime bundle.
6. Stage selected artifacts into `github-release/Notion2Council-<version>-windows-release.zip`.
7. If an existing release exists for the tag, delete its old assets safely.
8. Publish only `github-release/*.zip`.

Do not reintroduce broad release globs such as:

```yaml
files: |
  release/**
  dist-release/**
```

Those globs caused GitHub Releases to receive 100+ individual Electron runtime assets.

## Versioning rules

When bumping versions:

1. Update `package.json` version.
2. Update artifact names in `package.json` if they contain literal versions.
3. Run:

```powershell
npm install --package-lock-only
npm run validate
```

4. Commit `package.json` and `package-lock.json` together.
5. Tag using the same version, e.g. `v0.1.2`.

The release workflow derives `RELEASE_TAG` from `package.json`, so mismatched tags/package versions can publish unexpected release names.

## Security requirements

### Electron

- Keep `nodeIntegration: false`.
- Keep `contextIsolation: true`.
- Keep `sandbox: true` for windows unless a very specific exception is documented.
- Prefer preload IPC bridges over direct Node access in renderers.
- Keep internal pages on strict CSP.
- Do not add inline scripts to `hotkeys.html`; use `hotkeys-renderer.js`.

### PowerShell

- Avoid writing BOM-marked `.env` or state files. Use `System.Text.UTF8Encoding($false)` for cross-tool compatibility.
- Stop process trees when shutting down services.
- Avoid leaking temporary environment variables into parent/global session state.
- Validate service reuse with service-specific markers, not only a generic HTTP 200.

### Credentials

- Do not log API keys or Notion tokens.
- Do not commit local `.env`, Notion account files, cookies, or generated service state.

## Known fragile areas

Agents should inspect these carefully when modifying runtime behavior:

1. **Council frontend DOM selectors** — `focusChatInput()` relies on frontend selectors and may break if LLM Council UI changes.
2. **Upstream branch drift** — vendor repos are external and may change behavior.
3. **Notion login flow** — depends on browser/cookie behavior outside this repo.
4. **Release cleanup** — must tolerate a missing release. Do not treat a 404 JSON body as a release ID.
5. **Ports** — service reuse must check expected content/title to avoid attaching to unrelated local apps.
6. **Windows quoting** — PowerShell, npm, and electron-builder commands must preserve path quoting.

## Preferred local smoke tests

Run these before claiming production readiness:

```powershell
npm run validate

powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module .\scripts\lib\CommonUtils.psm1, .\scripts\lib\ConfigManager.psm1, .\scripts\lib\ProcessManager.psm1, .\scripts\lib\StateManager.psm1, .\scripts\lib\NetworkUtils.psm1, .\scripts\lib\RepoManager.psm1 -Force; 'modules ok'"

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch.ps1 -SetupOnly

npm run electron:dev
```

For release validation:

```powershell
npm run electron:build
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\package-release.ps1 -SkipNpmInstall -SkipBuild -NoPause
```

## Agent checklist before final response

Before telling the user a change is complete:

- State exactly which files changed.
- State the commit SHA.
- Mention whether validation was run locally, in CI, or only reasoned about.
- Distinguish between `master` pushed and release published.
- If a release was expected, verify the release asset shape with GitHub CLI or the release page.

## Current distribution stance

The release currently publishes a single unified Windows ZIP that contains selected build outputs. This is intentionally cleaner than uploading every file under `release/**`, but it is not necessarily the final product strategy.

Future maintainers may choose one of:

- portable EXE only
- MSI installer only
- MSIX
- combined ZIP containing selected installers

Do not change the distribution strategy without updating `README.md`, `DEVELOPMENT.md`, this file, and the release workflow body.


## Tools

<!-- sigmap-tools -->

```json
[
  {
    "name": "sigmap_ask",
    "description": "Rank source files by relevance to a natural-language query. Run before exploring the codebase.",
    "command": "sigmap ask \"$QUERY\""
  },
  {
    "name": "sigmap_validate",
    "description": "Validate SigMap config and measure context coverage. Run after changing config or source dirs.",
    "command": "sigmap validate"
  },
  {
    "name": "sigmap_judge",
    "description": "Score an LLM response for groundedness against source context. Use to verify answer quality.",
    "command": "sigmap judge --response \"$RESPONSE\" --context \"$CONTEXT\""
  },
  {
    "name": "sigmap_query",
    "description": "Rank all files by relevance using TF-IDF and write a focused mini-context.",
    "command": "sigmap --query \"$QUERY\" --context"
  },
  {
    "name": "sigmap_weights",
    "description": "Show learned file-ranking multipliers accumulated from past sessions.",
    "command": "sigmap weights"
  }
]
```

## Auto-generated signatures
<!-- Updated by gen-context.js -->
# Code signatures

## SigMap commands

| When | Command |
|------|---------|
| Before answering a question | `sigmap ask "<your question>"` |
| After code changes | `sigmap validate` |
| To query by topic | `sigmap --query "<topic>"` |

Always run `sigmap ask` or `sigmap --query` before searching for files relevant to a task.
## changes (last 5 commits — 1 second ago)
```
electron\main.js                              +waitForReadyNotionUrls  +openNotion2ApiBrowser  +openNotion2ApiDocsBrowser  +showAboutDialog
```

## .github

### .github\copilot-instructions.md
```
h2 Auto-generated signatures
h2 SigMap commands
h1 Code signatures
h2 .github
h3 .github\copilot-instructions.md
h3 .github\gemini-context.md
h3 .github\workflows\release.yml
h3 .github\workflows\validate.yml
h2 electron
h3 electron\diagnostics-renderer.js
h3 electron\diagnostics.html
h3 electron\hotkeys-renderer.js
h3 electron\hotkeys.html
h3 electron\lib\config.js
h3 electron\lib\diagnostics.js
h3 electron\lib\integration-config.js
h3 electron\lib\launcher.js
h3 electron\lib\logger.js
h3 electron\lib\utils.js
h3 electron\main.js
h3 electron\windows\diagnostics.js
h3 electron\windows\hotkeys.js
h3 electron\windows\main.js
code-fence plain
```

### .github\gemini-context.md
```
h2 Auto-generated signatures
h2 Code Signatures
h2 .github
h3 .github\copilot-instructions.md
h3 .github\gemini-context.md
h3 .github\workflows\release.yml
h3 .github\workflows\validate.yml
h2 electron
h3 electron\diagnostics-renderer.js
h3 electron\diagnostics.html
h3 electron\hotkeys-renderer.js
h3 electron\hotkeys.html
h3 electron\lib\config.js
h3 electron\lib\diagnostics.js
h3 electron\lib\integration-config.js
h3 electron\lib\launcher.js
h3 electron\lib\logger.js
h3 electron\lib\utils.js
h3 electron\main.js
h3 electron\windows\diagnostics.js
h3 electron\windows\hotkeys.js
h3 electron\windows\main.js
code-fence plain
```

### .github\workflows\release.yml
```
keys: [name, on, permissions, env, jobs]
job: build-windows
```

### .github\workflows\validate.yml
```
keys: [name, on, permissions, jobs]
job: validate
```

## electron

### electron\main.js
```
async function focusChatInput(text, submit = false)
async function ensureChatInputReady()
async function clearCouncilUiStorage()
async function getActiveRuntimeUrls(timeoutMs = 90000)
async function isRuntimeReady(urls, timeoutMs = 2500)
async function waitForReadyRuntimeUrls()
async function waitForReadyNotionUrls()
async function openNotion2ApiBrowser()
async function openNotion2ApiDocsBrowser()
async function openChat()
async function openChatWithClipboard()
async function createNewChatInputReady()
async function openNewChat()
async function openNewChatWithClipboard()
function showAboutDialog()
function createTray()
function refreshTrayMenu()
function setApplicationMenu()
function registerHotkeys()
```

### electron\diagnostics-renderer.js
```
function setStatus(text)
function formatValue(value)
function renderDefinitionList(el, entries)
function renderServices(services)
function render(data)
function readConfigForm()
function writeConfigForm(data)
async function refresh()
```

### electron\diagnostics.html
```
title: Notion2Council Diagnostics
div#checkedAt
button#refresh
button#start
button#stop
button#openUi
button#openDocs
button#openLogs
div#services
dl#provider
dl#config
input#notionLocalRoot
input#notionPort
input#councilLocalRoot
input#councilBackendPort
input#councilFrontendPort
input#providerUrlPath
button#saveConfig
div#configPath
pre#state
pre#log
div#status
```

### electron\hotkeys-renderer.js
```
function setStatus(text, kind = '')
function readForm()
function writeForm(values)
function formatRegistrations(registrations)
function getAcceleratorString(e)
async function load()
```

### electron\hotkeys.html
```
title: Notion2Council Hotkeys
input#toggleWindow
input#openChat
input#openNewChat
input#clipboardToChat
input#clipboardToNewChat
input#openHotkeySettings
button#save
button#reset
button#testClipboard
button#testClipboardToNewChat
button#reload
div#status
div#path
```

### electron\lib\config.js
```
module.exports = { defaultHotkeys, getHotkeyConfigPath, readHotkeys, writeHotkeys }
function getHotkeyConfigPath()
function readHotkeys()
function writeHotkeys(hotkeys)
```

### electron\lib\diagnostics.js
```
module.exports = { getDiagnosticsStatus }
function readJson(filePath)
function readEnvValue(filePath, name)
function tailFile(filePath, maxChars = 4000)
function requestText(url, options = {})
function requestJsonPost(url, bodyObject, options = {})
function titleContains(body, expectedTitle)
async function testService(name, url, options = {})
async function getDiagnosticsStatus()
```

### electron\lib\integration-config.js
```
module.exports = { getIntegrationConfig, getEditableLocalConfig, saveLocalIntegrationConfig }
function readJsonFile(filePath)
function getNested(source, parts)
function getConfigValue(localConfig, defaultConfig, parts, fallback)
function getDefaultConfigPath(repoRoot)
function getLocalConfigPath(repoRoot)
function resolveRuntimePath(repoRoot, value, fallbackRelative)
function getIntegrationConfig()
function getEditableLocalConfig()
function saveLocalIntegrationConfig(values)
```

### electron\lib\launcher.js
```
module.exports = { startStack, stopStack }
function resolvePowerShellPath()
function showError(title, message)
function readEnvValue(filePath, name)
function hasSavedNotionAccount(integration)
function runPowerShell(scriptPath, args = [])
function runVisibleNotionLogin(integration, afterLogin)
function getScriptPath(scriptName)
function getBaseLaunchArgs()
function startStack({ noBrowser = true } = {})
function stopStack()
```

### electron\lib\logger.js
```
module.exports = { getLogsDir, appendLog }
function ensureDir(dir)
function getLogsDir()
function appendLog(message)
```

### electron\lib\utils.js
```
module.exports = { ensureDir, getAppRoot, getRuntimeRoot, getUserDataRoot, isInsideAsar, toUnpackedAsarPath, waitForUrl, waitForRuntimeState }
function ensureDir(dir)
function isInsideAsar(value)
function toUnpackedAsarPath(value)
function directoryHasLaunchScript(dir)
function getUserDataRoot()
function getRuntimeRoot()
function getAppRoot()
function waitForUrl(url, timeoutMs = 90000, options = {})
function waitForRuntimeState(statePath, timeoutMs = 90000)
```

### electron\windows\diagnostics.js
```
module.exports = { openDiagnostics }
function openDiagnostics(parentWindow)
```

### electron\windows\hotkeys.js
```
module.exports = { openHotkeySettings }
function openHotkeySettings(parentWindow)
```

### electron\windows\main.js
```
module.exports = { createMainWindow, getMainWindow, showMainWindow, toggleMainWindow }
function createMainWindow(councilUiUrl)
function getMainWindow()
function showMainWindow()
function toggleMainWindow()
```
