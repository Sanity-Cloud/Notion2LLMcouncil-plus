# SigMap Query Context
Generated: 2026-05-28T22:28:57.942Z

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

## electron\lib\launcher.js
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

## electron\main.js
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

## electron\hotkeys.html
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

## electron\lib\config.js
```
module.exports = { defaultHotkeys, getHotkeyConfigPath, readHotkeys, writeHotkeys }
function getHotkeyConfigPath()
function readHotkeys()
function writeHotkeys(hotkeys)
```
