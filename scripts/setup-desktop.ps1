param(
    [switch]$SkipIntegrationSetup,
    [switch]$SkipNpmInstall,
    [switch]$Build,
    [switch]$Package
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

function Require-Command {
    param([string]$Name, [string]$InstallHint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found. $InstallHint"
    }
}

Write-Host "==> Notion2Council Desktop setup"
Write-Host "Repo: $RepoRoot"

Require-Command -Name "node" -InstallHint "Install Node.js 18+ from https://nodejs.org/"
Require-Command -Name "npm" -InstallHint "Install npm with Node.js."
Require-Command -Name "git" -InstallHint "Install Git for Windows."
Require-Command -Name "powershell" -InstallHint "Use Windows PowerShell."

$nodeVersion = (& node --version)
$npmVersion = (& npm --version)
Write-Host "Node: $nodeVersion"
Write-Host "npm:  $npmVersion"

if (-not $SkipNpmInstall) {
    Write-Host "==> Installing Electron dependencies"
    npm install
}

$iconScript = Join-Path $RepoRoot "scripts\create-electron-icons.ps1"
if (Test-Path $iconScript) {
    Write-Host "==> Ensuring Electron icons"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $iconScript
}

if (-not $SkipIntegrationSetup) {
    Write-Host "==> Running integration setup"
    & (Join-Path $RepoRoot "setup.bat")
}

if ($Build -or $Package) {
    Write-Host "==> Building Electron installer and ZIP"
    npm run electron:build
}

Write-Host "==> Creating Start Menu shortcut"
$RepoRootStr = $RepoRoot.ProviderPath
$ShortcutPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Notion2Council.lnk"
$TargetPath = Join-Path $RepoRootStr "release\win-unpacked\Notion2Council.exe"

if (-not (Test-Path $TargetPath)) {
    Write-Host "Unpacked executable not found. Running electron:pack to generate it..."
    npm run electron:pack
}

try {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $TargetPath
    $Shortcut.WorkingDirectory = $RepoRootStr
    $Shortcut.Description = "Notion2Council Desktop App"
    $Shortcut.IconLocation = "$TargetPath,0"
    $Shortcut.Save()
    Write-Host "Shortcut successfully created at: $ShortcutPath"
} catch {
    Write-Warning "Could not create Start Menu shortcut: $_"
}

Write-Host ""
Write-Host "Setup complete."
Write-Host "Run desktop app:"
Write-Host "  npm run start"
Write-Host ""
Write-Host "Package release locally:"
Write-Host "  .\package-release.bat"
Write-Host ""
Write-Host "Installer output:"
Write-Host "  $RepoRoot\release"
Pause

