#requires -Version 5.1
<#
.SYNOPSIS
  Recommended Notion2Council entry point: vendor submodules, patches, then Electron UI.

.DESCRIPTION
  1. Runs launch.ps1 -UseVendor -SetupOnly (submodule init + patch apply + deps check)
  2. Starts the Electron desktop shell (npm run start)

  Use this script or the Start Menu shortcut "Notion2Council" instead of launch-ui.bat
  when you want patches reliably applied before the stack starts.
#>
param(
    [switch]$SetupOnly,
    [switch]$SkipPatchSetup
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

$LaunchScript = Join-Path $RepoRoot "scripts\launch.ps1"
$LocalConfigPath = if ($env:NOTION2COUNCIL_CONFIG) { $env:NOTION2COUNCIL_CONFIG } else { Join-Path $RepoRoot "config\local.json" }
if (-not (Test-Path $LaunchScript)) {
    throw "Could not find $LaunchScript"
}

if (-not $SkipPatchSetup) {
    Write-Host "==> Notion2Council: syncing vendor submodules and applying council patches"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LaunchScript -UseVendor -SetupOnly -ConfigPath $LocalConfigPath
    if ($LASTEXITCODE -ne 0) {
        throw "Patch/setup step failed with exit code $LASTEXITCODE"
    }

    $verifyScript = Join-Path $RepoRoot "scripts\verify-council-patches.ps1"
    if (Test-Path $verifyScript) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyScript -RequireApplied
        if ($LASTEXITCODE -ne 0) {
            throw "Council patch verification failed after setup"
        }
    }
}

if ($SetupOnly) {
    Write-Host "Setup complete (patches applied). Start the UI with: npm run start"
    exit 0
}

if (-not (Test-Path (Join-Path $RepoRoot "node_modules\electron"))) {
    Write-Host "==> Installing Electron dependencies (first run)"
    & npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install failed with exit code $LASTEXITCODE" }
}

$iconPng = Join-Path $RepoRoot "electron\tray.png"
$iconScript = Join-Path $RepoRoot "scripts\create-electron-icons.ps1"
if (-not (Test-Path $iconPng) -and (Test-Path $iconScript)) {
    Write-Host "==> Generating tray icon (electron/tray.png missing)"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $iconScript
}

Write-Host "==> Starting Notion2Council desktop shell"
& npm run start
exit $LASTEXITCODE
