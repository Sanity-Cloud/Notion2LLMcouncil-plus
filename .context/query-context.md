# SigMap Query Context
Generated: 2026-05-24T03:06:59.534Z

## .github\workflows\validate.yml
```
keys: [name, on, permissions, jobs]
job: validate
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

## .github\gemini-context.md
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
