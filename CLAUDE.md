

## Auto-generated signatures
<!-- Updated by gen-context.js -->
# Code signatures

## changes (last 5 commits — 1 second ago)
```
.github\copilot-instructions.md               +setStatus  +readForm  +writeForm  +formatRegistrations
.github\gemini-context.md                     +setStatus  +readForm  +writeForm  +formatRegistrations
```

## .github

### .github\copilot-instructions.md
```
h2 Auto-generated signatures
h2 SigMap commands
h1 Code signatures
h2 electron
h3 electron\hotkeys-renderer.js
h3 electron\hotkeys.html
h3 electron\main.js
h3 electron\lib\config.js
h3 electron\lib\launcher.js
h3 electron\lib\logger.js
h3 electron\lib\utils.js
h3 electron\windows\hotkeys.js
h3 electron\windows\main.js
code-fence plain
```

### .github\gemini-context.md
```
h2 Auto-generated signatures
h2 Code Signatures
h2 electron
h3 electron\hotkeys-renderer.js
h3 electron\hotkeys.html
h3 electron\main.js
h3 electron\lib\config.js
h3 electron\lib\launcher.js
h3 electron\lib\logger.js
h3 electron\lib\utils.js
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
input#clipboardToChat
input#openHotkeySettings
button#save
button#reset
button#testClipboard
button#reload
div#status
div#path
```

### electron\main.js
```
async function focusChatInput(text)
async function openChat()
async function openChatWithClipboard()
function createTray()
function refreshTrayMenu()
function setApplicationMenu()
function registerHotkeys()
```

### electron\lib\config.js
```
module.exports = { defaultHotkeys, getHotkeyConfigPath, readHotkeys, writeHotkeys }
function getHotkeyConfigPath()
function readHotkeys()
function writeHotkeys(hotkeys)
```

### electron\lib\launcher.js
```
module.exports = { startStack, stopStack }
function resolvePowerShellPath()
function showError(title, message)
function runPowerShell(scriptPath, args = [])
function getScriptPath(scriptName)
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
module.exports = { ensureDir, getAppRoot, waitForUrl }
function ensureDir(dir)
function directoryHasLaunchScript(dir)
function getAppRoot()
function waitForUrl(url, timeoutMs = 90000, options = {})
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
