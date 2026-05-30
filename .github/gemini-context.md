

## Auto-generated signatures
<!-- Updated by gen-context.js -->
You are a coding assistant with complete knowledge of this codebase.
The following code signatures were extracted by SigMap v6.5.1 on 2026-05-30T02:43:39.590Z.

These signatures represent every public function, class, and type in the project.
Refer to them when answering questions about code structure, APIs, and implementation.
Before answering questions about specific code areas, suggest running `sigmap ask "<query>"` to get the most relevant files. After config changes, `sigmap validate` confirms coverage.

## Code Signatures

## deps
```
scratch\App_upstream_utf8.jsx ← components/Sidebar, api
scratch\ChatInterface_upstream_utf8.jsx ← StageTimer, SearchContext, Stage1, Stage2, Stage3
scratch\debug_conv_followup.py ← backend
scratch\dump_conv.py ← backend
scratch\test_council_run.py ← httpx
scratch\test_followup_run.py ← httpx
scratch\test_regex.py ← backend
```

## changes (last 5 commits — 1 second ago)
```
.github\copilot-instructions.md               +readJson  +readEnvValue  +tailFile  +requestText
.github\gemini-context.md                     +readJson  +readEnvValue  +tailFile  +requestText
```

## .github

### .github\copilot-instructions.md
```
h2 Auto-generated signatures
h2 SigMap commands
h1 Code signatures
h2 deps
h2 changes (last 5 commits — 1 second ago)
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
```

### .github\gemini-context.md
```
h2 Auto-generated signatures
h2 Code Signatures
h2 deps
h2 changes (last 5 commits — 1 second ago)
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
h2 scratch
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

## scratch

### scratch\app_jsx_diff.utf8.patch
```
function App() {
```

### scratch\App_upstream_utf8.jsx
```
class AppErrorBoundary
  constructor(props)
  static getDerivedStateFromError()
  render()
  if(this.state.hasError)
function AppLoadingFallback()
function App()
```

### scratch\ChatInterface_upstream_utf8.jsx
```
function hasStage1Results(msg)
function hasStage2Results(msg)
function hasStage2Started(msg)
function shouldShowStage1CouncilGrid(msg)
function shouldShowStage1Results(msg)
function getDeliberationScrollPhase(msg)
function renderStage1Content(msg)
function isCouncilTurnPending(msg, isActiveTurn, isLoading)
```

### scratch\debug_conv_followup.py
```
def main()
```

### scratch\dump_conv.py
```
def main()
```

### scratch\test_council_run.py
```
def check_no_hits(label, text)
def main()
```

### scratch\test_followup_run.py
```
def check_no_hits(label, text)
def run_message_stream(client, conv_id, content)
def main()
```

### scratch\test_regex.py
```
def main()
```
