param(
    [string]$ConfigPath = "",
    [string]$NotionRoot = "X:\Code\notion2api-pub",
    [string]$CouncilRoot = "X:\Code\llm-council-plus",
    [int]$NotionPort = 8000,
    [int]$CouncilBackendPort = 8001,
    [int]$CouncilFrontendPort = 5173,
    [string]$NotionRepoUrl = "https://github.com/Sanity-Cloud/notion2api.git",
    [string]$NotionBranch = "feat/login-cdp",
    [string]$CouncilRepoUrl = "https://github.com/jacob-bd/llm-council-plus.git",
    [string]$CouncilBranch = "main",
    [switch]$UseVendor,
    [switch]$RefreshLogin,
    [switch]$NoBrowser,
    [switch]$Stop
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$VendorRoot = Join-Path $RepoRoot "vendor"
$LogDir = Join-Path $RepoRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $VendorRoot | Out-Null
$BoundParameters = @($PSBoundParameters.Keys)

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return $null
    }
    return Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function Use-ConfigValue {
    param(
        $Value,
        $Fallback
    )
    if ($null -eq $Value -or "$Value" -eq "") {
        return $Fallback
    }
    return $Value
}

function Read-IntegrationConfig {
    $defaultPath = Join-Path $RepoRoot "config\default.json"
    $localPath = if ($ConfigPath) { $ConfigPath } else { Join-Path $RepoRoot "config\local.json" }

    $defaultConfig = Read-JsonFile -Path $defaultPath
    $localConfig = Read-JsonFile -Path $localPath

    if ($localConfig) {
        Write-Step "Using local config $localPath"
    }

    return @{
        Default = $defaultConfig
        Local = $localConfig
    }
}

function Get-ConfigProperty {
    param(
        [hashtable]$Config,
        [string[]]$Path,
        $Fallback = $null
    )

    foreach ($source in @($Config.Local, $Config.Default)) {
        $cursor = $source
        foreach ($part in $Path) {
            if ($null -eq $cursor -or -not ($cursor.PSObject.Properties.Name -contains $part)) {
                $cursor = $null
                break
            }
            $cursor = $cursor.$part
        }
        if ($null -ne $cursor -and "$cursor" -ne "") {
            return $cursor
        }
    }
    return $Fallback
}

function ConvertTo-StringArray {
    param($Value)
    if ($null -eq $Value) {
        return @()
    }
    return @($Value | ForEach-Object { [string]$_ })
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

$Config = Read-IntegrationConfig
if (-not ($BoundParameters -contains "NotionRoot")) {
    $NotionRoot = Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "localRoot")) -Fallback $NotionRoot
}
if (-not ($BoundParameters -contains "CouncilRoot")) {
    $CouncilRoot = Use-ConfigValue -Value (Get-ConfigProperty $Config @("council", "localRoot")) -Fallback $CouncilRoot
}
if (-not ($BoundParameters -contains "NotionRepoUrl")) {
    $NotionRepoUrl = Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "repoUrl")) -Fallback $NotionRepoUrl
}
if (-not ($BoundParameters -contains "NotionBranch")) {
    $NotionBranch = Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "branch")) -Fallback $NotionBranch
}
if (-not ($BoundParameters -contains "CouncilRepoUrl")) {
    $CouncilRepoUrl = Use-ConfigValue -Value (Get-ConfigProperty $Config @("council", "repoUrl")) -Fallback $CouncilRepoUrl
}
if (-not ($BoundParameters -contains "CouncilBranch")) {
    $CouncilBranch = Use-ConfigValue -Value (Get-ConfigProperty $Config @("council", "branch")) -Fallback $CouncilBranch
}
if (-not ($BoundParameters -contains "NotionPort")) {
    $NotionPort = [int](Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "port")) -Fallback $NotionPort)
}
if (-not ($BoundParameters -contains "CouncilBackendPort")) {
    $CouncilBackendPort = [int](Use-ConfigValue -Value (Get-ConfigProperty $Config @("council", "backendPort")) -Fallback $CouncilBackendPort)
}
if (-not ($BoundParameters -contains "CouncilFrontendPort")) {
    $CouncilFrontendPort = [int](Use-ConfigValue -Value (Get-ConfigProperty $Config @("council", "frontendPort")) -Fallback $CouncilFrontendPort)
}
$ProviderName = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "name")) -Fallback "Notion2API"
$ProviderEnabledKey = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "enabledKey")) -Fallback "custom"
$ProviderUrlPath = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "urlPath")) -Fallback "/v1"
$ConfiguredCouncilModels = ConvertTo-StringArray (Get-ConfigProperty $Config @("provider", "councilModels"))
$ConfiguredChairmanModel = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "chairmanModel")) -Fallback "custom:claude-opus4.7"

if ($UseVendor) {
    $NotionRoot = Join-Path $VendorRoot "notion2api"
    $CouncilRoot = Join-Path $VendorRoot "llm-council-plus"
}

function Ensure-Repo {
    param(
        [string]$Path,
        [string]$Url,
        [string]$Branch = ""
    )

    if (Test-Path $Path) {
        return
    }

    $parent = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Write-Step "Cloning $Url to $Path"
    if ($Branch) {
        git clone --branch $Branch $Url $Path
    } else {
        git clone $Url $Path
    }
}

function Get-Python {
    param([string]$Root)
    $venvPython = Join-Path $Root ".venv\Scripts\python.exe"
    if (Test-Path $venvPython) {
        return $venvPython
    }
    return "python"
}

function Stop-ProjectProcesses {
    $currentPid = $PID
    $patterns = @(
        [regex]::Escape((Resolve-Path $NotionRoot).Path),
        [regex]::Escape((Resolve-Path $CouncilRoot).Path)
    )
    $targets = Get-CimInstance Win32_Process | Where-Object {
        $_.ProcessId -ne $currentPid -and
        $_.CommandLine -and
        (
            ($_.CommandLine -match $patterns[0] -and $_.CommandLine -match "uvicorn.*app\.server") -or
            ($_.CommandLine -match $patterns[1] -and $_.CommandLine -match "backend\.main|vite|npm run dev")
        )
    }

    foreach ($target in $targets) {
        Write-Host "Stopping PID $($target.ProcessId): $($target.CommandLine)"
        Stop-Process -Id $target.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Set-EnvLine {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    $lines = if (Test-Path $Path) { @(Get-Content -Path $Path) } else { @() }
    $updated = $false
    $newLines = foreach ($line in $lines) {
        if ($line.TrimStart().StartsWith("$Name=")) {
            $updated = $true
            "$Name=$Value"
        } else {
            $line
        }
    }
    if (-not $updated) {
        $newLines += "$Name=$Value"
    }
    Set-Content -Path $Path -Value $newLines -Encoding UTF8
}

function Ensure-NotionMode {
    Set-EnvLine -Path (Join-Path $NotionRoot ".env") -Name "APP_MODE" -Value "standard"
}

function Test-NotionLogin {
    $python = Get-Python -Root $NotionRoot
    Push-Location $NotionRoot
    try {
        & $python "login.py" "--check"
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
}

function Ensure-NotionLogin {
    if (-not (Test-Path (Join-Path $NotionRoot "login.py"))) {
        throw "Notion2API checkout does not contain login.py. Use a branch/release with the auto-login helper."
    }

    if (-not $RefreshLogin -and (Test-NotionLogin)) {
        Write-Step "Notion token is valid"
        return
    }

    Write-Step "Refreshing Notion login session"
    $python = Get-Python -Root $NotionRoot
    Push-Location $NotionRoot
    try {
        & $python "login.py" "--timeout" "300"
        if ($LASTEXITCODE -ne 0) {
            throw "Notion login did not complete successfully."
        }
    } finally {
        Pop-Location
    }

    if (-not (Test-NotionLogin)) {
        throw "Notion token check still fails after login."
    }
}

function Wait-HttpOk {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 45
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        } catch {
            Start-Sleep -Milliseconds 750
        }
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for $Url"
}

function Start-NotionApi {
    $python = Get-Python -Root $NotionRoot
    $out = Join-Path $LogDir "notion2api.out.log"
    $err = Join-Path $LogDir "notion2api.err.log"
    Remove-Item $out, $err -ErrorAction SilentlyContinue

    Write-Step "Starting Notion2API on http://127.0.0.1:$NotionPort"
    Start-Process -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "app.server:app", "--host", "127.0.0.1", "--port", "$NotionPort") `
        -WorkingDirectory $NotionRoot `
        -RedirectStandardOutput $out `
        -RedirectStandardError $err `
        -WindowStyle Hidden | Out-Null
    Wait-HttpOk -Url "http://127.0.0.1:$NotionPort/health"
}

function Start-CouncilBackend {
    $python = Get-Python -Root $CouncilRoot
    $out = Join-Path $LogDir "council-backend.out.log"
    $err = Join-Path $LogDir "council-backend.err.log"
    Remove-Item $out, $err -ErrorAction SilentlyContinue

    Write-Step "Starting LLM Council backend on http://127.0.0.1:$CouncilBackendPort"
    Start-Process -FilePath $python `
        -ArgumentList @("-m", "backend.main") `
        -WorkingDirectory $CouncilRoot `
        -RedirectStandardOutput $out `
        -RedirectStandardError $err `
        -WindowStyle Hidden | Out-Null
    Wait-HttpOk -Url "http://127.0.0.1:$CouncilBackendPort/api/settings"
}

function Apply-CouncilProviderSettings {
    $settingsUrl = "http://127.0.0.1:$CouncilBackendPort/api/settings"
    $current = Invoke-RestMethod -Method Get -Uri $settingsUrl -TimeoutSec 10

    $enabled = @{}
    if ($current.enabled_providers) {
        foreach ($property in $current.enabled_providers.PSObject.Properties) {
            $enabled[$property.Name] = [bool]$property.Value
        }
    }
    $enabled[$ProviderEnabledKey] = $true

    $councilModels = @($current.council_models)
    if ($ConfiguredCouncilModels.Count -gt 0 -and (
        $councilModels.Count -lt 2 -or -not ($councilModels | Where-Object { $_ -like "$($ProviderEnabledKey):*" })
    )) {
        $councilModels = $ConfiguredCouncilModels
    }

    $chairmanModel = [string]$current.chairman_model
    if (-not $chairmanModel -or $chairmanModel -notlike "$($ProviderEnabledKey):*") {
        $chairmanModel = $ConfiguredChairmanModel
    }

    $providerUrl = "http://127.0.0.1:$NotionPort$ProviderUrlPath"
    $body = @{
        custom_endpoint_name = $ProviderName
        custom_endpoint_url = $providerUrl
        enabled_providers = $enabled
        council_models = $councilModels
        chairman_model = $chairmanModel
    } | ConvertTo-Json -Depth 20

    Write-Step "Configuring LLM Council custom provider"
    Invoke-RestMethod -Method Put -Uri $settingsUrl -ContentType "application/json" -Body $body -TimeoutSec 20 | Out-Null
}

function Start-CouncilFrontend {
    $frontendRoot = Join-Path $CouncilRoot "frontend"
    $out = Join-Path $LogDir "council-frontend.out.log"
    $err = Join-Path $LogDir "council-frontend.err.log"
    Remove-Item $out, $err -ErrorAction SilentlyContinue

    Write-Step "Starting LLM Council frontend on http://127.0.0.1:$CouncilFrontendPort"
    Start-Process -FilePath "npm.cmd" `
        -ArgumentList @("run", "dev", "--", "--host", "127.0.0.1", "--port", "$CouncilFrontendPort") `
        -WorkingDirectory $frontendRoot `
        -RedirectStandardOutput $out `
        -RedirectStandardError $err `
        -WindowStyle Hidden | Out-Null
    Wait-HttpOk -Url "http://127.0.0.1:$CouncilFrontendPort/"
}

Ensure-Repo -Path $NotionRoot -Url $NotionRepoUrl -Branch $NotionBranch
Ensure-Repo -Path $CouncilRoot -Url $CouncilRepoUrl -Branch $CouncilBranch
$NotionRoot = (Resolve-Path $NotionRoot).Path
$CouncilRoot = (Resolve-Path $CouncilRoot).Path

if ($Stop) {
    Write-Step "Stopping launcher-managed services"
    Stop-ProjectProcesses
    exit 0
}

Write-Step "Preparing Notion2API + LLM Council"
Ensure-NotionMode
Ensure-NotionLogin
Stop-ProjectProcesses
Start-Sleep -Seconds 1
Start-NotionApi
Start-CouncilBackend
Apply-CouncilProviderSettings
Start-CouncilFrontend

Write-Host ""
Write-Host "Ready:"
Write-Host "  Notion2API:        http://127.0.0.1:$NotionPort"
Write-Host "  LLM Council API:   http://127.0.0.1:$CouncilBackendPort"
Write-Host "  LLM Council UI:    http://127.0.0.1:$CouncilFrontendPort"
Write-Host "  Logs:              $LogDir"
Write-Host ""
Write-Host "Stop later with:"
Write-Host "  .\stop.bat"

if (-not $NoBrowser) {
    Start-Process "http://127.0.0.1:$CouncilFrontendPort/"
}
