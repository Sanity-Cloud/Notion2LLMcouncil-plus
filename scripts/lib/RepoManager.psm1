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



    $PatchFilesList = @(
        @{ Name="scripts\patches\the-ai-counsel-custom-model-icons.patch"; PrId=$null }
        @{ Name="scripts\patches\the-ai-counsel-custom-provider-initial-setup.patch"; PrId=$null }
        @{ Name="scripts\patches\the-ai-counsel-first-message-title.patch"; PrId=$null }
        @{ Name="scripts\patches\the-ai-counsel-new-chat-stream-race.patch"; PrId=$null }
        @{ Name="scripts\patches\the-ai-counsel-notion2api-file-uploads.patch"; PrId=6 }
        @{ Name="scripts\patches\the-ai-counsel-notion2api-upload-rate-limit.patch"; PrId=$null }
        @{ Name="scripts\patches\the-ai-counsel-notion2api-save-export.patch"; PrId=$null }
        @{ Name="scripts\patches\the-ai-counsel-preflight-rate-limit.patch"; PrId=$null }
        @{ Name="scripts\patches\the-ai-counsel-custom-openai-runtime-retry.patch"; PrId=5 }
    )

    $PatchFiles = foreach ($p in $PatchFilesList) {
        $patchPath = Join-Path $RepoRoot $p.Name

        if (-not (Test-Path $patchPath)) {
            Write-Warning "Patch file not found: $patchPath"
            continue
        }

        if ($p.PrId -and (Test-PrMerged -PrId $p.PrId -RepoUrl $RemoteUrl)) {
            Write-Host "Skipping $($p.Name) because upstream PR #$($p.PrId) is merged."
            continue
        }

        $patchPath
    }

    # 1. Get submodule commit
    $SubmoduleCommit = ""
    try {
        $SubmoduleCommit = (git -C $CouncilRoot rev-parse HEAD 2>$null).Trim()
    } catch {
        # Fallback if git fails
    }

    # 2. Get hash of all patch files that exist
    $PatchHashes = ""
    $LedgerEntries = @()
    foreach ($file in $PatchFiles) {
        if (Test-Path $file) {
            $hash = Get-Sha256Hash -Path $file
            $fileName = Split-Path $file -Leaf
            $PatchHashes += "$fileName=$hash`n"

            # Identify PR number if mapped
            $prId = $null
            foreach ($p in $PatchFilesList) {
                if (($p.Name -replace '\\', '/') -match ($fileName -replace '\\', '/')) {
                    $prId = $p.PrId
                    break
                }
            }

            $LedgerEntries += @{
                name = $fileName -replace "\.patch$", ""
                file = "scripts/patches/$fileName"
                status = "applied"
                upstreamPr = $prId
                supersededByMerge = $false
            }
        }
    }

    $LedgerObject = @{
        base = "the-ai-counsel@$SubmoduleCommit"
        patches = $LedgerEntries
    }

    $ExpectedState = "SubmoduleCommit=$SubmoduleCommit`n$PatchHashes"

    $LedgerFile = Join-Path $RepoRoot "patches.json"
    $LedgerJson = $LedgerObject | ConvertTo-Json -Depth 5
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LedgerFile, $LedgerJson, $utf8NoBom)

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

Export-ModuleMember -Function Initialize-Repo, Get-Python, Update-RepoPatch, Apply-SubmodulePatches, Test-PrMerged


function Get-GitHubOwnerRepoFromRemoteUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepoUrl
    )

    $url = $RepoUrl.Trim()

    if ($url -match '^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$') {
        return "$($Matches.owner)/$($Matches.repo)"
    }

    if ($url -match '^git@github\.com:(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') {
        return "$($Matches.owner)/$($Matches.repo)"
    }

    if ($url -match '^([^/\s]+)/([^/\s]+)$') {
        return "$($Matches[1])/$($Matches[2])"
    }

    throw "Could not parse GitHub owner/repo from remote URL: $RepoUrl"
}

function Test-PrMerged {
    param(
        [Parameter(Mandatory = $true)]
        [int] $PrId,

        [Parameter(Mandatory = $true)]
        [string] $RepoUrl
    )

    try {
        $ownerRepo = Get-GitHubOwnerRepoFromRemoteUrl -RepoUrl $RepoUrl
    }
    catch {
        Write-Warning "Could not determine GitHub repo for PR #$PrId. Assuming not merged. $($_.Exception.Message)"
        return $false
    }

    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCommand) {
        try {
            $mergedText = & gh pr view $PrId `
                --repo $ownerRepo `
                --json merged `
                --jq ".merged" 2>$null

            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($mergedText)) {
                return ($mergedText.Trim().ToLowerInvariant() -eq "true")
            }

            Write-Warning "gh could not determine merge status for PR #$PrId in $ownerRepo. Falling back to GitHub API."
        }
        catch {
            Write-Warning "gh failed while checking PR #$PrId in $ownerRepo. Falling back to GitHub API. $($_.Exception.Message)"
        }
    }

    try {
        $headers = @{
            "Accept"               = "application/vnd.github+json"
            "X-GitHub-Api-Version" = "2022-11-28"
            "User-Agent"           = "Notion2Council-Launcher"
        }

        $token = $env:GH_TOKEN
        if ([string]::IsNullOrWhiteSpace($token)) {
            $token = $env:GITHUB_TOKEN
        }

        if (-not [string]::IsNullOrWhiteSpace($token)) {
            $headers["Authorization"] = "Bearer $token"
        }

        $uri = "https://api.github.com/repos/$ownerRepo/pulls/$PrId"
        $pr = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop

        return -not [string]::IsNullOrWhiteSpace($pr.merged_at)
    }
    catch {
        Write-Warning "Could not determine merge status for PR #$PrId in $ownerRepo. Assuming not merged. $($_.Exception.Message)"
        return $false
    }
}
