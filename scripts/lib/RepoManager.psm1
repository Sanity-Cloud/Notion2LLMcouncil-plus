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
                    git -C $Path checkout $Branch
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

function Update-RepoPatch {
    param(
        [string]$Root,
        [string]$PatchPath,
        [string]$Name
    )

    if (-not (Test-Path $PatchPath)) { return }

    Push-Location $Root
    try {
        cmd.exe /c "git apply --check `"$PatchPath`" 2>nul"
        if ($LASTEXITCODE -eq 0) {
            Write-Step "Applying patch: $Name"
            cmd.exe /c "git apply `"$PatchPath`""
            if ($LASTEXITCODE -ne 0) { throw "Failed to apply patch: $Name" }
            return
        }

        cmd.exe /c "git apply --reverse --check `"$PatchPath`" 2>nul"
        if ($LASTEXITCODE -eq 0) {
            Write-Step "Patch already applied: $Name"
            return
        }

        throw "Patch cannot be applied cleanly: $Name"
    } finally {
        Pop-Location
    }
}

Export-ModuleMember -Function Initialize-Repo, Get-Python, Update-RepoPatch
