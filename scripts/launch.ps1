param(
    [string]$ConfigPath = "",
    [string]$NotionRoot = "",
    [string]$CouncilRoot = "",
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

# Paths and State
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$LibDir = Join-Path $PSScriptRoot "lib"
$LogDir = if ($env:NOTION2COUNCIL_LOG_DIR) { $env:NOTION2COUNCIL_LOG_DIR } else { Join-Path $RepoRoot "logs" }
$VendorRoot = if ($env:NOTION2COUNCIL_RUNTIME_ROOT) { Join-Path $env:NOTION2COUNCIL_RUNTIME_ROOT "vendor" } else { Join-Path $RepoRoot "vendor" }
$StateFile = Join-Path $LogDir "launcher-state.json"
$RestartNotionFlag = Join-Path $LogDir "restart-notion.flag"

# Import Modules
Import-Module (Join-Path $LibDir "CommonUtils.psm1") -Force
Import-Module (Join-Path $LibDir "ConfigManager.psm1") -Force
Import-Module (Join-Path $LibDir "ProcessManager.psm1") -Force
Import-Module (Join-Path $LibDir "StateManager.psm1") -Force
Import-Module (Join-Path $LibDir "NetworkUtils.psm1") -Force
Import-Module (Join-Path $LibDir "RepoManager.psm1") -Force

# Initialization
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $VendorRoot | Out-Null
$BoundParameters = @($PSBoundParameters.Keys)
$NotionApiKeyChanged = $false

# Local Functions (Internal to launch.ps1 logic)
function Stop-ManagedServices {
    $state = Get-State -StateFile $StateFile
    foreach ($service in @($state.councilFrontend, $state.councilBackend, $state.notion)) {
        if ($service -and $service.pid) {
            Write-Step "Stopping $($service.name) (PID $($service.pid))"
            Stop-ProcessId -ProcessId ([int]$service.pid) -Tree
        }
    }
    Remove-Item $StateFile -ErrorAction SilentlyContinue
}

function Set-EnvLine {
    param([string]$Path, [string]$Name, [string]$Value)
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
    if (-not $updated) { $newLines += "$Name=$Value" }
    
    # Write UTF8 WITHOUT BOM for .env compatibility
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $newLines, $utf8NoBom)
}

function Get-EnvLineValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) { return "" }
    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("#") -or -not $trimmed.StartsWith("$Name=")) { continue }
        return $trimmed.Substring($Name.Length + 1).Trim('"').Trim("'")
    }
    return ""
}

function New-ApiKey {
    $bytes = [byte[]]::new(32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function Test-PythonModules {
    param([string]$Python, [string[]]$Modules)
    if (-not $Modules -or $Modules.Count -eq 0) { return $true }

    $missing = @()
    $checkCode = "import importlib.util, os, sys; module=os.environ.get('N2C_PY_MODULE', ''); sys.exit(0 if module and importlib.util.find_spec(module) else 1)"

    foreach ($module in $Modules) {
        $oldValue = $env:N2C_PY_MODULE
        $env:N2C_PY_MODULE = $module
        try {
            & $Python -c $checkCode *> $null
            if ($LASTEXITCODE -ne 0) {
                $missing += $module
            }
        } finally {
            if ($null -eq $oldValue) {
                Remove-Item Env:N2C_PY_MODULE -ErrorAction SilentlyContinue
            } else {
                $env:N2C_PY_MODULE = $oldValue
            }
        }
    }

    if ($missing.Count -eq 0) { return $true }
    Write-Step "Missing Python modules: $($missing -join ', ')"
    return $false
}

function Get-PyprojectDependencies {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return @() }

    $content = Get-Content -Raw -Path $Path
    $match = [regex]::Match($content, '(?ms)^dependencies\s*=\s*\[(?<deps>.*?)\]')
    if (-not $match.Success) { return @() }

    $deps = @()
    foreach ($line in ($match.Groups['deps'].Value -split "`r?`n")) {
        $clean = ($line -replace '#.*$', '').Trim().TrimEnd(',').Trim()
        if (-not $clean) { continue }
        $depMatch = [regex]::Match($clean, '^["''](?<dep>.*?)["'']$')
        if ($depMatch.Success) {
            $deps += $depMatch.Groups['dep'].Value
        }
    }

    return $deps
}

function Initialize-PythonRequirements {
    param(
        [string]$Root,
        [string]$Label,
        [string[]]$RequiredModules = @()
    )

    $requirementsPath = Join-Path $Root "requirements.txt"
    $pyprojectPath = Join-Path $Root "pyproject.toml"
    $hasRequirements = Test-Path $requirementsPath
    $hasPyproject = Test-Path $pyprojectPath

    if (-not $hasRequirements -and -not $hasPyproject) {
        Write-Step "$Label requirements.txt or pyproject.toml not found; skipping Python dependency install"
        return
    }

    $venvDir = Join-Path $Root ".venv"
    $venvPython = Join-Path $venvDir "Scripts\python.exe"
    if (-not (Test-Path $venvPython)) {
        Write-Step "Creating $Label Python virtual environment"
        & python -m venv $venvDir
        if ($LASTEXITCODE -ne 0) { throw "Failed to create Python virtual environment for $Label" }
    }

    $python = Get-Python -Root $Root
    if ($hasRequirements) {
        $dependencySource = $requirementsPath
        $installArgs = @("-m", "pip", "install", "--disable-pip-version-check", "-r", $requirementsPath)
        $installLabel = "$Label Python requirements"
    } else {
        $dependencySource = $pyprojectPath
        $pyprojectDependencies = @(Get-PyprojectDependencies -Path $pyprojectPath)
        if ($pyprojectDependencies.Count -eq 0) {
            throw "$Label pyproject.toml does not contain a parseable dependencies list"
        }
        $installArgs = @("-m", "pip", "install", "--disable-pip-version-check") + $pyprojectDependencies
        $installLabel = "$Label Python project dependencies"
    }

    $requirementsHash = (Get-FileHash -Path $dependencySource -Algorithm SHA256).Hash
    $markerPath = Join-Path $Root ".notion2council-requirements.sha256"
    $markerHash = if (Test-Path $markerPath) { (Get-Content -Path $markerPath -Raw).Trim() } else { "" }
    $modulesOk = Test-PythonModules -Python $python -Modules $RequiredModules

    if ($modulesOk -and $markerHash -eq $requirementsHash) {
        Write-Step "$installLabel are current"
        return
    }

    Write-Step "Installing $installLabel"
    & $python @installArgs
    if ($LASTEXITCODE -ne 0) { throw "Failed to install Python dependencies for $Label" }

    Set-Content -Path $markerPath -Value $requirementsHash -Encoding ASCII
    if (-not (Test-PythonModules -Python $python -Modules $RequiredModules)) {
        throw "$Label Python dependencies installed, but one or more required modules are still unavailable"
    }
}

function Initialize-NotionApiKey {
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
    Write-Step "Generated Notion2API API key"
    return $generated
}

function Initialize-NotionMode {
    Set-EnvLine -Path (Join-Path $NotionRoot ".env") -Name "APP_MODE" -Value $NotionAppMode
}

function Test-NotionLogin {
    $python = Get-Python -Root $NotionRoot
    Push-Location $NotionRoot
    try {
        & $python "login.py" "--check"
        return ($LASTEXITCODE -eq 0)
    } finally { Pop-Location }
}

function Initialize-NotionLogin {
    if (-not (Test-Path (Join-Path $NotionRoot "login.py"))) {
        throw "Notion2API checkout does not contain login.py"
    }
    if (-not $RefreshLogin -and (Test-NotionLogin)) {
        Write-Step "Notion token is valid"
        return
    }
    if (-not $NotionAutoLogin) {
        throw "Notion login is invalid and autoLogin is disabled"
    }
    Write-Step "Refreshing Notion login session"
    $python = Get-Python -Root $NotionRoot
    Push-Location $NotionRoot
    try {
        & $python "login.py" "--timeout" "$NotionLoginTimeoutSeconds"
        if ($LASTEXITCODE -ne 0) { throw "Notion login failed" }
    } finally { Pop-Location }
}

function Start-NotionApi {
    param($State)
    $healthUrl = "http://127.0.0.1:$NotionPort/health"
    $pidToStop = Get-ListeningProcessId -Port $NotionPort
    
    if ($pidToStop -and (Test-HttpOk -Url $healthUrl -ExpectedContent "ok")) {
        if (Test-Path $RestartNotionFlag) {
            Write-Step "Restarting Notion2API (forced by flag)"
            Stop-ProcessId -ProcessId $pidToStop -Tree
            Start-Sleep -Seconds 1
            Remove-Item $RestartNotionFlag -ErrorAction SilentlyContinue
        } else {
            Write-Step "Reusing Notion2API on http://127.0.0.1:$NotionPort"
            $State.notion = @{ name = "Notion2API"; pid = $pidToStop; port = $NotionPort; url = "http://127.0.0.1:$NotionPort" }
            return $State
        }
    }
    
    # Clean up flag if it somehow survived
    Remove-Item $RestartNotionFlag -ErrorAction SilentlyContinue

    if (Test-PortInUse -Port $NotionPort) { $script:NotionPort = Find-FreePort -PreferredPort $NotionPort }

    $python = Get-Python -Root $NotionRoot
    Write-Step "Starting Notion2API on http://127.0.0.1:$NotionPort"
    $process = Start-Process -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "app.server:app", "--host", "127.0.0.1", "--port", "$NotionPort") `
        -WorkingDirectory $NotionRoot -RedirectStandardOutput (Join-Path $LogDir "notion2api.out.log") -RedirectStandardError (Join-Path $LogDir "notion2api.err.log") `
        -WindowStyle Hidden -PassThru
    Wait-HttpOk -Url "http://127.0.0.1:$NotionPort/health" -ExpectedContent "ok"
    $State.notion = @{ name = "Notion2API"; pid = $process.Id; port = $NotionPort; url = "http://127.0.0.1:$NotionPort" }
    return $State
}

function Start-CouncilBackend {
    param($State)
    $settingsUrl = "http://127.0.0.1:$CouncilBackendPort/api/settings"
    $pidToStop = Get-ListeningProcessId -Port $CouncilBackendPort
    
    if ($pidToStop -and (Test-HttpOk -Url $settingsUrl -ExpectedContent "council_models")) {
        Write-Step "Reusing LLM Council backend on http://127.0.0.1:$CouncilBackendPort"
        $State.councilBackend = @{ name = "LLM Council backend"; pid = $pidToStop; port = $CouncilBackendPort; url = "http://127.0.0.1:$CouncilBackendPort" }
        return $State
    }

    if (Test-PortInUse -Port $CouncilBackendPort) { $script:CouncilBackendPort = Find-FreePort -PreferredPort $CouncilBackendPort }

    $python = Get-Python -Root $CouncilRoot
    Write-Step "Starting LLM Council backend on http://127.0.0.1:$CouncilBackendPort"
    $env:LLM_COUNCIL_ENABLE_SHUTDOWN = "1"
    $process = Start-Process -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "backend.main:app", "--host", "127.0.0.1", "--port", "$CouncilBackendPort") `
        -WorkingDirectory $CouncilRoot -RedirectStandardOutput (Join-Path $LogDir "council-backend.out.log") -RedirectStandardError (Join-Path $LogDir "council-backend.err.log") `
        -WindowStyle Hidden -PassThru
    # Clear env var leakage
    $env:LLM_COUNCIL_ENABLE_SHUTDOWN = $null
    Wait-HttpOk -Url $settingsUrl -ExpectedContent "council_models"
    $State.councilBackend = @{ name = "LLM Council backend"; pid = $process.Id; port = $CouncilBackendPort; url = "http://127.0.0.1:$CouncilBackendPort" }
    return $State
}

function Set-CouncilSettings {
    param([string]$NotionApiKey)
    $settingsUrl = "http://127.0.0.1:$CouncilBackendPort/api/settings"
    $current = Invoke-RestMethod -Method Get -Uri $settingsUrl -TimeoutSec 10
    
    $enabled = @{}
    if ($current.enabled_providers) { foreach ($property in $current.enabled_providers.PSObject.Properties) { $enabled[$property.Name] = [bool]$property.Value } }
    $enabled[$ProviderEnabledKey] = $true

    $body = [ordered]@{
        custom_endpoint_name    = $ProviderName
        custom_endpoint_url     = "http://127.0.0.1:$NotionPort$ProviderUrlPath"
        custom_endpoint_api_key = $NotionApiKey
        enabled_providers       = $enabled
        council_models          = if ($ProviderApplyDefaultCouncil) { $ConfiguredCouncilModels } else { $current.council_models }
        chairman_model          = if ($ProviderApplyDefaultCouncil) { $ConfiguredChairmanModel } else { $current.chairman_model }
    }
    if ($ProviderApplyDefaultCouncil) {
        if ($ConfiguredCouncilMemberFilters) { $body['council_member_filters'] = $ConfiguredCouncilMemberFilters }
        $body['chairman_filter']     = $ConfiguredChairmanFilter
        $body['search_query_filter'] = $ConfiguredSearchQueryFilter
    }
    $bodyJson = $body | ConvertTo-Json -Depth 20

    Write-Step "Configuring LLM Council custom provider"
    Invoke-RestMethod -Method Put -Uri $settingsUrl -ContentType "application/json" -Body $bodyJson -TimeoutSec 20 | Out-Null
}

function Start-CouncilFrontend {
    param($State)
    $allowedPorts = @($CouncilFrontendPort, 5173, 5174, 3000) | Select-Object -Unique
    foreach ($candidate in $allowedPorts) {
        if (Test-HttpOk -Url "http://127.0.0.1:$candidate/" -ExpectedTitle "LLM Council") {
            # Ensure both script-scoped and local variables reflect the chosen port
            $script:CouncilFrontendPort = $candidate
            $CouncilFrontendPort = $candidate
            Write-Step "Reusing LLM Council frontend on port $candidate"
            $listeningPid = Get-ListeningProcessId -Port $CouncilFrontendPort
            $State.councilFrontend = @{ name = "LLM Council frontend"; pid = $listeningPid; port = $CouncilFrontendPort; url = "http://127.0.0.1:$CouncilFrontendPort" }
            return $State
        }
    }

    $frontendRoot = Join-Path $CouncilRoot "frontend"

    # Run npm ci / install preflight if node_modules is missing
    $nodeModulesPath = Join-Path $frontendRoot "node_modules"
    if (-not (Test-Path $nodeModulesPath)) {
        Write-Step "LLM Council frontend node_modules is missing. Running npm preflight..."
        Push-Location $frontendRoot
        try {
            $installed = $false
            if (Test-Path (Join-Path $frontendRoot "package-lock.json")) {
                Write-Step "Running npm ci in $frontendRoot"
                & npm ci
                if ($LASTEXITCODE -eq 0) { $installed = $true }
            }
            if (-not $installed) {
                Write-Step "Running npm install in $frontendRoot"
                & npm install
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to install frontend dependencies in '$frontendRoot'."
                }
            }
        } finally {
            Pop-Location
        }
    }

    $envLocalPath = Join-Path $frontendRoot ".env.local"
    $envLocalLines = @(
        "VITE_API_URL=http://127.0.0.1:$CouncilBackendPort",
        "VITE_ENABLE_LOCAL_SHUTDOWN=true"
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($envLocalPath, $envLocalLines, $utf8NoBom)

    # If the preferred frontend port is occupied (but not serving LLM Council), pick a free port
    if (Test-PortInUse -Port $CouncilFrontendPort) { $script:CouncilFrontendPort = Find-FreePort -PreferredPort $CouncilFrontendPort; $CouncilFrontendPort = $script:CouncilFrontendPort }

    Write-Step "Starting LLM Council frontend on http://127.0.0.1:$CouncilFrontendPort"
    $process = Start-Process -FilePath "npm.cmd" -ArgumentList @("run", "dev", "--", "--host", "127.0.0.1", "--port", "$CouncilFrontendPort") `
        -WorkingDirectory $frontendRoot -RedirectStandardOutput (Join-Path $LogDir "council-frontend.out.log") -RedirectStandardError (Join-Path $LogDir "council-frontend.err.log") `
        -WindowStyle Hidden -PassThru
    Wait-HttpOk -Url "http://127.0.0.1:$CouncilFrontendPort/"
    $State.councilFrontend = @{ name = "LLM Council frontend"; pid = $process.Id; port = $CouncilFrontendPort; url = "http://127.0.0.1:$CouncilFrontendPort" }
    return $State
}

# Execution
$Config = Read-IntegrationConfig -RepoRoot $RepoRoot -ConfigPath $ConfigPath
if (-not ($BoundParameters -contains "NotionRoot")) { $NotionRoot = Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "localRoot")) -Fallback $NotionRoot }
if (-not ($BoundParameters -contains "CouncilRoot")) { $CouncilRoot = Use-ConfigValue -Value (Get-ConfigProperty $Config @("council", "localRoot")) -Fallback $CouncilRoot }
if (-not ($BoundParameters -contains "NotionPort")) { $NotionPort = [int](Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "port")) -Fallback $NotionPort) }
if (-not ($BoundParameters -contains "CouncilBackendPort")) { $CouncilBackendPort = [int](Use-ConfigValue -Value (Get-ConfigProperty $Config @("council", "backendPort")) -Fallback $CouncilBackendPort) }
if (-not ($BoundParameters -contains "CouncilFrontendPort")) { $CouncilFrontendPort = [int](Use-ConfigValue -Value (Get-ConfigProperty $Config @("council", "frontendPort")) -Fallback $CouncilFrontendPort) }

$ProviderName = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "name")) -Fallback "Notion2API"
$ProviderEnabledKey = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "enabledKey")) -Fallback "custom"
$ProviderUrlPath = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "urlPath")) -Fallback "/v1"
$NotionAppMode = Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "appMode")) -Fallback "standard"
$NotionAutoLogin = [bool](Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "autoLogin")) -Fallback $true)
$NotionLoginTimeoutSeconds = [int](Use-ConfigValue -Value (Get-ConfigProperty $Config @("notion", "loginTimeoutSeconds")) -Fallback 300)
$ProviderApplyDefaultCouncil = [bool](Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "applyDefaultCouncil")) -Fallback $true)
$ConfiguredCouncilModels = ConvertTo-StringArray (Get-ConfigProperty $Config @("provider", "councilModels"))
$ConfiguredChairmanModel = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "chairmanModel")) -Fallback "custom:claude-opus4.7"
$ConfiguredCouncilMemberFilters = Get-ConfigProperty $Config @("provider", "councilMemberFilters")
$ConfiguredChairmanFilter       = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "chairmanFilter"))       -Fallback "remote"
$ConfiguredSearchQueryFilter    = Use-ConfigValue -Value (Get-ConfigProperty $Config @("provider", "searchQueryFilter"))    -Fallback "remote"

if ($UseVendor) { $NotionRoot = Join-Path $VendorRoot "notion2api"; $CouncilRoot = Join-Path $VendorRoot "llm-council-plus" }
Initialize-Repo -Path $NotionRoot -Url $NotionRepoUrl -Branch $NotionBranch
Initialize-Repo -Path $CouncilRoot -Url $CouncilRepoUrl -Branch $CouncilBranch
$NotionRoot = (Resolve-Path $NotionRoot).Path
$CouncilRoot = (Resolve-Path $CouncilRoot).Path

if ($Stop) { Stop-ManagedServices; exit 0 }

Write-Step "Preparing Services"
Initialize-PythonRequirements -Root $NotionRoot -Label "Notion2API" -RequiredModules @("cloudscraper", "fastapi", "uvicorn", "dotenv", "slowapi", "websocket")
Initialize-PythonRequirements -Root $CouncilRoot -Label "LLM Council" -RequiredModules @("fastapi", "uvicorn", "dotenv", "httpx", "pydantic", "ddgs", "yake", "mcp")
Initialize-NotionMode
Initialize-NotionLogin
$notionApiKey = Initialize-NotionApiKey

if ($SetupOnly) { Write-Host "Setup complete"; exit 0 }

$state = Get-State -StateFile $StateFile
$state = Start-NotionApi -State $state
$state = Start-CouncilBackend -State $state
Set-CouncilSettings -NotionApiKey $notionApiKey
$state = Start-CouncilFrontend -State $state
Save-State -State $state -StateFile $StateFile

Write-Host "`nReady:"
Write-Host "  Notion2API:        http://127.0.0.1:$NotionPort"
Write-Host "  LLM Council API:   http://127.0.0.1:$CouncilBackendPort"
Write-Host "  LLM Council UI:    http://127.0.0.1:$CouncilFrontendPort"
Write-Host "  Logs:              $LogDir`n"

if (-not $NoBrowser) { Start-Process "http://127.0.0.1:$CouncilFrontendPort/" }

if (-not $env:GITHUB_ACTIONS) {
    Pause
}
