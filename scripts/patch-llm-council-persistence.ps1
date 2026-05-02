param(
    [string]$CouncilRoot = "X:\Code\llm-council-plus"
)

$ErrorActionPreference = "Stop"

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }
    $backup = "$Path.bak_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $Path $backup -Force
    Write-Host "Backup: $backup"
}

function Replace-Required {
    param(
        [string]$Path,
        [string]$Old,
        [string]$New,
        [string]$Label
    )
    $text = Get-Content $Path -Raw
    if ($text.Contains($New)) {
        Write-Host "Already patched: $Label"
        return
    }
    if (-not $text.Contains($Old)) {
        Write-Warning "Pattern not found for: $Label"
        return
    }
    $text = $text.Replace($Old, $New)
    Set-Content -Path $Path -Value $text -Encoding UTF8
    Write-Host "Patched: $Label"
}

$AppPath = Join-Path $CouncilRoot "frontend\src\App.jsx"
$SettingsPath = Join-Path $CouncilRoot "frontend\src\components\Settings.jsx"
$ProviderPath = Join-Path $CouncilRoot "frontend\src\components\settings\ProviderSettings.jsx"

Backup-File $AppPath
Backup-File $SettingsPath
Backup-File $ProviderPath

$oldHasApiKey = @'
      const hasApiKey = settings.openrouter_api_key_set ||
        settings.groq_api_key_set ||
        settings.openai_api_key_set ||
        settings.anthropic_api_key_set ||
        settings.google_api_key_set ||
        settings.mistral_api_key_set ||
        settings.deepseek_api_key_set;
'@

$newHasApiKey = @'
      const hasCustomEndpoint =
        settings.custom_endpoint_api_key_set &&
        settings.custom_endpoint_name &&
        settings.custom_endpoint_url &&
        settings.enabled_providers?.custom;

      const hasApiKey = hasCustomEndpoint ||
        settings.openrouter_api_key_set ||
        settings.groq_api_key_set ||
        settings.openai_api_key_set ||
        settings.anthropic_api_key_set ||
        settings.google_api_key_set ||
        settings.mistral_api_key_set ||
        settings.deepseek_api_key_set;
'@
Replace-Required -Path $AppPath -Old $oldHasApiKey -New $newHasApiKey -Label "App.jsx counts custom endpoint as configured"

$oldCustomSave = @'
        await api.updateSettings({
          custom_endpoint_name: customEndpointName,
          custom_endpoint_url: customEndpointUrl,
          custom_endpoint_api_key: customEndpointApiKey || null
        });
'@

$newCustomSave = @'
        const updatePayload = {
          custom_endpoint_name: customEndpointName,
          custom_endpoint_url: customEndpointUrl
        };

        // The backend intentionally does not send existing API keys back to the UI.
        // Preserve an already-configured key when the password field is blank.
        if (customEndpointApiKey) {
          updatePayload.custom_endpoint_api_key = customEndpointApiKey;
        }

        await api.updateSettings(updatePayload);
'@
Replace-Required -Path $SettingsPath -Old $oldCustomSave -New $newCustomSave -Label "Settings.jsx preserves custom endpoint API key when field is blank"

$oldPlaceholder = @'
                            placeholder={settings?.custom_endpoint_url ? '••••••••••••••••' : 'Enter API key'}
'@
$newPlaceholder = @'
                            placeholder={settings?.custom_endpoint_api_key_set ? '••••••••••••••••' : 'Enter API key'}
'@
Replace-Required -Path $ProviderPath -Old $oldPlaceholder -New $newPlaceholder -Label "ProviderSettings.jsx placeholder uses custom_endpoint_api_key_set"

$oldInputClass = @'
                        />
'@
$newInputClass = @'
                            className={settings?.custom_endpoint_api_key_set && !customEndpointApiKey ? 'key-configured' : ''}
                        />
'@
# Only patch the first matching closing input after the custom endpoint API key placeholder by using a targeted regex.
$text = Get-Content $ProviderPath -Raw
if ($text -notmatch "custom_endpoint_api_key_set && !customEndpointApiKey") {
    $pattern = "(?s)(<input\s+type=\"password\"\s+placeholder=\{settings\?\.custom_endpoint_api_key_set \? '••••••••••••••••' : 'Enter API key'\}.*?onChange=\{\(e\) => \{\s*setCustomEndpointApiKey\(e\.target\.value\);\s*// setCustomEndpointTestResult\(null\); // Missing prop\s*\}\}\s*)/>"
    $replacement = '$1className={settings?.custom_endpoint_api_key_set && !customEndpointApiKey ? ''key-configured'' : ''''}\n                        />'
    $newText = [regex]::Replace($text, $pattern, $replacement, 1)
    if ($newText -ne $text) {
        Set-Content -Path $ProviderPath -Value $newText -Encoding UTF8
        Write-Host "Patched: ProviderSettings.jsx marks saved custom API key as configured"
    } else {
        Write-Warning "Could not add custom endpoint API key className automatically."
    }
} else {
    Write-Host "Already patched: ProviderSettings.jsx custom API key className"
}

$text = Get-Content $ProviderPath -Raw
$needle = @'
                    {settings?.custom_endpoint_url && (
                        <div className="key-status set">
                            ✓ Endpoint configured
                            {customEndpointModels.length > 0 && ` · ${customEndpointModels.length} models available`}
                        </div>
                    )}
'@
$insert = @'
                    {settings?.custom_endpoint_api_key_set && !customEndpointApiKey && (
                        <div className="key-status set">✓ API key configured</div>
                    )}

                    {settings?.custom_endpoint_url && (
                        <div className="key-status set">
                            ✓ Endpoint configured
                            {customEndpointModels.length > 0 && ` · ${customEndpointModels.length} models available`}
                        </div>
                    )}
'@
if ($text.Contains("✓ API key configured</div>")) {
    Write-Host "Already patched: ProviderSettings.jsx displays custom API key configured status"
} elseif ($text.Contains($needle)) {
    $text = $text.Replace($needle, $insert)
    Set-Content -Path $ProviderPath -Value $text -Encoding UTF8
    Write-Host "Patched: ProviderSettings.jsx displays custom API key configured status"
} else {
    Write-Warning "Could not find custom endpoint status block."
}

Write-Host ""
Write-Host "Done. Restart the stack:"
Write-Host "  cd X:\Code\Notion2LLMcouncil-plus"
Write-Host "  .\stop.bat"
Write-Host "  .\launch.bat"
Pause
