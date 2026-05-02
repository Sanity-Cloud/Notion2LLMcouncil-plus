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
    [switch]$SetupOnly,
    [switch]$Stop
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$VendorRoot = Join-Path $RepoRoot "vendor"
$LogDir = Join-Path $RepoRoot "logs"
$StateFile = Join-Path $LogDir "launcher-state.json"
$RestartNotionFlag = Join-Path $LogDir "restart-notion.flag"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $VendorRoot | Out-Null
$BoundParameters = @($PSBoundParameters.Keys)
$NotionApiKeyChanged = $false

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return $null
    }
    return Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function Use-ConfigValue {
    param($Value, $Fallback)
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

function Get-State {
    $state = Read-JsonFile -Path $StateFile
    if ($state) {
        return $state
    }
    return [pscustomobject]@{
        notion = $null
        councilBackend = $null
        councilFrontend = $null
    }
}

function Save-State {
    param($State)
    $State | ConvertTo-Json -Depth 20 | Set-Content -Path $StateFile -Encoding UTF8
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

function Test-HttpOk {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
    } catch {
        return $false
    }
}

function Wait-HttpOk {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 45
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-HttpOk -Url $Url) {
            return
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for $Url"
}

function Test-PortInUse {
    param([int]$Port)
    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    return [bool]($listeners | Where-Object { $_.Port -eq $Port })
}

function Get-ListeningProcessId {
    param([int]$Port)
    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
            Select-Object -First 1
        if ($connection) {
            return [int]$connection.OwningProcess
        }
    } catch {
        return 0
    }
    return 0
}

function Find-FreePort {
    param(
        [int]$PreferredPort,
        [int[]]$Alternates = @()
    )

    foreach ($candidate in @($PreferredPort) + $Alternates) {
        if (-not (Test-PortInUse -Port $candidate)) {
            return $candidate
        }
    }

    for ($candidate = $PreferredPort + 1; $candidate -lt $PreferredPort + 100; $candidate++) {
        if (-not (Test-PortInUse -Port $candidate)) {
            return $candidate
        }
    }

    throw "No free local port found near $PreferredPort."
}

function Stop-ProcessId {
    param([int]$ProcessId)
    if ($ProcessId -le 0 -or $ProcessId -eq $PID) {
        return
    }
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Stop-ManagedServices {
    $state = Get-State
    foreach ($service in @($state.councilFrontend, $state.councilBackend, $state.notion)) {
        if ($service -and $service.pid) {
            Write-Step "Stopping PID $($service.pid) for $($service.name)"
            Stop-ProcessId -ProcessId ([int]$service.pid)
        }
    }
    Remove-Item $StateFile -ErrorAction SilentlyContinue
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

function Get-EnvLineValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path $Path)) {
        return ""
    }

    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("#") -or -not $trimmed.StartsWith("$Name=")) {
            continue
        }
        return $trimmed.Substring($Name.Length + 1).Trim('"').Trim("'")
    }
    return ""
}

function New-ApiKey {
    $bytes = [byte[]]::new(32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function Ensure-NotionApiKey {
    $envPath = Join-Path $NotionRoot ".env"
    $existing = Get-EnvLineValue -Path $envPath -Name "API_KEY"
    if ($existing) {
        Write-Step "Notion2API API key is configured"
        return $existing
    }

    $generated = "n2c_" + (New-ApiKey)
    Set-EnvLine -Path $envPath -Name "API_KEY" -Value $generated
    $script:NotionApiKeyChanged = $true
    Set-Content -Path $RestartNotionFlag -Value "api-key-generated" -Encoding UTF8
    Write-Step "Generated Notion2API API key for the local integration"
    return $generated
}

function Ensure-NotionMode {
    Set-EnvLine -Path (Join-Path $NotionRoot ".env") -Name "APP_MODE" -Value $NotionAppMode
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

    if (-not $NotionAutoLogin) {
        throw "Notion login is invalid and autoLogin is disabled. Run .\launch.bat -RefreshLogin or enable notion.autoLogin."
    }

    Write-Step "Refreshing Notion login session"
    $python = Get-Python -Root $NotionRoot
    Push-Location $NotionRoot
    try {
        & $python "login.py" "--timeout" "$NotionLoginTimeoutSeconds"
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

function Start-NotionApi {
    param($State)
    $healthUrl = "http://127.0.0.1:$NotionPort/health"
    if (Test-HttpOk -Url $healthUrl) {
        if ($NotionApiKeyChanged -or (Test-Path $RestartNotionFlag)) {
            $pidToStop = Get-ListeningProcessId -Port $NotionPort
            if ($pidToStop) {
                Write-Step "Restarting Notion2API so the configured API key is active"
                Stop-ProcessId -ProcessId $pidToStop
                Start-Sleep -Seconds 1
            }
            Remove-Item $RestartNotionFlag -ErrorAction SilentlyContinue
        } else {
        Write-Step "Reusing Notion2API on http://127.0.0.1:$NotionPort"
        $State.notion = @{
            name = "Notion2API"
            pid = Get-ListeningProcessId -Port $NotionPort
            port = $NotionPort
            url = "http://127.0.0.1:$NotionPort"
        }
        return $State
        }
    }

    if (Test-PortInUse -Port $NotionPort) {
        $oldPort = $NotionPort
        $script:NotionPort = Find-FreePort -PreferredPort $NotionPort
        Write-Step "Port $oldPort is busy; using Notion2API port $NotionPort"
    }

    $python = Get-Python -Root $NotionRoot
    $out = Join-Path $LogDir "notion2api.out.log"
    $err = Join-Path $LogDir "notion2api.err.log"
    Remove-Item $out, $err -ErrorAction SilentlyContinue

    Write-Step "Starting Notion2API on http://127.0.0.1:$NotionPort"
    $process = Start-Process -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "app.server:app", "--host", "127.0.0.1", "--port", "$NotionPort") `
        -WorkingDirectory $NotionRoot `
        -RedirectStandardOutput $out `
        -RedirectStandardError $err `
        -WindowStyle Hidden `
        -PassThru
    Wait-HttpOk -Url "http://127.0.0.1:$NotionPort/health"
    $State.notion = @{
        name = "Notion2API"
        pid = $process.Id
        port = $NotionPort
        url = "http://127.0.0.1:$NotionPort"
    }
    return $State
}

function Start-CouncilBackend {
    param($State)
    $settingsUrl = "http://127.0.0.1:$CouncilBackendPort/api/settings"
    if (Test-HttpOk -Url $settingsUrl) {
        Write-Step "Reusing LLM Council backend on http://127.0.0.1:$CouncilBackendPort"
        $State.councilBackend = @{
            name = "LLM Council backend"
            pid = Get-ListeningProcessId -Port $CouncilBackendPort
            port = $CouncilBackendPort
            url = "http://127.0.0.1:$CouncilBackendPort"
        }
        return $State
    }

    if (Test-PortInUse -Port $CouncilBackendPort) {
        $oldPort = $CouncilBackendPort
        $script:CouncilBackendPort = Find-FreePort -PreferredPort $CouncilBackendPort
        Write-Step "Port $oldPort is busy; using LLM Council backend port $CouncilBackendPort"
    }

    $python = Get-Python -Root $CouncilRoot
    $out = Join-Path $LogDir "council-backend.out.log"
    $err = Join-Path $LogDir "council-backend.err.log"
    Remove-Item $out, $err -ErrorAction SilentlyContinue

    Write-Step "Starting LLM Council backend on http://127.0.0.1:$CouncilBackendPort"
    $env:LLM_COUNCIL_ENABLE_SHUTDOWN = "1"
    $env:NOTION2COUNCIL_STOP_SCRIPT = (Join-Path $RepoRoot "stop.bat")
    $process = Start-Process -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "backend.main:app", "--host", "127.0.0.1", "--port", "$CouncilBackendPort") `
        -WorkingDirectory $CouncilRoot `
        -RedirectStandardOutput $out `
        -RedirectStandardError $err `
        -WindowStyle Hidden `
        -PassThru
    Wait-HttpOk -Url "http://127.0.0.1:$CouncilBackendPort/api/settings"
    $State.councilBackend = @{
        name = "LLM Council backend"
        pid = $process.Id
        port = $CouncilBackendPort
        url = "http://127.0.0.1:$CouncilBackendPort"
    }
    return $State
}

function Apply-CouncilProviderSettings {
    param([string]$NotionApiKey)

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
    if ($ProviderApplyDefaultCouncil -and $ConfiguredCouncilModels.Count -gt 0) {
        $councilModels = $ConfiguredCouncilModels
    } elseif ($ConfiguredCouncilModels.Count -gt 0 -and (
        $councilModels.Count -lt 2 -or -not ($councilModels | Where-Object { $_ -like "$($ProviderEnabledKey):*" })
    )) {
        $councilModels = $ConfiguredCouncilModels
    }

    $chairmanModel = [string]$current.chairman_model
    if ($ProviderApplyDefaultCouncil) {
        $chairmanModel = $ConfiguredChairmanModel
    } elseif (-not $chairmanModel -or $chairmanModel -notlike "$($ProviderEnabledKey):*") {
        $chairmanModel = $ConfiguredChairmanModel
    }

    $providerUrl = "http://127.0.0.1:$NotionPort$ProviderUrlPath"
    $bodyData = @{
        custom_endpoint_name = $ProviderName
        custom_endpoint_url = $providerUrl
        custom_endpoint_api_key = $NotionApiKey
        enabled_providers = $enabled
        council_models = $councilModels
        chairman_model = $chairmanModel
        council_member_filters = $ConfiguredCouncilMemberFilters
        chairman_filter = $ConfiguredChairmanFilter
        search_query_filter = $ConfiguredSearchQueryFilter
    }
    if (-not $NotionApiKey) {
        $bodyData.Remove("custom_endpoint_api_key")
    }
    $body = $bodyData | ConvertTo-Json -Depth 20

    Write-Step "Configuring LLM Council custom provider"
    if ($ProviderSupportsStreaming) {
        Write-Step "Notion2API streaming is available for clients that send stream=true"
    }
    Invoke-RestMethod -Method Put -Uri $settingsUrl -ContentType "application/json" -Body $body -TimeoutSec 20 | Out-Null
}

function Test-CouncilProviderConnection {
    param([string]$NotionApiKey)

    $providerUrl = "http://127.0.0.1:$NotionPort$ProviderUrlPath"
    $testUrl = "http://127.0.0.1:$CouncilBackendPort/api/settings/test-custom-endpoint"
    $body = @{
        name = $ProviderName
        url = $providerUrl
        api_key = $NotionApiKey
    } | ConvertTo-Json -Depth 10

    Write-Step "Testing LLM Council connection to Notion2API provider"
    $result = Invoke-RestMethod -Method Post -Uri $testUrl -ContentType "application/json" -Body $body -TimeoutSec 20
    if (-not $result.success) {
        throw "LLM Council could not connect to Notion2API provider: $($result.message)"
    }
    Write-Step "Notion2API provider connection is ready"
}

function Start-CouncilFrontend {
    param($State)
    $allowedPorts = @($CouncilFrontendPort, 5173, 5174, 3000) | Select-Object -Unique
    foreach ($candidate in $allowedPorts) {
        if (Test-HttpOk -Url "http://127.0.0.1:$candidate/") {
            $script:CouncilFrontendPort = $candidate
            Write-Step "Reusing LLM Council frontend on http://127.0.0.1:$CouncilFrontendPort"
            $State.councilFrontend = @{
                name = "LLM Council frontend"
                pid = Get-ListeningProcessId -Port $CouncilFrontendPort
                port = $CouncilFrontendPort
                url = "http://127.0.0.1:$CouncilFrontendPort"
            }
            return $State
        }
    }

    if (Test-PortInUse -Port $CouncilFrontendPort) {
        foreach ($candidate in $allowedPorts) {
            if (-not (Test-PortInUse -Port $candidate)) {
                $script:CouncilFrontendPort = $candidate
                break
            }
        }
        if (Test-PortInUse -Port $CouncilFrontendPort) {
            throw "Frontend ports 5173, 5174, and 3000 are already in use."
        }
    }

    $frontendRoot = Join-Path $CouncilRoot "frontend"
    $envFile = Join-Path $frontendRoot ".env.local"
    $out = Join-Path $LogDir "council-frontend.out.log"
    $err = Join-Path $LogDir "council-frontend.err.log"
    Remove-Item $out, $err -ErrorAction SilentlyContinue

    Set-Content -Path $envFile -Encoding UTF8 -Value @(
        "VITE_API_URL=http://127.0.0.1:$CouncilBackendPort",
        "VITE_ENABLE_LOCAL_SHUTDOWN=true"
    )

    Write-Step "Starting LLM Council frontend on http://127.0.0.1:$CouncilFrontendPort"
    $process = Start-Process -FilePath "npm.cmd" `
        -ArgumentList @("run", "dev", "--", "--host", "127.0.0.1", "--port", "$CouncilFrontendPort") `
        -WorkingDirectory $frontendRoot `
        -RedirectStandardOutput $out `
        -RedirectStandardError $err `
        -WindowStyle Hidden `
        -PassThru
    Wait-HttpOk -Url "http://127.0.0.1:$CouncilFrontendPort/"
    $State.councilFrontend = @{
        name = "LLM Council frontend"
        pid = $process.Id
        port = $CouncilFrontendPort
        url = "http://127.0.0.1:$CouncilFrontendPort"
    }
    return $State
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
$NotionAppMode = Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "appMode")) -Fallback "standard"
$NotionAutoLogin = [bool](Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "autoLogin")) -Fallback $true)
$NotionLoginTimeoutSeconds = [int](Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "loginTimeoutSeconds")) -Fallback 300)
$ProviderSupportsStreaming = [bool](Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "supportsStreaming")) -Fallback $true)
$ProviderApplyDefaultCouncil = [bool](Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "applyDefaultCouncil")) -Fallback $true)
$ConfiguredCouncilModels = ConvertTo-StringArray (Get-ConfigProperty $Config @("provider", "councilModels"))
$ConfiguredChairmanModel = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "chairmanModel")) -Fallback "custom:claude-opus4.7"
$ConfiguredCouncilMemberFilters = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "councilMemberFilters")) -Fallback @{
    "0" = "remote"
    "1" = "remote"
    "2" = "remote"
    "3" = "remote"
}
$ConfiguredChairmanFilter = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "chairmanFilter")) -Fallback "remote"
$ConfiguredSearchQueryFilter = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "searchQueryFilter")) -Fallback "remote"

if ($UseVendor) {
    $NotionRoot = Join-Path $VendorRoot "notion2api"
    $CouncilRoot = Join-Path $VendorRoot "llm-council-plus"
}

Ensure-Repo -Path $NotionRoot -Url $NotionRepoUrl -Branch $NotionBranch
Ensure-Repo -Path $CouncilRoot -Url $CouncilRepoUrl -Branch $CouncilBranch
$NotionRoot = (Resolve-Path $NotionRoot).Path
$CouncilRoot = (Resolve-Path $CouncilRoot).Path

if ($Stop) {
    Write-Step "Stopping launcher-managed services"
    Stop-ManagedServices
    exit 0
}

Write-Step "Preparing Notion2API + LLM Council"
Ensure-NotionMode
Ensure-NotionLogin
$notionApiKey = Ensure-NotionApiKey

if ($SetupOnly) {
    if (Test-HttpOk -Url "http://127.0.0.1:$NotionPort/health") {
        Set-Content -Path $RestartNotionFlag -Value "setup-refresh" -Encoding UTF8
    }
    Write-Host ""
    Write-Host "Setup complete:"
    Write-Host "  Notion2API root:   $NotionRoot"
    Write-Host "  LLM Council root:  $CouncilRoot"
    Write-Host "  API key:           configured in Notion2API .env"
    Write-Host "  Login:             valid"
    Write-Host ""
    Write-Host "Start later with:"
    Write-Host "  .\launch.bat"
    exit 0
}

$state = Get-State
$state = Start-NotionApi -State $state
$state = Start-CouncilBackend -State $state
Apply-CouncilProviderSettings -NotionApiKey $notionApiKey
Test-CouncilProviderConnection -NotionApiKey $notionApiKey
$state = Start-CouncilFrontend -State $state
Save-State -State $state

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
