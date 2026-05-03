function Get-State {
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

function Save-State {
    param($State, [string]$StateFile)
    $State | ConvertTo-Json -Depth 20 | Set-Content -Path $StateFile -Encoding UTF8
}

Export-ModuleMember -Function Get-State, Save-State
