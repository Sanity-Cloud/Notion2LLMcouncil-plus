param(
    [switch]$SkipPackageLock
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

function Write-Check {
    param([string]$Message)
    Write-Host "[check] $Message"
}

function Assert-FileExists {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Required file missing: $Path"
    }
}

function Read-JsonChecked {
    param([string]$Path)
    Assert-FileExists -Path $Path
    try {
        return Get-Content -Raw -Path $Path | ConvertFrom-Json
    } catch {
        throw "Invalid JSON in $Path`: $($_.Exception.Message)"
    }
}

Write-Check "Required files exist"
$requiredFiles = @(
    "package.json",
    "config/default.json",
    "electron/main.js",
    "electron-builder.portable.json",
    ".github/workflows/release.yml",
    "scripts/launch.ps1",
    "scripts/package-release.ps1",
    "scripts/setup-desktop.ps1"
)
foreach ($file in $requiredFiles) {
    Assert-FileExists -Path (Join-Path $RepoRoot $file)
}

Write-Check "JSON files parse"
$package = Read-JsonChecked -Path (Join-Path $RepoRoot "package.json")
$config = Read-JsonChecked -Path (Join-Path $RepoRoot "config/default.json")
$builder = Read-JsonChecked -Path (Join-Path $RepoRoot "electron-builder.portable.json")

Write-Check "Package version is present"
if (-not $package.version) {
    throw "package.json version is missing."
}

if (-not $SkipPackageLock -and (Test-Path (Join-Path $RepoRoot "package-lock.json"))) {
    Write-Check "package-lock version matches package.json"
    $lock = Read-JsonChecked -Path (Join-Path $RepoRoot "package-lock.json")
    if ($lock.version -ne $package.version) {
        throw "package-lock.json root version '$($lock.version)' does not match package.json '$($package.version)'. Run npm install/package-lock update."
    }
    if ($lock.packages."".version -ne $package.version) {
        throw "package-lock.json packages[''].version '$($lock.packages."".version)' does not match package.json '$($package.version)'."
    }
}

Write-Check "Default config uses portable vendor paths"
if ([string]$config.notion.localRoot -match "^[A-Za-z]:\\") {
    throw "config/default.json notion.localRoot must not be machine-specific: $($config.notion.localRoot)"
}
if ([string]$config.council.localRoot -match "^[A-Za-z]:\\") {
    throw "config/default.json council.localRoot must not be machine-specific: $($config.council.localRoot)"
}

Write-Check "PowerShell scripts parse"
$psScripts = @(
    "scripts/launch.ps1",
    "scripts/package-release.ps1",
    "scripts/setup-desktop.ps1",
    "scripts/create-electron-icons.ps1"
)
foreach ($script in $psScripts) {
    $fullPath = Join-Path $RepoRoot $script
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $joined = ($errors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) -join "; "
        throw "PowerShell parse errors in $script`: $joined"
    }
}

Write-Check "Electron entrypoint parses"
node --check (Join-Path $RepoRoot "electron/main.js")

Write-Check "Release workflow does not publish broad runtime globs"
$workflow = Get-Content -Raw -Path (Join-Path $RepoRoot ".github/workflows/release.yml")
if ($workflow -match "(?m)^\s*files:\s*\r?\n\s*release/\*\*") {
    throw "Release workflow still publishes release/** directly. Stage a single package instead."
}
if ($workflow -match "(?m)^\s*path:\s*\r?\n\s*release/\*\*") {
    throw "Release workflow still uploads release/** directly. Stage a single package instead."
}
if ($workflow -notmatch "github-release/\*\.zip") {
    throw "Release workflow should publish github-release/*.zip."
}

Write-Check "Release artifact names include package version"
$version = [regex]::Escape([string]$package.version)
$packageJson = Get-Content -Raw -Path (Join-Path $RepoRoot "package.json")
if ($packageJson -notmatch $version) {
    throw "package.json does not contain its declared version string in artifact metadata."
}

Write-Host "All validation checks passed."
