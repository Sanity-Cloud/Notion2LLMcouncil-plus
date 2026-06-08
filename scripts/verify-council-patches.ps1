#requires -Version 5.1
<#
.SYNOPSIS
  Verifies council patch wiring targets vendor/the-ai-counsel (not legacy llm-council-plus).

.PARAMETER RequireApplied
  When set, also requires guard symbols in the checked-out council tree.
#>
param(
    [switch]$RequireApplied
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$CouncilRoot = Join-Path $RepoRoot "vendor\the-ai-counsel"
$LegacyRoot = Join-Path $RepoRoot "vendor\llm-council-plus"
$GuardsPatch = Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion-attachment-endpoint-guards.patch"
$RepoManager = Join-Path $RepoRoot "scripts\lib\RepoManager.psm1"
$CustomOpenAi = Join-Path $CouncilRoot "backend\providers\custom_openai.py"

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

Write-Host "[verify] Council vendor path: vendor/the-ai-counsel"

if (-not (Test-Path (Join-Path $CouncilRoot ".git"))) {
    Fail "Active council submodule missing at vendor/the-ai-counsel. Run: git submodule update --init vendor/the-ai-counsel"
}

if (Test-Path $LegacyRoot) {
    $legacyEntries = @(Get-ChildItem -Path $LegacyRoot -Force -ErrorAction SilentlyContinue)
    if ($legacyEntries.Count -gt 0) {
        Write-Warning "Legacy vendor/llm-council-plus still exists and is not the active submodule. Ignore it for patch checks."
    } else {
        Write-Host "[verify] Legacy vendor/llm-council-plus is empty (safe to remove)"
    }
}

if (-not (Test-Path $GuardsPatch)) {
    Fail "Missing patch file: scripts/patches/the-ai-counsel-notion-attachment-endpoint-guards.patch"
}

$repoManagerText = Get-Content -Raw -Path $RepoManager
if ($repoManagerText -notmatch 'the-ai-counsel-notion-attachment-endpoint-guards\.patch') {
    Fail "RepoManager.psm1 does not register the-ai-counsel-notion-attachment-endpoint-guards.patch"
}

if ($repoManagerText -match 'llm-council-plus-notion2api-upload-rate-limit\.patch') {
    Fail "RepoManager.psm1 still references legacy llm-council-plus patch names"
}

Write-Host "[verify] Patch file and RepoManager wiring: OK"

$guardsApplied = $false
Push-Location $CouncilRoot
try {
    git apply --reverse --check --ignore-whitespace $GuardsPatch 2>$null
    if ($LASTEXITCODE -eq 0) {
        $guardsApplied = $true
        Write-Host "[verify] Guards patch applied in vendor/the-ai-counsel: OK"
    } else {
        git apply --check --ignore-whitespace $GuardsPatch 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[verify] Guards patch not yet applied (run launch -UseVendor -SetupOnly)"
        } else {
            Write-Warning "Guards patch state is inconsistent with submodule HEAD"
        }
    }
} finally {
    Pop-Location
}

if ($RequireApplied) {
    if (-not (Test-Path $CustomOpenAi)) {
        Fail "custom_openai.py not found under vendor/the-ai-counsel"
    }

    $providerText = Get-Content -Raw -Path $CustomOpenAi
    $required = @(
        "def _is_notion_attachment_endpoint",
        "payload_attachments",
        "notion_upload",
        "use_notion_attachment_retry",
        "_ATTACHMENT_UPLOAD_SEMAPHORE"
    )
    $missing = @($required | Where-Object { $providerText -notmatch [regex]::Escape($_) })
    if ($missing.Count -gt 0 -and -not $guardsApplied) {
        Fail ("vendor/the-ai-counsel missing guard symbols: {0}. Run: scripts\launch.ps1 -UseVendor -SetupOnly" -f ($missing -join ", "))
    }

    if ($missing.Count -gt 0 -and $guardsApplied) {
        Fail "Guards patch reports applied but symbols are missing from custom_openai.py"
    }

    Write-Host "[verify] Notion attachment guard symbols in vendor/the-ai-counsel: OK"
}

Write-Host "[verify] Council patch verification passed."
