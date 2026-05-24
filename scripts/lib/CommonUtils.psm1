function Write-Step
{
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Read-JsonFile
{
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return $null
    }
    return Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function ConvertTo-StringArray
{
    param($Value)
    if ($null -eq $Value) {
        return @()
    }
    return @($Value | ForEach-Object { [string]$_ })
}

function Get-Sha256Hash
{
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha256.ComputeHash($stream)
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }

    return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
}

Export-ModuleMember -Function Write-Step, Read-JsonFile, ConvertTo-StringArray, Get-Sha256Hash
