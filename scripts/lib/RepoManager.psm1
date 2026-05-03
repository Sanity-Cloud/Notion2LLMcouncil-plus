function Initialize-Repo {
    param(
        [string]$Path,
        [string]$Url,
        [string]$Branch = ""
    )

    if (Test-Path $Path) {
        return
    }

    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    
    Write-Step "Cloning $Url to $Path"
    if ($Branch) {
        git clone --branch $Branch $Url $Path
    } else {
        git clone $Url $Path
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

Export-ModuleMember -Function Initialize-Repo, Get-Python
