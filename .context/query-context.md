# SigMap Query Context
Generated: 2026-05-30T01:48:39.586Z

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

## .github\copilot-instructions.md
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
```

## .github\gemini-context.md
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

## .github\workflows\release.yml
```
keys: [name, on, permissions, env, jobs]
job: build-windows
```
