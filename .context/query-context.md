# SigMap Query Context
Generated: 2026-05-04T12:25:32.765Z

## .github\copilot-instructions.md
```
h2 Auto-generated signatures
h2 SigMap commands
h1 Code signatures
h2 changes (last 5 commits — 6 minutes ago)
h2 .github
h3 .github\copilot-instructions.md
h3 .github\gemini-context.md
h3 .github\workflows\release.yml
h3 .github\workflows\validate.yml
h2 electron
h3 electron\hotkeys-renderer.js
h3 electron\hotkeys.html
h3 electron\lib\config.js
h3 electron\lib\launcher.js
h3 electron\lib\logger.js
h3 electron\lib\utils.js
h3 electron\main.js
h3 electron\windows\hotkeys.js
h3 electron\windows\main.js
code-fence plain
```

## .github\gemini-context.md
```
h2 Auto-generated signatures
h2 Code Signatures
h2 changes (last 5 commits — 6 minutes ago)
h2 .github
h3 .github\copilot-instructions.md
h3 .github\gemini-context.md
h3 .github\workflows\release.yml
h3 .github\workflows\validate.yml
h2 electron
h3 electron\hotkeys-renderer.js
h3 electron\hotkeys.html
h3 electron\lib\config.js
h3 electron\lib\launcher.js
h3 electron\lib\logger.js
h3 electron\lib\utils.js
h3 electron\main.js
h3 electron\windows\hotkeys.js
h3 electron\windows\main.js
code-fence plain
```

## electron\hotkeys-renderer.js
```
function setStatus(text, kind = '')
function readForm()
function writeForm(values)
function formatRegistrations(registrations)
function getAcceleratorString(e)
async function load()
```

## electron\hotkeys.html
```
title: Notion2Council Hotkeys
input#toggleWindow
input#openChat
input#clipboardToChat
input#openHotkeySettings
button#save
button#reset
button#testClipboard
button#reload
div#status
div#path
```

## electron\windows\main.js
```
module.exports = { createMainWindow, getMainWindow, showMainWindow, toggleMainWindow }
function createMainWindow(councilUiUrl)
function getMainWindow()
function showMainWindow()
function toggleMainWindow()
```
