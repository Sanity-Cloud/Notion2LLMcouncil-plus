$commonUtilsPath = Join-Path $PSScriptRoot "CommonUtils.psm1"
if (Test-Path $commonUtilsPath) {
    Import-Module $commonUtilsPath
}

function Initialize-Repo {
    param(
        [string]$Path,
        [string]$Url,
        [string]$Branch = ""
    )

    if (Test-Path $Path) {
        if (Test-Path (Join-Path $Path ".git")) {
            if ($Branch) {
                Write-Step "Refreshing $Path from origin/$Branch"
                git -C $Path fetch --quiet origin $Branch
                if ($LASTEXITCODE -ne 0) {
                    Write-Step "Could not fetch origin/$Branch for $Path; using existing checkout"
                    return
                }

                $currentBranch = git -C $Path rev-parse --abbrev-ref HEAD
                if ($currentBranch -ne $Branch) {
                    Write-Step "Updating $Path to branch $Branch"
                    git -C $Path checkout -f $Branch
                    if ($LASTEXITCODE -ne 0) { throw "Failed to checkout branch $Branch in $Path" }
                }

                git -C $Path pull --quiet --ff-only origin $Branch
                if ($LASTEXITCODE -ne 0) {
                    Write-Step "Could not fast-forward $Path from origin/$Branch; using existing checkout"
                }
            }
        }
        return
    }

    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    
    Write-Step "Cloning $Url to $Path"
    if ($Branch) {
        git clone --quiet --branch $Branch $Url $Path
    } else {
        git clone --quiet $Url $Path
    }
}

function Get-Python {
    param([string]$Root)
    $venvPython = Join-Path $Root ".venv\Scripts\python.exe"
    if (Test-Path $venvPython) {
        return $venvPython
    }
    return "python"
}

function Get-PatchTargetPaths {
    param([string]$PatchPath)

    if (-not (Test-Path $PatchPath)) { return @() }

    $targets = @()
    foreach ($line in Get-Content -Path $PatchPath) {
        if ($line -match '^\+\+\+ b/(.+)$') {
            $target = $Matches[1]
            if ($target -and $target -ne "/dev/null") { $targets += $target }
        }
    }

    return @($targets | Select-Object -Unique)
}

function Reset-PatchTargetPaths {
    param(
        [string[]]$Targets,
        [string]$Name
    )

    foreach ($target in $Targets) {
        if (-not $target) { continue }
        Write-Step "Resetting patch target for $($Name): $target"
        cmd.exe /c "git checkout -- `"$target`" 2>nul"
        if ($LASTEXITCODE -ne 0) {
            if (Test-Path $target) {
                Remove-Item -Path $target -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
    }
}


function Test-PatchEquivalentPresent {
    param(
        [string]$Root,
        [string]$PatchPath
    )

    if (-not $PatchPath) { return $false }

    $leaf = Split-Path $PatchPath -Leaf

    if ($leaf -eq "notion2api-search-metadata-web-only.patch") {
        $chatPath = Join-Path $Root "app\api\chat.py"
        if (-not (Test-Path $chatPath)) { return $false }
        $chatContent = Get-Content -Raw -Path $chatPath
        $required = @(
            "def _emit_search_metadata_for_client",
            "def _probe_match_candidates",
            "last_user_content = _last_user_message_content"
        )
        foreach ($symbol in $required) {
            if ($chatContent -notmatch [regex]::Escape($symbol)) { return $false }
        }
        return $true
    }

    if ($leaf -eq "notion2api-drop-current-user-request-label.patch") {
        $conversationPath = Join-Path $Root "app\conversation.py"
        if (-not (Test-Path $conversationPath)) { return $false }
        $conversationContent = Get-Content -Raw -Path $conversationPath
        return $conversationContent -notmatch '\[Current user request\]'
    }

    $customOpenAiPath = Join-Path $Root "backend\providers\custom_openai.py"
    if (-not (Test-Path $customOpenAiPath)) { return $false }

    $content = Get-Content -Raw -Path $customOpenAiPath

    if ($leaf -eq "the-ai-counsel-custom-openai-runtime-retry.patch") {
        $required = @(
            "def _is_rate_limited",
            "def _rate_limit_retry_config",
            "debug_timeline",
            "rate_limited",
            "total_elapsed_seconds"
        )
        foreach ($symbol in $required) {
            if ($content -notmatch [regex]::Escape($symbol)) { return $false }
        }
        return $true
    }

    if ($leaf -eq "the-ai-counsel-notion-attachment-endpoint-guards.patch") {
        $required = @(
            "def _is_notion_attachment_endpoint",
            "payload_attachments",
            "notion_upload",
            "use_notion_attachment_retry"
        )
        foreach ($symbol in $required) {
            if ($content -notmatch [regex]::Escape($symbol)) { return $false }
        }
        return $true
    }

    if ($leaf -eq "the-ai-counsel-stage1-attachments-wireup.patch") {
        $councilPath = Join-Path $Root "backend\council.py"
        if (-not (Test-Path $councilPath)) { return $false }
        $councilContent = Get-Content -Raw -Path $councilPath
        $required = @(
            "attachments: List[Dict[str, Any]] | None = None",
            "attachments=attachments"
        )
        foreach ($symbol in $required) {
            if ($councilContent -notmatch [regex]::Escape($symbol)) { return $false }
        }
        return $true
    }

    if ($leaf -eq "the-ai-counsel-notion2api-stage1-stagger.patch") {
        $councilPath = Join-Path $Root "backend\council.py"
        if (-not (Test-Path $councilPath)) { return $false }
        $councilContent = Get-Content -Raw -Path $councilPath
        return $councilContent -match "_NOTION_STAGGER_SECONDS" -and $councilContent -match "_vary_notion_thread_title"
    }

    if ($leaf -eq "the-ai-counsel-notion2api-preflight-skip.patch") {
        $preflightPath = Join-Path $Root "backend\model_preflight.py"
        if (-not (Test-Path $preflightPath)) { return $false }
        $preflightContent = Get-Content -Raw -Path $preflightPath
        return $preflightContent -match "def _skip_notion2api_preflight"
    }

    if ($leaf -eq "the-ai-counsel-notion2api-upload-rate-limit.patch") {
        $required = @(
            "_ATTACHMENT_UPLOAD_SEMAPHORE",
            "def _attachment_retry_config",
            "def _rate_limit_retry_config",
            "debug_timeline",
            "rate_limited",
            "total_elapsed_seconds"
        )
        foreach ($symbol in $required) {
            if ($content -notmatch [regex]::Escape($symbol)) { return $false }
        }
        $councilPath = Join-Path $Root "backend\council.py"
        if (-not (Test-Path $councilPath)) { return $false }
        $councilContent = Get-Content -Raw -Path $councilPath
        if ($councilContent -notmatch 'attachments:\s*"List\[Dict\[str,\s*Any\]\]\s*\|\s*None"\s*=\s*None') {
            return $false
        }
        return $true
    }

    return $false
}

function Invoke-RepoPatchPostHooks {
    param(
        [string]$Root,
        [string]$PatchPath,
        [string]$Name
    )

    $patchDir = Split-Path $PatchPath -Parent
    $leaf = Split-Path $PatchPath -Leaf

    if ($leaf -eq "the-ai-counsel-new-chat-stream-race.patch") {
        $uploadPatch = Join-Path $patchDir "the-ai-counsel-notion2api-file-uploads.patch"
        if (Test-Path $uploadPatch) {
            Update-RepoPatch `
                -Root $Root `
                -PatchPath $uploadPatch `
                -Name "LLM Council Notion2API file uploads"
        }
    }

    if ($leaf -eq "the-ai-counsel-notion2api-file-uploads.patch") {
        $rateLimitPatch = Join-Path $patchDir "the-ai-counsel-notion2api-upload-rate-limit.patch"
        if (Test-Path $rateLimitPatch) {
            Update-RepoPatch `
                -Root $Root `
                -PatchPath $rateLimitPatch `
                -Name "LLM Council Notion2API upload rate-limit guard"
        }
    }

    if ($leaf -eq "the-ai-counsel-notion2api-upload-rate-limit.patch") {
        $saveExportPatch = Join-Path $patchDir "the-ai-counsel-notion2api-save-export.patch"
        if (Test-Path $saveExportPatch) {
            Update-RepoPatch `
                -Root $Root `
                -PatchPath $saveExportPatch `
                -Name "LLM Council Notion2API save and export layer"
        }
    }
}

function Update-RepoPatch {
    param(
        [string]$Root,
        [string]$PatchPath,
        [string]$Name,
        [switch]$Optional
    )

    if (-not (Test-Path $PatchPath)) { return }

    if (Test-PatchEquivalentPresent -Root $Root -PatchPath $PatchPath) {
        Write-Step "Skipping patch already integrated upstream: $Name"
        return
    }

    Push-Location $Root
    try {
        try {
            cmd.exe /c "git apply --check --ignore-whitespace `"$PatchPath`" 2>nul"
            if ($LASTEXITCODE -eq 0) {
                Write-Step "Applying patch: $Name"
                cmd.exe /c "git apply --ignore-whitespace `"$PatchPath`""
                if ($LASTEXITCODE -ne 0) { throw "Failed to apply patch: $Name" }
                return
            }

            cmd.exe /c "git apply --reverse --check --ignore-whitespace `"$PatchPath`" 2>nul"
            if ($LASTEXITCODE -eq 0) {
                Write-Step "Patch already applied: $Name"
                return
            }

            $targets = @(Get-PatchTargetPaths -PatchPath $PatchPath)
            if ($targets.Count -gt 0) {
                Write-Step "Patch state drift detected for $Name; resetting managed target file(s) and retrying"
                Reset-PatchTargetPaths -Targets $targets -Name $Name

                cmd.exe /c "git apply --check --ignore-whitespace `"$PatchPath`" 2>nul"
                if ($LASTEXITCODE -eq 0) {
                    Write-Step "Applying patch after reset: $Name"
                    cmd.exe /c "git apply --ignore-whitespace `"$PatchPath`""
                    if ($LASTEXITCODE -ne 0) { throw "Failed to apply patch after reset: $Name" }
                    return
                }
            }

            throw "Patch cannot be applied cleanly: $Name"
        } catch {
            if ($Optional) {
                Write-Warning "Optional patch '$Name' failed: $($_.Exception.Message)"
            } else {
                throw
            }
        }
    } finally {
        Pop-Location
    }
}

function Test-CouncilPatchesPresent {
    param(
        [string]$CouncilRoot,
        [string]$RepoRoot
    )

    # Probe the tail of the patch stack. Older probes (e.g. configurable-model-timeout
    # on council.py) fail reverse-check once later patches touch the same file.
    $probePatches = @(
        "the-ai-counsel-notion-attachment-endpoint-guards.patch",
        "the-ai-counsel-chat-input-layout.patch"
    )

    Push-Location $CouncilRoot
    try {
        foreach ($leaf in $probePatches) {
            $probePatch = Join-Path $RepoRoot "scripts\patches\$leaf"
            if (-not (Test-Path $probePatch)) { return $false }
            cmd.exe /c "git apply --reverse --check --ignore-whitespace `"$probePatch`" 2>nul"
            if ($LASTEXITCODE -ne 0) { return $false }
        }
        return $true
    } finally {
        Pop-Location
    }
}

function Apply-Notion2ApiPatches {
    param(
        [string]$NotionRoot,
        [string]$RepoRoot
    )

    $patchFiles = @(
        (Join-Path $RepoRoot "scripts\patches\notion2api-search-metadata-web-only.patch"),
        (Join-Path $RepoRoot "scripts\patches\notion2api-openai-compat-shim.patch"),
        (Join-Path $RepoRoot "scripts\patches\notion2api-drop-current-user-request-label.patch")
    )

    foreach ($patchPath in $patchFiles) {
        if (-not (Test-Path $patchPath)) { continue }
        $leaf = Split-Path $patchPath -Leaf
        $name = switch ($leaf) {
            "notion2api-search-metadata-web-only.patch" { "Notion2API search_metadata web client only" }
            "notion2api-openai-compat-shim.patch" { "Notion2API OpenAI-compat persona shim" }
            "notion2api-drop-current-user-request-label.patch" { "Notion2API drop Current user request label" }
            default { $leaf }
        }
        Update-RepoPatch `
            -Root $NotionRoot `
            -PatchPath $patchPath `
            -Name $name
    }
}

function Apply-SubmodulePatches {
    param(
        [string]$CouncilRoot,
        [string]$RepoRoot
    )

    $RemoteUrl = ""
    try {
        $RemoteUrl = (git -C $CouncilRoot remote get-url origin 2>$null).Trim()
    } catch {}



    $PatchFiles = @(
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-custom-model-icons.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-custom-provider-initial-setup.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-first-message-title.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-new-chat-stream-race.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion2api-file-uploads.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion2api-upload-rate-limit.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-preflight-rate-limit.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion2api-preflight-skip.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-configurable-model-timeout.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-stage1-attachments-wireup.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion2api-stage1-stagger.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-custom-openai-runtime-retry.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-strip-reasoning-preamble.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-model-timeout-query-default.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-chairman-extended-timeout.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion-attachment-endpoint-guards.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-debate-claim-extraction-timeout.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion2api-integration-fixes.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-claim-verdict-render.patch"),
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-chat-input-layout.patch")
    )

    # 1. Get submodule commit
    $SubmoduleCommit = ""
    try {
        $SubmoduleCommit = (git -C $CouncilRoot rev-parse HEAD 2>$null).Trim()
    } catch {
        # Fallback if git fails
    }

    # 2. Get hash of all patch files that exist
    $PatchHashes = ""
    foreach ($file in $PatchFiles) {
        if (Test-Path $file) {
            $hash = Get-Sha256Hash -Path $file
            $fileName = Split-Path $file -Leaf
            $PatchHashes += "$fileName=$hash`n"
        }
    }

    $ExpectedState = "SubmoduleCommit=$SubmoduleCommit`n$PatchHashes"

    $MarkerFile = Join-Path $CouncilRoot ".patches-applied"
    $CurrentState = ""
    if (Test-Path $MarkerFile) {
        $CurrentState = Get-Content -Raw -Path $MarkerFile
    }

    if ($CurrentState -eq $ExpectedState) {
        if (Test-CouncilPatchesPresent -CouncilRoot $CouncilRoot -RepoRoot $RepoRoot) {
            Write-Step "LLM Council patches already applied (matching marker file found)"
            return
        }

        Write-Warning "Patch marker matched but council checkout is missing patches; re-applying."
        Remove-Item $MarkerFile -Force -ErrorAction SilentlyContinue
    }

    Write-Step "Submodule patches not applied or dirty; resetting and applying all patches"
    Push-Location $CouncilRoot
    try {
        $DirtyStatus = cmd.exe /c "git status --porcelain" 2>$null
        if ($DirtyStatus) {
            Write-Warning "Council checkout has uncommitted changes; backing up before reset."
            $BackupDir = "${CouncilRoot}.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Path $CouncilRoot -Destination $BackupDir -Recurse -Force
            Write-Step "Backup created at: $BackupDir"
        }
        cmd.exe /c "git checkout -- ."
        cmd.exe /c "git clean -fd"
    } finally {
        Pop-Location
    }

    # Now apply the patches in strict order. Hidden post-hook chaining is intentionally disabled.
    # Stale/colliding PR-backed patches are skipped when equivalent code is already present.
    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-custom-model-icons.patch") `
        -Name "LLM Council custom model brand icons" `
        -Optional

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-custom-provider-initial-setup.patch") `
        -Name "LLM Council custom provider initial setup detection"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-first-message-title.patch") `
        -Name "LLM Council first message conversation titles"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-new-chat-stream-race.patch") `
        -Name "LLM Council new chat stream race guard"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion2api-file-uploads.patch") `
        -Name "LLM Council Notion2API file uploads"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion2api-upload-rate-limit.patch") `
        -Name "LLM Council Notion2API upload rate-limit guard" `
        -Optional

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-preflight-rate-limit.patch") `
        -Name "LLM Council preflight rate-limit retry and soft-fail"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion2api-preflight-skip.patch") `
        -Name "LLM Council Notion2API preflight skip"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-configurable-model-timeout.patch") `
        -Name "LLM Council configurable model timeout"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-stage1-attachments-wireup.patch") `
        -Name "LLM Council stage1 attachments wireup"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion2api-stage1-stagger.patch") `
        -Name "LLM Council Notion2API stage1 stagger"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-custom-openai-runtime-retry.patch") `
        -Name "LLM Council custom OpenAI runtime 429 retry with backoff" `
        -Optional

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-strip-reasoning-preamble.patch") `
        -Name "LLM Council strip untagged reasoning preamble"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-model-timeout-query-default.patch") `
        -Name "LLM Council default query timeout from settings"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-chairman-extended-timeout.patch") `
        -Name "LLM Council chairman and stage 4 extended timeout"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion-attachment-endpoint-guards.patch") `
        -Name "LLM Council Notion2API attachment endpoint guards"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-debate-claim-extraction-timeout.patch") `
        -Name "LLM Council debate claim extraction extended timeout"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-notion2api-integration-fixes.patch") `
        -Name "LLM Council Notion2API integration fixes"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-claim-verdict-render.patch") `
        -Name "LLM Council claim verdict structured render"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-chat-input-layout.patch") `
        -Name "LLM Council chat input layout clearance"

    # Write marker file if we got here successfully
    Set-Content -Path $MarkerFile -Value $ExpectedState -NoNewline
    Write-Step "Patches successfully applied and marker file written"
}

Export-ModuleMember -Function Initialize-Repo, Get-Python, Update-RepoPatch, Apply-Notion2ApiPatches, Apply-SubmodulePatches, Test-CouncilPatchesPresent, Test-PatchEquivalentPresent
