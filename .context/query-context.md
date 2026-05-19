# SigMap Query Context
Generated: 2026-05-19T06:36:16.383Z

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

## electron\lib\diagnostics.js
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

## electron\lib\integration-config.js
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

## electron\windows\main.js
```
module.exports = { createMainWindow, getMainWindow, showMainWindow, toggleMainWindow }
function createMainWindow(councilUiUrl)
function getMainWindow()
function showMainWindow()
function toggleMainWindow()
```
