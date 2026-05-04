# SigMap Query Context
Generated: 2026-05-04T09:59:55.714Z

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

## electron\hotkeys-renderer.js
```
function setStatus(text, kind = '')
function readForm()
function writeForm(values)
function formatRegistrations(registrations)
function getAcceleratorString(e)
async function load()
```

## electron\lib\config.js
```
module.exports = { defaultHotkeys, getHotkeyConfigPath, readHotkeys, writeHotkeys }
function getHotkeyConfigPath()
function readHotkeys()
function writeHotkeys(hotkeys)
```

## electron\lib\launcher.js
```
module.exports = { startStack, stopStack }
function resolvePowerShellPath()
function showError(title, message)
function runPowerShell(scriptPath, args = [])
function getScriptPath(scriptName)
function startStack({ noBrowser = true } = {})
function stopStack()
```

## electron\lib\logger.js
```
module.exports = { getLogsDir, appendLog }
function ensureDir(dir)
function getLogsDir()
function appendLog(message)
```
