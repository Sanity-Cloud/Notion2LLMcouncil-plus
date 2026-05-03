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

Export-ModuleMember -Function Write-Step, Read-JsonFile, ConvertTo-StringArray
