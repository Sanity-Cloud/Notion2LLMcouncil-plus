$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Import-Module (Join-Path $RepoRoot "scripts\lib\CouncilSettingsUtils.psm1") -Force

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-TestSettings {
    return [PSCustomObject]@{
        custom_endpoint_url = "http://127.0.0.1:8120/v1"
        custom_endpoint_api_key = "CaseSensitiveKey123"
        enabled_providers = [PSCustomObject]@{
            openrouter = $false
            ollama = $false
            groq = $false
            direct = $false
            custom = $true
        }
    }
}

$expectedUrl = "http://localhost:8120/v1/"
$expectedKey = "CaseSensitiveKey123"

$ok = Test-CouncilProviderSettings -Settings (New-TestSettings) -ExpectedUrl $expectedUrl -ExpectedApiKey $expectedKey
Assert-True -Condition $ok.Ok -Message "Expected localhost/trailing-slash URL normalization to pass."
Assert-True -Condition ($ok.Issues.Count -eq 0) -Message "Expected correct provider settings to produce no repair issues."

$staleKey = New-TestSettings
$staleKey.custom_endpoint_api_key = "casesensitivekey123"
$staleKeyResult = Test-CouncilProviderSettings -Settings $staleKey -ExpectedUrl $expectedUrl -ExpectedApiKey $expectedKey
Assert-True -Condition (-not $staleKeyResult.Ok) -Message "Expected case-changed API key to fail exact comparison."
Assert-True -Condition (($staleKeyResult.Issues -join "; ") -notmatch [regex]::Escape($expectedKey)) -Message "API key leaked in key-mismatch diagnostic."
Assert-True -Condition (($staleKeyResult.Issues -join "; ") -match "length") -Message "Expected sanitized key length diagnostic."
try {
    Test-CouncilProviderSettingsOrThrow -Settings $staleKey -ExpectedUrl $expectedUrl -ExpectedApiKey $expectedKey
    throw "Expected throwing provider check to fail on stale key."
} catch {
    Assert-True -Condition ($_.Exception.Message -notmatch [regex]::Escape($expectedKey)) -Message "API key leaked in thrown mismatch diagnostic."
}

$wrongUrl = New-TestSettings
$wrongUrl.custom_endpoint_url = "http://127.0.0.1:9999/v1"
$wrongUrlResult = Test-CouncilProviderSettings -Settings $wrongUrl -ExpectedUrl $expectedUrl -ExpectedApiKey $expectedKey
Assert-True -Condition (-not $wrongUrlResult.Ok) -Message "Expected wrong provider URL to fail."
Assert-True -Condition (($wrongUrlResult.Issues -join "; ") -match "custom_endpoint_url") -Message "Expected URL mismatch diagnostic."

$httpsUrl = New-TestSettings
$httpsUrl.custom_endpoint_url = "https://127.0.0.1:8120/v1"
$httpsUrlResult = Test-CouncilProviderSettings -Settings $httpsUrl -ExpectedUrl $expectedUrl -ExpectedApiKey $expectedKey
Assert-True -Condition (-not $httpsUrlResult.Ok) -Message "Expected different URL scheme to fail."

$pathCaseUrl = New-TestSettings
$pathCaseUrl.custom_endpoint_url = "http://127.0.0.1:8120/V1"
$pathCaseUrlResult = Test-CouncilProviderSettings -Settings $pathCaseUrl -ExpectedUrl $expectedUrl -ExpectedApiKey $expectedKey
Assert-True -Condition (-not $pathCaseUrlResult.Ok) -Message "Expected different URL path casing to fail."

$disabled = New-TestSettings
$disabled.enabled_providers.custom = $false
$disabledResult = Test-CouncilProviderSettings -Settings $disabled -ExpectedUrl $expectedUrl -ExpectedApiKey $expectedKey
Assert-True -Condition (-not $disabledResult.Ok) -Message "Expected disabled custom provider to fail."
Assert-True -Condition (($disabledResult.Issues -join "; ") -match "not enabled") -Message "Expected disabled provider diagnostic."

$empty = Test-CouncilProviderSettings -Settings $null -ExpectedUrl $expectedUrl -ExpectedApiKey $expectedKey
Assert-True -Condition (-not $empty.Ok) -Message "Expected missing settings payload to fail."

Write-Host "CouncilSettingsUtils tests passed."
