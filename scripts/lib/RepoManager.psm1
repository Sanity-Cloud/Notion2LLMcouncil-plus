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

    Push-Location $Root
    try {
        try {
            cmd.exe /c "git apply --check --ignore-whitespace `"$PatchPath`" 2>nul"
            if ($LASTEXITCODE -eq 0) {
                Write-Step "Applying patch: $Name"
                cmd.exe /c "git apply --ignore-whitespace `"$PatchPath`""
                if ($LASTEXITCODE -ne 0) { throw "Failed to apply patch: $Name" }
                Invoke-RepoPatchPostHooks -Root $Root -PatchPath $PatchPath -Name $Name
                return
            }

            cmd.exe /c "git apply --reverse --check --ignore-whitespace `"$PatchPath`" 2>nul"
            if ($LASTEXITCODE -eq 0) {
                Write-Step "Patch already applied: $Name"
                Invoke-RepoPatchPostHooks -Root $Root -PatchPath $PatchPath -Name $Name
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
                    Invoke-RepoPatchPostHooks -Root $Root -PatchPath $PatchPath -Name $Name
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
        (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-custom-openai-runtime-retry.patch")
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
        Write-Step "LLM Council patches already applied (matching marker file found)"
        return
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

    # Now apply the patches in strict order. The race patch post-hook applies
    # the upload patch, and the upload patch post-hook applies the upload
    # rate-limit guard.
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
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-preflight-rate-limit.patch") `
        -Name "LLM Council preflight rate-limit retry and soft-fail"

    Update-RepoPatch `
        -Root $CouncilRoot `
        -PatchPath (Join-Path $RepoRoot "scripts\patches\the-ai-counsel-custom-openai-runtime-retry.patch") `
        -Name "LLM Council custom OpenAI runtime 429 retry with backoff"

    # Write marker file if we got here successfully
    Set-Content -Path $MarkerFile -Value $ExpectedState -NoNewline
    Write-Step "Patches successfully applied and marker file written"
}

Export-ModuleMember -Function Initialize-Repo, Get-Python, Update-RepoPatch, Apply-SubmodulePatches
