param(
    [string]$CouncilRoot = "",
    [string]$BackupRoot = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not $CouncilRoot) {
    $CouncilRoot = Join-Path $RepoRoot "vendor\the-ai-counsel"
}
if (-not $BackupRoot) {
    $BackupRoot = Join-Path $env:APPDATA "notion2council-desktop\backups"
}

$Data = Join-Path $CouncilRoot "data"
if (-not (Test-Path $Data)) {
    throw "Council runtime data directory not found: $Data"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Backup = Join-Path $BackupRoot "data-$timestamp"
New-Item -ItemType Directory -Force -Path $Backup | Out-Null
Copy-Item (Join-Path $Data "*") $Backup -Recurse -Force

$readme = @(
    "Notion2Council runtime data backup",
    "",
    "Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')",
    "Source: $Data",
    "Purpose: preserve Council settings and conversation history before cleaning, replacing, or repairing vendor runtime data.",
    "",
    "Contents may include private conversation history and API keys. Do not commit this folder.",
    "",
    "Restore procedure:",
    "1. Stop the stack: powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch.ps1 -Stop",
    "2. Copy this folder's contents back to the active Council data directory.",
    "3. Relaunch the stack so the launcher can sync settings.custom_endpoint_api_key to the active Notion2API API_KEY.",
    "4. Verify /api/settings and /api/conversations before deleting this backup.",
    "",
    "Safe to delete: only after a newer verified backup exists and conversations/settings have been confirmed restored."
) -join [Environment]::NewLine

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $Backup "README.txt"), $readme + [Environment]::NewLine, $utf8NoBom)

Write-Host "Backed up active data to: $Backup"
