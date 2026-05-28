$commonUtilsPath = Join-Path $PSScriptRoot "CommonUtils.psm1"
if (Test-Path $commonUtilsPath) {
    Import-Module $commonUtilsPath
}

function Get-State
{
    param([string]$StateFile)

    $state = Read-JsonFile -Path $StateFile
    if (-not $state) {
        $state = [pscustomobject]@{}
    }

    foreach ($propertyName in @("notion", "councilBackend", "councilFrontend")) {
        if (-not ($state.PSObject.Properties.Name -contains $propertyName)) {
            $state | Add-Member -NotePropertyName $propertyName -NotePropertyValue $null
        }
    }

    return $state
}

function Save-State
{
    param($State, [string]$StateFile)
    $json = $State | ConvertTo-Json -Depth 20
    
    # Write UTF8 WITHOUT BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($StateFile, $json, $utf8NoBom)
}

Export-ModuleMember -Function Get-State, Save-State
