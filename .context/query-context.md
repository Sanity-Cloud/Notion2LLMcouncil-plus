# SigMap Query Context
Generated: 2026-05-24T12:42:32.299Z

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

## electron\windows\hotkeys.js
```
module.exports = { openHotkeySettings }
function openHotkeySettings(parentWindow)
```

## .github\copilot-instructions.md
```
h2 Auto-generated signatures
h2 SigMap commands
h1 Code signatures
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
```

## .github\gemini-context.md
```
h2 Auto-generated signatures
h2 Code Signatures
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
```
