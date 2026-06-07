param(
    [string]$ConfigPath = "",
    [switch]$NoBrowser = $true
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$VendorRoot = Join-Path $RepoRoot "vendor"

Write-Host "Starting End-to-End Smoke Test..."

# 1. Clean vendor reset (for tests, we just assume clean state or prompt for it)
Write-Host "1. Validating Vendor State..."
$CouncilRoot = Join-Path $VendorRoot "the-ai-counsel"
if (-not (Test-Path $CouncilRoot)) {
    Write-Warning "Vendor not found, launching will bootstrap it."
}

# 2. Launch Services in Setup/Background Mode
Write-Host "2. Starting Services..."
$launchArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "launch.ps1"), "-NoBrowser")
if ($ConfigPath) { $launchArgs += "-ConfigPath"; $launchArgs += $ConfigPath }

# Note: In a real test runner we would Start-Process and capture output, but for a simple script:
$process = Start-Process -FilePath "pwsh" -ArgumentList $launchArgs -PassThru -WindowStyle Hidden
Write-Host "Launcher started with PID $($process.Id). Waiting for initialization..."

Start-Sleep -Seconds 15

# 3. Verify Health Endpoints
Write-Host "3. Verifying Health Endpoints..."
$backendHealthy = $false
try {
    $res = Invoke-RestMethod -Uri "http://127.0.0.1:8121/health" -Method Get -TimeoutSec 5
    if ($res.status -eq "ok") { $backendHealthy = $true }
} catch {}

if (-not $backendHealthy) {
    Write-Warning "Backend health check failed."
} else {
    Write-Host "Backend health: OK"
}

# 4. Smoke Test Prompt
Write-Host "4. Sending Smoke Test Prompt..."
if ($backendHealthy) {
    try {
        $body = @{
            model = "custom:claude-opus4.7"
            messages = @(
                @{ role = "user"; content = "Smoke test: respond with OK" }
            )
        } | ConvertTo-Json
        $res = Invoke-RestMethod -Uri "http://127.0.0.1:8121/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10
        Write-Host "Received response from model."
    } catch {
        Write-Warning "Smoke test prompt failed: $($_.Exception.Message)"
    }
}

# 5. Shut Down Services
Write-Host "5. Shutting Down Services..."
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "launch.ps1") -Stop

Write-Host "End-to-End Smoke Test Completed."
