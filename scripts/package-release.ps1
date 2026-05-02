param(
    [string]$Version = "",
    [switch]$SkipNpmInstall,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

function Get-PackageVersion {
    $pkg = Get-Content -Path (Join-Path $RepoRoot "package.json") -Raw | ConvertFrom-Json
    return [string]$pkg.version
}

if (-not $Version) {
    $Version = Get-PackageVersion
}

$ReleaseRoot = Join-Path $RepoRoot "release"
$DistRoot = Join-Path $RepoRoot "dist-release"
$BundleRoot = Join-Path $DistRoot "Notion2Council-$Version"
$ZipPath = Join-Path $DistRoot "Notion2Council-$Version-source-bundle.zip"

Write-Host "==> Packaging Notion2Council $Version"
Write-Host "Repo: $RepoRoot"

if (-not $SkipNpmInstall) {
    Write-Host "==> Installing dependencies"
    npm install
}

$iconScript = Join-Path $RepoRoot "scripts\create-electron-icons.ps1"
if (Test-Path $iconScript) {
    Write-Host "==> Ensuring Electron icons"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $iconScript
}

if (-not $SkipBuild) {
    Write-Host "==> Building installer and portable ZIP through electron-builder"
    npm run electron:build
}

Write-Host "==> Creating source/runtime bundle"
Remove-Item $BundleRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $BundleRoot | Out-Null

$include = @(
    "config",
    "electron",
    "scripts",
    "launch.bat",
    "stop.bat",
    "setup.bat",
    "setup-desktop.bat",
    "package-release.bat",
    "package.json",
    "package-lock.json",
    "README.md"
)

foreach ($item in $include) {
    $src = Join-Path $RepoRoot $item
    if (Test-Path $src) {
        Copy-Item $src -Destination $BundleRoot -Recurse -Force
    }
}

New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null
Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $BundleRoot "*") -DestinationPath $ZipPath -Force

Write-Host ""
Write-Host "Release packaging complete."
Write-Host "Electron-builder output:"
Write-Host "  $ReleaseRoot"
Write-Host "Source/runtime bundle:"
Write-Host "  $ZipPath"
Write-Host ""
Write-Host "For a GitHub Release, upload the installer/zip from release\ and the source bundle from dist-release\."
Pause
