if (-not (Get-Variable -Name EnableStrongRepair -ErrorAction SilentlyContinue)) {
    $EnableStrongRepair = $false
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VideoExtensions = @('.mp4', '.mkv', '.mts', '.m2ts', '.mov', '.avi', '.webm', '.wmv')
$KeywordPatterns = @('Icaros', 'MPC-HC', 'MPC-BE', 'Media Player Classic', 'K-Lite', 'LAV', 'Microsoft', 'Windows Media Player')
$PreviewHandlerGuid = '{8895b1c6-b41f-4c1c-a562-0d564250836f}'
$ThumbnailHandlerGuid = '{e357fccd-a995-4576-b01f-234630154e96}'
$PropertyHandlerGuid = '{bb2e617c-0920-11d1-9a0b-00c04fc2d6c1}'
$IconCachePattern = 'iconcache_*.db'
$AutoDestinationsPattern = '*.automaticDestinations-ms'
$CustomDestinationsPattern = '*.customDestinations-ms'
$ExplorerCacheRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
$ExplorerRecentRoot = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 92)
    Write-Host $Title
    Write-Host ('=' * 92)
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-Directory {
    param([Parameter(Mandatory)] [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Export-RegistryKey {
    param(
        [Parameter(Mandatory)] [string]$RegistryPath,
        [Parameter(Mandatory)] [string]$DestinationFile
    )

    $destinationParent = Split-Path -Parent $DestinationFile
    New-Directory -Path $destinationParent

    if (Test-Path -LiteralPath ("Registry::$RegistryPath")) {
        & reg.exe export $RegistryPath $DestinationFile /y | Out-Null
        return $true
    }

    return $false
}

function Import-RegistryBackups {
    param([Parameter(Mandatory)] [string]$BackupRoot)

    Get-ChildItem -LiteralPath $BackupRoot -Filter '*.reg' -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            Write-Host "Importing backup: $($_.Name)"
            & reg.exe import $_.FullName | Out-Null
        }
}

function Stop-ExplorerCleanly {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Start-Explorer {
    Start-Process explorer.exe | Out-Null
}

function Remove-CacheFiles {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Pattern,
        [ref]$RemovedList
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -Filter $Pattern -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $RemovedList.Value += $_.FullName
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
}

function Get-RegistryValuesSafe {
    param([Parameter(Mandatory)] [string]$RegistryPath)

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath ("Registry::$RegistryPath"))) {
        return $result
    }

    try {
        $item = Get-Item -LiteralPath ("Registry::$RegistryPath") -ErrorAction Stop
        $props = Get-ItemProperty -LiteralPath ("Registry::$RegistryPath") -ErrorAction SilentlyContinue
        foreach ($name in $item.GetValueNames()) {
            $result[$name] = $props.$name
        }
    }
    catch {
    }

    return $result
}

function Resolve-HandlerInfo {
    param([string]$Clsid)

    if ([string]::IsNullOrWhiteSpace($Clsid)) {
        return [pscustomobject]@{
            Clsid = $null
            Name = $null
            InprocServer32 = $null
        }
    }

    $clsidPath = "Registry::HKEY_CLASSES_ROOT\CLSID\$Clsid"
    if (-not (Test-Path -LiteralPath $clsidPath)) {
        return [pscustomobject]@{
            Clsid = $Clsid
            Name = $null
            InprocServer32 = $null
        }
    }

    $name = $null
    $inproc = $null
    try {
        $key = Get-Item -LiteralPath $clsidPath -ErrorAction Stop
        $name = $key.GetValue('', $null)
        $inprocKey = Get-Item -LiteralPath (Join-Path $clsidPath 'InprocServer32') -ErrorAction SilentlyContinue
        if ($inprocKey) {
            $inproc = $inprocKey.GetValue('', $null)
        }
    }
    catch {
    }

    [pscustomobject]@{
        Clsid = $Clsid
        Name = $name
        InprocServer32 = $inproc
    }
}

function Get-PreviewHandlersReport {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PreviewHandlers',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\PreviewHandlers'
    )

    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        $values = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
        $key = Get-Item -LiteralPath $path -ErrorAction Stop
        foreach ($valueName in $key.GetValueNames()) {
            $resolved = Resolve-HandlerInfo -Clsid $valueName
            $text = @($valueName, $values.$valueName, $resolved.Name, $resolved.InprocServer32) -join ' '
            $termMatches = @()
            foreach ($pattern in $KeywordPatterns) {
                if ($text -match [regex]::Escape($pattern)) {
                    $termMatches += $pattern
                }
            }

            [pscustomobject]@{
                View = if ($path -like '*WOW6432Node*') { '32-bit' } else { '64-bit' }
                Clsid = $valueName
                Name = $values.$valueName
                ResolvedName = $resolved.Name
                InprocServer32 = $resolved.InprocServer32
                MatchedTerms = ($termMatches | Select-Object -Unique) -join ', '
            }
        }
    }
}

function Get-VideoExtensionReport {
    param([Parameter(Mandatory)] [string]$Extension)

    $systemAssocPath = "HKCR:\SystemFileAssociations\$Extension"
    $extPath = "HKCR:\$Extension"
    $extValues = Get-RegistryValuesSafe -RegistryPath $extPath.Replace('HKCR:\', 'HKEY_CLASSES_ROOT\')
    $systemValues = Get-RegistryValuesSafe -RegistryPath $systemAssocPath.Replace('HKCR:\', 'HKEY_CLASSES_ROOT\')

    $previewClsid = $null
    $thumbnailClsid = $null
    $propertyClsid = $null

    $previewExPath = "Registry::HKEY_CLASSES_ROOT\$Extension\ShellEx\$PreviewHandlerGuid"
    $thumbnailExPath = "Registry::HKEY_CLASSES_ROOT\$Extension\ShellEx\$ThumbnailHandlerGuid"
    $propertyExPath = "Registry::HKEY_CLASSES_ROOT\$Extension\ShellEx\$PropertyHandlerGuid"

    if (Test-Path -LiteralPath $previewExPath) {
        try { $previewClsid = (Get-ItemProperty -LiteralPath $previewExPath -ErrorAction Stop).'(default)' } catch { }
    }
    if (Test-Path -LiteralPath $thumbnailExPath) {
        try { $thumbnailClsid = (Get-ItemProperty -LiteralPath $thumbnailExPath -ErrorAction Stop).'(default)' } catch { }
    }
    if (Test-Path -LiteralPath $propertyExPath) {
        try { $propertyClsid = (Get-ItemProperty -LiteralPath $propertyExPath -ErrorAction Stop).'(default)' } catch { }
    }

    $previewResolved = Resolve-HandlerInfo -Clsid $previewClsid
    $thumbnailResolved = Resolve-HandlerInfo -Clsid $thumbnailClsid
    $propertyResolved = Resolve-HandlerInfo -Clsid $propertyClsid

    $shellMatches = @()
    $shellRootPath = "Registry::HKEY_CLASSES_ROOT\SystemFileAssociations\$Extension\Shell"
    if (Test-Path -LiteralPath $shellRootPath) {
        Get-ChildItem -LiteralPath $shellRootPath -ErrorAction SilentlyContinue | ForEach-Object {
            $subKey = $_.PSPath
            $textParts = @($_.PSChildName)
            try {
                $subValues = Get-ItemProperty -LiteralPath $subKey -ErrorAction SilentlyContinue
                $textParts += $subValues.'(default)'
                $textParts += $subValues.Icon
            }
            catch {
            }
            $commandPath = "$subKey\command"
            if (Test-Path -LiteralPath $commandPath) {
                try {
                    $commandValues = Get-ItemProperty -LiteralPath $commandPath -ErrorAction SilentlyContinue
                    $textParts += $commandValues.'(default)'
                }
                catch {
                }
            }
            $text = ($textParts -join ' ')
            foreach ($pattern in $KeywordPatterns) {
                if ($text -match [regex]::Escape($pattern)) {
                    $shellMatches += [pscustomobject]@{
                        Location = "$systemAssocPath\Shell\$($_.PSChildName)"
                        MatchedTerm = $pattern
                        Details = $text.Trim()
                    }
                    break
                }
            }
        }
    }

    [pscustomobject]@{
        Extension = $Extension
        DefaultProgId = $extValues['']
        ContentType = $extValues['Content Type']
        PerceivedType = $extValues['PerceivedType']
        PreviewHandlerClsid = $previewClsid
        PreviewHandlerName = $previewResolved.Name
        PreviewHandlerInprocServer32 = $previewResolved.InprocServer32
        ThumbnailHandlerClsid = $thumbnailClsid
        ThumbnailHandlerName = $thumbnailResolved.Name
        ThumbnailHandlerInprocServer32 = $thumbnailResolved.InprocServer32
        PropertyHandlerClsid = $propertyClsid
        PropertyHandlerName = $propertyResolved.Name
        PropertyHandlerInprocServer32 = $propertyResolved.InprocServer32
        PreviewDetails = $systemValues['PreviewDetails']
        ExtendedTileInfo = $systemValues['ExtendedTileInfo']
        InfoTip = $systemValues['InfoTip']
        ShellMatches = $shellMatches
    }
}

function Build-Report {
    param(
        [Parameter(Mandatory)] [object[]]$PreviewHandlers,
        [Parameter(Mandatory)] [object[]]$VideoReports,
        [Parameter(Mandatory)] [string]$Title
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine($Title)
    [void]$builder.AppendLine(('=' * 92))
    [void]$builder.AppendLine('Preview handlers:')
    [void]$builder.AppendLine((($PreviewHandlers | Format-Table -AutoSize | Out-String).TrimEnd()))
    [void]$builder.AppendLine('')
    [void]$builder.AppendLine('Video extension references:')
    foreach ($row in $VideoReports) {
        [void]$builder.AppendLine((($row | Select-Object Extension, DefaultProgId, ContentType, PerceivedType, PreviewHandlerClsid, PreviewHandlerName, PreviewHandlerInprocServer32, ThumbnailHandlerClsid, ThumbnailHandlerName, ThumbnailHandlerInprocServer32, PropertyHandlerClsid, PropertyHandlerName, PropertyHandlerInprocServer32 | Format-List | Out-String).TrimEnd()))
        if ($row.PreviewDetails) {
            [void]$builder.AppendLine('PreviewDetails contains:')
            [void]$builder.AppendLine($row.PreviewDetails)
        }
        if ($row.ShellMatches) {
            [void]$builder.AppendLine('Shell references:')
            [void]$builder.AppendLine((($row.ShellMatches | Format-Table -AutoSize | Out-String).TrimEnd()))
        }
        [void]$builder.AppendLine('')
    }
    return $builder.ToString()
}

function Get-IssueSummary {
    param([Parameter(Mandatory)] [object[]]$VideoReports)

    $hasStaleHandlers = $false
    $hasPreviewHandlers = $false
    $hasThirdPartyThumb = $false
    foreach ($row in $VideoReports) {
        $handlerText = @($row.PreviewHandlerClsid, $row.PreviewHandlerName, $row.PreviewHandlerInprocServer32, $row.ThumbnailHandlerClsid, $row.ThumbnailHandlerName, $row.ThumbnailHandlerInprocServer32, $row.PropertyHandlerClsid, $row.PropertyHandlerName, $row.PropertyHandlerInprocServer32, $row.PreviewDetails) -join ' '
        if ($handlerText -match 'Microsoft Windows Media Player|Microsoft|Icaros') {
            $hasPreviewHandlers = $true
        }
        if ($handlerText -match 'Icaros|MPC-HC|MPC-BE|Media Player Classic|K-Lite|LAV') {
            $hasThirdPartyThumb = $true
        }
        if ($row.PreviewHandlerClsid -or $row.ThumbnailHandlerClsid -or $row.PropertyHandlerClsid) {
            $hasStaleHandlers = $true
        }
    }

    if ($hasStaleHandlers -and $hasThirdPartyThumb) {
        return 'third-party thumbnail provider'
    }
    if ($hasStaleHandlers -and $hasPreviewHandlers) {
        return 'preview handler registration'
    }
    return 'stale thumbnail cache / preview pane UI state'
}

function Invoke-StrongRepair {
    param(
        [Parameter(Mandatory)] [object[]]$VideoReports,
        [Parameter(Mandatory)] [string]$BackupRoot
    )

    $changedKeys = @()
    foreach ($row in $VideoReports) {
        $extension = $row.Extension
        $systemAssocPath = "HKCR:\SystemFileAssociations\$extension"
        $extPath = "HKCR:\$extension"

        $safeHandler = $false
        if ($row.ThumbnailHandlerName -match 'Icaros') {
            $safeHandler = $true
        }

        $handlerText = @($row.ThumbnailHandlerClsid, $row.ThumbnailHandlerName, $row.ThumbnailHandlerInprocServer32, $row.PropertyHandlerClsid, $row.PropertyHandlerName, $row.PropertyHandlerInprocServer32) -join ' '
        if ($safeHandler) {
            continue
        }

        $needsChange = $handlerText -match 'MPC-HC|MPC-BE|Media Player Classic|K-Lite|LAV|PotPlayer|Daum|VLC|PowerToys|Monaco'
        if (-not $needsChange) {
            continue
        }

        foreach ($targetPath in @(
            "Registry::HKEY_CLASSES_ROOT\$extension\ShellEx\$ThumbnailHandlerGuid",
            "Registry::HKEY_CLASSES_ROOT\$extension\ShellEx\$PropertyHandlerGuid",
            "Registry::HKEY_CLASSES_ROOT\SystemFileAssociations\$extension\ShellEx\$ThumbnailHandlerGuid",
            "Registry::HKEY_CLASSES_ROOT\SystemFileAssociations\$extension\ShellEx\$PropertyHandlerGuid"
        )) {
            if (Test-Path -LiteralPath $targetPath) {
                $safeName = ($targetPath -replace '[\\/:*?"<>| ]', '_').Trim('_')
                $regBackup = Join-Path $BackupRoot "$safeName.backup.reg"
                $regPath = ($targetPath -replace '^HKCR:\\', 'HKEY_CLASSES_ROOT\\') -replace '^HKCR:', 'HKEY_CLASSES_ROOT'
                if (-not (Test-Path -LiteralPath $regBackup)) {
                    & reg.exe export $regPath $regBackup /y | Out-Null
                }
                Write-Host "Removing conflicting handler reference: $targetPath"
                Remove-Item -LiteralPath $targetPath -Force -Recurse -ErrorAction SilentlyContinue
                $changedKeys += $targetPath
            }
        }
    }

    return $changedKeys
}

if (-not (Test-IsAdmin)) {
    throw 'Run this script from an elevated PowerShell session.'
}

$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
    $desktop = [Environment]::GetFolderPath('MyDocuments')
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $desktop "ExplorerPosterFrameRepair-$timestamp"
New-Directory -Path $backupRoot

Write-Section 'Phase 1 - Backup and diagnostics'
Write-Host "Backup folder: $backupRoot"
Write-Host 'Capturing registry backups before any changes.'

$registryTargets = @(
    'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer',
    'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
    'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Modules\GlobalSettings',
    'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\PreviewHandlers',
    'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\PreviewHandlers'
)

foreach ($extension in $VideoExtensions) {
    $registryTargets += "HKEY_CLASSES_ROOT\SystemFileAssociations\$extension"
}

foreach ($target in $registryTargets) {
    $safeName = ($target -replace '[\\/:*?"<>| ]', '_').Trim('_')
    $destination = Join-Path $backupRoot "$safeName.reg"
    [void](Export-RegistryKey -RegistryPath $target -DestinationFile $destination)
}

$previewHandlersBefore = @(Get-PreviewHandlersReport)
$videoReportsBefore = foreach ($extension in $VideoExtensions) { Get-VideoExtensionReport -Extension $extension }
    $summaryBefore = Get-IssueSummary -VideoReports $videoReportsBefore
$reportBefore = Build-Report -PreviewHandlers $previewHandlersBefore -VideoReports $videoReportsBefore -Title 'Before repair'

$reportPath = Join-Path $backupRoot 'before-after-report.txt'
Set-Content -LiteralPath $reportPath -Value $reportBefore -Encoding UTF8

Write-Host $reportBefore
Write-Host ''
Write-Host "Likely issue category: $summaryBefore"

Write-Section 'Phase 2 - Stop Explorer and clear non-thumbnail caches'
Write-Host 'Stopping Explorer cleanly so Explorer caches are not in use.'
Stop-ExplorerCleanly

$removedCaches = @()
Remove-CacheFiles -Path $ExplorerCacheRoot -Pattern $IconCachePattern -RemovedList ([ref]$removedCaches)
Remove-CacheFiles -Path $ExplorerRecentRoot -Pattern $AutoDestinationsPattern -RemovedList ([ref]$removedCaches)
Remove-CacheFiles -Path $ExplorerRecentRoot -Pattern $CustomDestinationsPattern -RemovedList ([ref]$removedCaches)

Write-Host 'Resetting Preview Pane layout/state.'
try {
    Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Modules\GlobalSettings\Sizer' -Name 'DetailsContainerSizer' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Modules\GlobalSettings\Sizer' -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Host "Sizer reset warning: $($_.Exception.Message)"
}

Write-Host 'Re-enabling Explorer preview handlers.'
New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Force | Out-Null
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowPreviewHandlers' -PropertyType DWord -Value 1 -Force | Out-Null

Write-Section 'Phase 3 - Optional stronger repair'
if ($EnableStrongRepair) {
    Write-Host 'Strong repair is enabled. Removing only conflicting third-party thumbnail/property references.'
    $changedKeys = Invoke-StrongRepair -VideoReports $videoReportsBefore -BackupRoot $backupRoot
    if ($changedKeys.Count -gt 0) {
        Write-Host 'Changed registry paths:'
        $changedKeys | ForEach-Object { Write-Host "  $_" }
    }
    else {
        Write-Host 'No third-party thumbnail/property references required removal.'
    }
}
else {
    Write-Host 'Strong repair is disabled. No thumbnail/property references were removed.'
}

Write-Section 'Phase 4 - Restart Explorer'
Write-Host 'Restarting Explorer to flush stale preview and thumbnail surfaces.'
Start-Explorer

Start-Sleep -Milliseconds 1500

$previewHandlersAfter = @(Get-PreviewHandlersReport)
$videoReportsAfter = foreach ($extension in $VideoExtensions) { Get-VideoExtensionReport -Extension $extension }
$summaryAfter = Get-IssueSummary -VideoReports $videoReportsAfter
$reportAfter = Build-Report -PreviewHandlers $previewHandlersAfter -VideoReports $videoReportsAfter -Title 'After repair'

$reportCombined = @"
$reportBefore

$reportAfter

Removed cache files:
$((if ($removedCaches.Count -gt 0) { ($removedCaches | Sort-Object -Unique | ForEach-Object { "- $_" }) -join [Environment]::NewLine } else { '- None' }))

Likely issue category before repair: $summaryBefore
Likely issue category after repair: $summaryAfter
"@

Set-Content -LiteralPath $reportPath -Value $reportCombined -Encoding UTF8

$rollbackScriptPath = Join-Path $backupRoot 'Rollback-ExplorerPosterFrameRepair.ps1'
$rollbackScript = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
`$BackupRoot = '$backupRoot'

if (-not (Test-Path -LiteralPath `$BackupRoot)) {
    throw 'Backup folder not found: ' + `$BackupRoot
}

Write-Host 'Restoring registry backups from:' `$BackupRoot
Get-ChildItem -LiteralPath `$BackupRoot -Filter '*.reg' | Sort-Object Name | ForEach-Object {
    Write-Host "Importing `$(`$_.Name)"
    & reg.exe import `$_.FullName | Out-Null
}

Write-Host 'Restarting Explorer after rollback.'
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
Write-Host 'Rollback complete.'
Pause
"@
Set-Content -LiteralPath $rollbackScriptPath -Value $rollbackScript -Encoding UTF8

Write-Section 'Summary'
Write-Host "Backup folder: $backupRoot"
Write-Host "Report file:    $reportPath"
Write-Host "Rollback file:  $rollbackScriptPath"
Write-Host ''
Write-Host 'Rollback command:'
Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File `"$rollbackScriptPath`""
Write-Host ''
Write-Host 'Likely issue category before repair:'
Write-Host $summaryBefore
Write-Host 'Likely issue category after repair:'
Write-Host $summaryAfter
Write-Host ''
Write-Host 'Done. Press any key to exit.'
Pause