# SigMap Query Context
Generated: 2026-05-21T06:35:54.097Z

## electron\diagnostics.html
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
```

## electron\lib\utils.js
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

## electron\main.js
```
async function focusChatInput(text, submit = false)
async function ensureChatInputReady()
async function clearCouncilUiStorage()
async function getActiveRuntimeUrls(timeoutMs = 90000)
async function isRuntimeReady(urls, timeoutMs = 2500)
async function waitForReadyRuntimeUrls()
async function openChat()
async function openChatWithClipboard()
async function createNewChatInputReady()
async function openNewChat()
async function openNewChatWithClipboard()
function createTray()
function refreshTrayMenu()
function setApplicationMenu()
function registerHotkeys()
```

## electron\windows\main.js
```
module.exports = { createMainWindow, getMainWindow, showMainWindow, toggleMainWindow }
function createMainWindow(councilUiUrl)
function getMainWindow()
function showMainWindow()
function toggleMainWindow()
```

## .github\copilot-instructions.md
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
```
