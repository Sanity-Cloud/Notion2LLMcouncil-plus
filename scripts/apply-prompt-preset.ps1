param(
    [string]$Preset = "",
    [string]$ConfigPath = "",
    [string]$CouncilRoot = "X:\Code\llm-council-plus",
    [int]$CouncilBackendPort = 8001,
    [switch]$List,
    [switch]$Show,
    [switch]$RestartBackend
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $RepoRoot "config\prompt-presets.json"
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Get-PresetNames {
    param($Config)
    return @($Config.presets.PSObject.Properties | ForEach-Object { $_.Name })
}

function Show-Presets {
    param($Config)
    Write-Host ""
    Write-Host "Available prompt presets:"
    foreach ($property in $Config.presets.PSObject.Properties) {
        $item = $property.Value
        Write-Host ("  {0,-24} {1}" -f $property.Name, $item.description)
    }
    Write-Host ""
}

function Get-SettingsPath {
    param([string]$Root)
    return Join-Path $Root "data\settings.json"
}

function Read-SettingsFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return [pscustomobject]@{}
    }
    try {
        return Get-Content -Path $Path -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Could not parse existing settings file. Starting with an empty settings object."
        return [pscustomobject]@{}
    }
}

function Add-OrSetProperty {
    param(
        [object]$Object,
        [string]$Name,
        $Value
    )
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Save-SettingsFile {
    param(
        [string]$Path,
        [object]$Settings
    )
    $dir = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $Settings | ConvertTo-Json -Depth 30 | Set-Content -Path $Path -Encoding UTF8
}

function Test-Backend {
    param([int]$Port)
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/api/settings" -TimeoutSec 3
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
    } catch {
        return $false
    }
}

function Apply-ViaBackend {
    param(
        [int]$Port,
        [hashtable]$Payload
    )
    $json = $Payload | ConvertTo-Json -Depth 30
    Invoke-RestMethod -Method Put -Uri "http://127.0.0.1:$Port/api/settings" -ContentType "application/json" -Body $json -TimeoutSec 20 | Out-Null
}

function Apply-ToFile {
    param(
        [string]$CouncilRoot,
        [hashtable]$Payload
    )
    $settingsPath = Get-SettingsPath -Root $CouncilRoot
    $settings = Read-SettingsFile -Path $settingsPath
    foreach ($key in $Payload.Keys) {
        Add-OrSetProperty -Object $settings -Name $key -Value $Payload[$key]
    }
    Save-SettingsFile -Path $settingsPath -Settings $settings
    Write-Host "Applied preset to settings file: $settingsPath"
}

function Restart-CouncilBackend {
    param([string]$CouncilRoot)
    $escaped = [regex]::Escape((Resolve-Path $CouncilRoot).Path)
    $targets = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and
        $_.CommandLine -match $escaped -and
        $_.CommandLine -match "backend\.main|uvicorn.*backend\.main"
    }
    foreach ($target in $targets) {
        Write-Host "Stopping backend PID $($target.ProcessId)"
        Stop-Process -Id $target.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

$config = Read-JsonFile -Path $ConfigPath

if ($List -or -not $Preset) {
    Show-Presets -Config $config
    if (-not $Preset) {
        $Preset = Read-Host "Preset to apply"
    }
}

$names = Get-PresetNames -Config $config
if ($names -notcontains $Preset) {
    throw "Unknown preset '$Preset'. Use -List to see available presets."
}

$selected = $config.presets.$Preset
$payload = @{}

if ($selected.prompts) {
    foreach ($property in $selected.prompts.PSObject.Properties) {
        $payload[$property.Name] = [string]$property.Value
    }
}

if ($selected.settings) {
    foreach ($property in $selected.settings.PSObject.Properties) {
        $payload[$property.Name] = $property.Value
    }
}

if ($Show) {
    Write-Host ""
    Write-Host "Preset: $Preset"
    Write-Host "Name:   $($selected.name)"
    Write-Host "Desc:   $($selected.description)"
    Write-Host ""
    $payload | ConvertTo-Json -Depth 30
    Write-Host ""
}

if (Test-Backend -Port $CouncilBackendPort) {
    Apply-ViaBackend -Port $CouncilBackendPort -Payload $payload
    Write-Host "Applied preset '$Preset' through LLM Council backend on port $CouncilBackendPort."
} else {
    Apply-ToFile -CouncilRoot $CouncilRoot -Payload $payload
    if ($RestartBackend) {
        Restart-CouncilBackend -CouncilRoot $CouncilRoot
    }
}

Write-Host ""
Write-Host "Active prompt preset: $Preset"
Write-Host "Restart or hard-refresh the LLM Council UI if it was already open."
Pause
