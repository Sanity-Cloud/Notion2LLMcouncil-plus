#requires -Version 5.1
<#
.SYNOPSIS
  Creates or updates the Notion2Council shortcut in the Windows Start Menu.

.DESCRIPTION
  Points at scripts/Start-Notion2Council.ps1 (vendor sync, patch apply, Electron UI).
  Does not use the legacy vendor/llm-council-plus path or the unpacked release EXE.
#>
param(
    [string]$ShortcutName = "Notion2Council"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$StartScript = Join-Path $RepoRoot "scripts\Start-Notion2Council.ps1"
$ProgramsDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$ShortcutPath = Join-Path $ProgramsDir "$ShortcutName.lnk"

if (-not (Test-Path $StartScript)) {
    throw "Missing launcher script: $StartScript"
}

$iconScript = Join-Path $RepoRoot "scripts\create-electron-icons.ps1"
if ((Test-Path $iconScript) -and -not (Test-Path (Join-Path $RepoRoot "electron\icon.ico"))) {
    Write-Host "==> Generating desktop icons for shortcut"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $iconScript
}

$iconCandidates = @(
    (Join-Path $RepoRoot "electron\icon.ico"),
    (Join-Path $RepoRoot "release\win-unpacked\Notion2Council.exe"),
    (Join-Path $RepoRoot "build\icon.ico"),
    (Join-Path $RepoRoot "node_modules\electron\dist\electron.exe")
)

$iconPath = $null
foreach ($candidate in $iconCandidates) {
    if (Test-Path $candidate) {
        $iconPath = $candidate
        break
    }
}

$windir = $env:SystemRoot
if (-not $windir) { $windir = "C:\Windows" }
$powerShellPath = Join-Path $windir "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path $powerShellPath)) {
    $powerShellPath = "powershell.exe"
}

$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$StartScript`""

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $powerShellPath
$Shortcut.Arguments = $arguments
$Shortcut.WorkingDirectory = $RepoRoot
$Shortcut.Description = "Notion2Council (vendor/the-ai-counsel + patches, then Electron)"
if ($iconPath) {
    $Shortcut.IconLocation = "$iconPath,0"
}
$Shortcut.Save()

Write-Host "Start Menu shortcut created:"
Write-Host "  $ShortcutPath"
Write-Host ""
Write-Host "Target:"
Write-Host "  $powerShellPath $arguments"
Write-Host "Working directory:"
Write-Host "  $RepoRoot"
