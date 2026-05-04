param(
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"

# Paths
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$LibDir = Join-Path $PSScriptRoot "lib"

# Import Modules
Import-Module (Join-Path $LibDir "CommonUtils.psm1") -Force
Import-Module (Join-Path $LibDir "ConfigManager.psm1") -Force

# Load Config
$Config = Read-IntegrationConfig -RepoRoot $RepoRoot -ConfigPath $ConfigPath
$SigMapScriptPath = Get-ConfigProperty $Config @("sigmap", "scriptPath") -Fallback ""

# Regenerate Context
if ($SigMapScriptPath -and (Test-Path $SigMapScriptPath)) {
    Write-Step "Regenerating SigMap context using script: $SigMapScriptPath"
    & node $SigMapScriptPath
} else {
    Write-Step "Regenerating SigMap context using CLI (npx sigmap)"
    & npx -y sigmap
}

Write-Host "`nContext regeneration complete."
