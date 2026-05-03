function Use-ConfigValue {
    param($Value, $Fallback)
    if ($null -eq $Value -or "$Value" -eq "") {
        return $Fallback
    }
    return $Value
}

function Read-IntegrationConfig {
    param([string]$RepoRoot, [string]$ConfigPath)
    $defaultPath = Join-Path $RepoRoot "config\default.json"
    $localPath = if ($ConfigPath) { $ConfigPath } else { Join-Path $RepoRoot "config\local.json" }
    
    $defaultConfig = Read-JsonFile -Path $defaultPath
    $localConfig = Read-JsonFile -Path $localPath

    return @{
        Default = $defaultConfig
        Local = $localConfig
        LocalPath = $localPath
    }
}

function Get-ConfigProperty {
    param(
        [hashtable]$Config,
        [string[]]$Path,
        $Fallback = $null
    )

    foreach ($source in @($Config.Local, $Config.Default)) {
        $cursor = $source
        foreach ($part in $Path) {
            if ($null -eq $cursor -or -not ($cursor.PSObject.Properties.Name -contains $part)) {
                $cursor = $null
                break
            }
            $cursor = $cursor.$part
        }
        if ($null -ne $cursor -and "$cursor" -ne "") {
            return $cursor
        }
    }
    return $Fallback
}

Export-ModuleMember -Function Use-ConfigValue, Read-IntegrationConfig, Get-ConfigProperty
