function Get-State
{
    param([string]$StateFile)
    $state = Read-JsonFile -Path $StateFile
    if ($state) {
        return $state
    }
    return [pscustomobject]@{
        notion = $null
        councilBackend = $null
        councilFrontend = $null
    }
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
