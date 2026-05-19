if (-not (Get-Variable -Name EnableStrongRepair -ErrorAction SilentlyContinue)) {
    $EnableStrongRepair = $false
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VideoExtensions = @('.mp4', '.mkv', '.mts', '.m2ts', '.mov', '.avi', '.webm', '.wmv')
$PreviewHandlerKey = '{8895b1c6-b41f-4c1c-a562-0d564250836f}'
$ThumbnailHandlerKey = '{e357fccd-a995-4576-b01f-234630154e96}'
$ShowPreviewHandlersPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$SizerPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Modules\GlobalSettings\Sizer'
$PreviewHandlersPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PreviewHandlers',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\PreviewHandlers'
)
$KeywordPatterns = @('MPC-HC', 'MPC-BE', 'Media Player Classic', 'Icaros', 'K-Lite', 'LAV', 'Microsoft', 'Windows Media Player')

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 80)
    Write-Host $Title
    Write-Host ('=' * 80)
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-RegExport {
    param(
        [Parameter(Mandatory)] [string]$RegistryPath,
        [Parameter(Mandatory)] [string]$DestinationPath
    )

    $parent = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath ("Registry::$RegistryPath")) {
        & reg.exe export $RegistryPath $DestinationPath /y | Out-Null
        return $true
    }

    return $false
}

function Invoke-RegAddDword {
    param(
        [Parameter(Mandatory)] [string]$RegistryPath,
        [Parameter(Mandatory)] [string]$ValueName,
        [Parameter(Mandatory)] [int]$Value
    )

    & reg.exe add $RegistryPath /v $ValueName /t REG_DWORD /d $Value /f | Out-Null
}

function Invoke-RegDeleteValue {
    param(
        [Parameter(Mandatory)] [string]$RegistryPath,
        [Parameter(Mandatory)] [string]$ValueName
    )

    & reg.exe delete $RegistryPath /v $ValueName /f | Out-Null
}

function Invoke-RegDeleteKey {
    param([Parameter(Mandatory)] [string]$RegistryPath)

    & reg.exe delete $RegistryPath /f /va | Out-Null
    & reg.exe delete $RegistryPath /f | Out-Null
}

function Get-RegistryKeyValues {
    param([Microsoft.Win32.RegistryKey]$Key)

    if (-not $Key) {
        return [ordered]@{}
    }

    $values = [ordered]@{}
    foreach ($valueName in $Key.GetValueNames()) {
        $values[$valueName] = $Key.GetValue($valueName)
    }

    return $values
}

function Open-ClassesRootKey {
    param([string]$SubKey)

    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, [Microsoft.Win32.RegistryView]::Default)
    return $root.OpenSubKey($SubKey)
}

function Open-LocalMachineKey {
    param(
        [Microsoft.Win32.RegistryView]$View,
        [string]$SubKey
    )

    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $View)
    return $root.OpenSubKey($SubKey)
}

function Get-ResolvedHandlerInfo {
    param([string]$Clsid)

    if ([string]::IsNullOrWhiteSpace($Clsid)) {
        return $null
    }

    $subKey = "CLSID\$Clsid"
    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::ClassesRoot, [Microsoft.Win32.RegistryView]::Default)
    $clsidKey = $root.OpenSubKey($subKey)
    if (-not $clsidKey) {
        return [pscustomobject]@{
            Clsid = $Clsid
            Name = $null
            InprocServer32 = $null
            IsResolved = $false
        }
    }

    $inproc = $clsidKey.OpenSubKey('InprocServer32')
    [pscustomobject]@{
        Clsid = $Clsid
        Name = $clsidKey.GetValue('DisplayName', $null)
        DefaultValue = $clsidKey.GetValue('', $null)
        InprocServer32 = if ($inproc) { $inproc.GetValue('', $null) } else { $null }
        IsResolved = $true
    }
}

function Get-PreviewHandlersReport {
    $rows = foreach ($path in $PreviewHandlersPaths) {
        $view = if ($path -like '*WOW6432Node*') { [Microsoft.Win32.RegistryView]::Registry32 } else { [Microsoft.Win32.RegistryView]::Registry64 }
        $key = Open-LocalMachineKey -View $view -SubKey 'SOFTWARE\Microsoft\Windows\CurrentVersion\PreviewHandlers'
        if (-not $key) { continue }

        foreach ($valueName in $key.GetValueNames()) {
            $handler = Get-ResolvedHandlerInfo -Clsid $valueName
            $matchedTerms = @()
            foreach ($term in $KeywordPatterns) {
                if (("$valueName $($key.GetValue($valueName)) $($handler.Name) $($handler.InprocServer32)") -match [regex]::Escape($term)) {
                    $matchedTerms += $term
                }
            }

            [pscustomobject]@{
                View = if ($view -eq [Microsoft.Win32.RegistryView]::Registry32) { '32-bit' } else { '64-bit' }
                Clsid = $valueName
                Name = $key.GetValue($valueName)
                ResolvedName = $handler.Name
                InprocServer32 = $handler.InprocServer32
                MatchedTerms = ($matchedTerms | Select-Object -Unique) -join ', '
            }
        }
    }

    return $rows | Sort-Object View, Name, Clsid
}

function Get-AssociationReport {
    param([string]$Extension)

    $extKey = Open-ClassesRootKey -SubKey $Extension
    $systemKey = Open-ClassesRootKey -SubKey "SystemFileAssociations\$Extension"
    $previewAssociationKey = if ($extKey) { $extKey.OpenSubKey("ShellEx\$PreviewHandlerKey") } else { $null }
    $systemPreviewAssociationKey = if ($systemKey) { $systemKey.OpenSubKey("ShellEx\$PreviewHandlerKey") } else { $null }
    $thumbnailAssociationKey = if ($extKey) { $extKey.OpenSubKey("ShellEx\$ThumbnailHandlerKey") } else { $null }

    $shellMatches = @()
    if ($systemKey) {
        $shellRoot = $systemKey.OpenSubKey('Shell')
        if ($shellRoot) {
            foreach ($subName in $shellRoot.GetSubKeyNames()) {
                $commandKey = $shellRoot.OpenSubKey("$subName\command")
                $shellKey = $shellRoot.OpenSubKey($subName)
                $combinedParts = @($subName)
                if ($shellKey) {
                    $combinedParts += $shellKey.GetValue('', $null)
                    $combinedParts += $shellKey.GetValue('Icon', $null)
                }
                if ($commandKey) {
                    $combinedParts += $commandKey.GetValue('', $null)
                }
                $combined = $combinedParts -join ' '
                foreach ($term in $KeywordPatterns) {
                    if ($combined -match [regex]::Escape($term)) {
                        $shellMatches += [pscustomobject]@{
                            Extension = $Extension
                            Location = "SystemFileAssociations\$Extension\Shell\$subName"
                            MatchedTerm = $term
                            Details = $combined.Trim()
                        }
                        break
                    }
                }
            }
        }
    }

    $previewHandlerClsid = $null
    if ($previewAssociationKey) {
        $previewHandlerClsid = $previewAssociationKey.GetValue('', $null)
    }
    elseif ($systemPreviewAssociationKey) {
        $previewHandlerClsid = $systemPreviewAssociationKey.GetValue('', $null)
    }

    $previewHandlerInfo = Get-ResolvedHandlerInfo -Clsid $previewHandlerClsid

    [pscustomobject]@{
        Extension = $Extension
        DefaultProgId = if ($extKey) { $extKey.GetValue('', $null) } else { $null }
        ContentType = if ($extKey) { $extKey.GetValue('Content Type', $null) } else { $null }
        PerceivedType = if ($extKey) { $extKey.GetValue('PerceivedType', $null) } else { $null }
        PreviewHandlerClsid = $previewHandlerClsid
        PreviewHandlerName = if ($previewHandlerInfo) { $previewHandlerInfo.Name } else { $null }
        PreviewHandlerInprocServer32 = if ($previewHandlerInfo) { $previewHandlerInfo.InprocServer32 } else { $null }
        ThumbnailHandlerClsid = if ($thumbnailAssociationKey) { $thumbnailAssociationKey.GetValue('', $null) } else { $null }
        PreviewDetailsHasIcaros = if ($systemKey) { ($systemKey.GetValue('PreviewDetails', '') -match 'Icaros') } else { $false }
        ShellMatches = $shellMatches
    }
}

function Format-Report {
    param(
        [Parameter(Mandatory)] [object[]]$PreviewHandlers,
        [Parameter(Mandatory)] [object[]]$Associations,
        [Parameter(Mandatory)] [object[]]$SuspiciousHits,
        [Parameter(Mandatory)] [object]$AdvancedState,
        [Parameter(Mandatory)] [string]$Heading
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine($Heading)
    [void]$builder.AppendLine(('=' * 80))
    [void]$builder.AppendLine('Explorer Advanced state:')
    [void]$builder.AppendLine((($AdvancedState | Format-List * | Out-String).TrimEnd()))
    [void]$builder.AppendLine('')
    [void]$builder.AppendLine('Preview handlers:')
    [void]$builder.AppendLine((($PreviewHandlers | Format-Table -AutoSize | Out-String).TrimEnd()))
    [void]$builder.AppendLine('')
    [void]$builder.AppendLine('Video associations:')
    foreach ($row in $Associations) {
        [void]$builder.AppendLine((($row | Select-Object Extension, DefaultProgId, ContentType, PerceivedType, PreviewHandlerClsid, PreviewHandlerName, PreviewHandlerInprocServer32, ThumbnailHandlerClsid, PreviewDetailsHasIcaros | Format-List | Out-String).TrimEnd()))
        if ($row.ShellMatches) {
            [void]$builder.AppendLine('  Shell references:')
            [void]$builder.AppendLine((($row.ShellMatches | Format-Table -AutoSize | Out-String).TrimEnd()))
        }
        [void]$builder.AppendLine('')
    }
    [void]$builder.AppendLine('Suspicious keyword hits:')
    if ($SuspiciousHits) {
        [void]$builder.AppendLine((($SuspiciousHits | Format-Table -AutoSize | Out-String).TrimEnd()))
    }
    else {
        [void]$builder.AppendLine('None')
    }

    return $builder.ToString()
}

function Save-ReportFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Content
    )

    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function New-RollbackScript {
    param([Parameter(Mandatory)] [string]$BackupRoot)

    $rollbackPath = Join-Path $BackupRoot 'Rollback-PreviewPaneRepair.ps1'
    $content = @"
Set-StrictMode -Version Latest

`$ErrorActionPreference = 'Stop'
`$backupRoot = '$BackupRoot'

if (-not (Test-Path -LiteralPath `$backupRoot)) {
    throw "Backup folder not found: `$backupRoot"
}

Write-Host 'Restoring registry backups from:' `$backupRoot
Get-ChildItem -LiteralPath `$backupRoot -Filter '*.reg' | Sort-Object Name | ForEach-Object {
    Write-Host "Importing `$(`$_.Name)..."
    & reg.exe import `$_.FullName | Out-Null
}

Write-Host 'Restarting Explorer after rollback...'
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe

Write-Host 'Rollback complete.'
Pause
"@

    Set-Content -LiteralPath $rollbackPath -Value $content -Encoding UTF8
    return $rollbackPath
}

$IsAdmin = Test-IsAdmin
if ($EnableStrongRepair -and -not $IsAdmin) {
    throw 'EnableStrongRepair requires an elevated PowerShell session.'
}

if (-not $IsAdmin) {
    Write-Host 'Not running elevated. Safe reset and reporting will continue; strong repair remains disabled.'
    $EnableStrongRepair = $false
}

$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
    $desktop = [Environment]::GetFolderPath('MyDocuments')
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $desktop "PreviewPaneRepair-$timestamp"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

Write-Section 'Phase 1 - Backup and diagnosis before changes'
Write-Host "Backup folder: $backupRoot"

$exportPaths = @(
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PreviewHandlers',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\PreviewHandlers',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Modules\GlobalSettings\Sizer'
)

foreach ($extension in $VideoExtensions) {
    $exportPaths += "HKCR\$extension"
    $exportPaths += "HKCR\SystemFileAssociations\$extension"
}

foreach ($registryPath in $exportPaths) {
    $safeName = ($registryPath -replace '[\\/:*?"<>| ]', '_').Trim('_')
    $destination = Join-Path $backupRoot "$safeName.reg"
    [void](Invoke-RegExport -RegistryPath $registryPath -DestinationPath $destination)
}

$advancedRoot = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Default)
$advancedKey = $advancedRoot.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', $true)
$advancedStateBefore = [pscustomobject]@{
    ShowPreviewHandlers = if ($advancedKey) { $advancedKey.GetValue('ShowPreviewHandlers', $null) } else { $null }
    NavPaneShowAllFolders = if ($advancedKey) { $advancedKey.GetValue('NavPaneShowAllFolders', $null) } else { $null }
    SeparateProcess = if ($advancedKey) { $advancedKey.GetValue('SeparateProcess', $null) } else { $null }
    HideFileExt = if ($advancedKey) { $advancedKey.GetValue('HideFileExt', $null) } else { $null }
}

$previewHandlersBefore = @(Get-PreviewHandlersReport)
$associationsBefore = foreach ($extension in $VideoExtensions) { Get-AssociationReport -Extension $extension }
$suspiciousHitsBefore = @(
    $previewHandlersBefore | Where-Object { $_.MatchedTerms }
    foreach ($association in $associationsBefore) {
        if ($association.PreviewHandlerName -and ($association.PreviewHandlerName -match 'MPC-HC|MPC-BE|Media Player Classic|Icaros|K-Lite|LAV|Microsoft|Windows Media Player')) {
            [pscustomobject]@{
                Scope = 'Association'
                Extension = $association.Extension
                MatchedTerms = $association.PreviewHandlerName
                Details = $association.PreviewHandlerInprocServer32
            }
        }
        foreach ($shellHit in @($association.ShellMatches)) {
            [pscustomobject]@{
                Scope = 'Shell'
                Extension = $shellHit.Extension
                MatchedTerms = $shellHit.MatchedTerm
                Details = $shellHit.Details
            }
        }
    }
)

$reportBefore = Format-Report -PreviewHandlers $previewHandlersBefore -Associations $associationsBefore -SuspiciousHits $suspiciousHitsBefore -AdvancedState $advancedStateBefore -Heading 'Before repair'
Write-Host $reportBefore

Write-Section 'Phase 2 - Safe reset'
Write-Host 'Backing up and re-enabling Explorer preview handlers.'
Invoke-RegAddDword -RegistryPath 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -ValueName 'ShowPreviewHandlers' -Value 1

if (Test-Path -LiteralPath $SizerPath) {
    Write-Host 'Removing preview pane sizing cache state from Sizer.'
    try {
        Remove-ItemProperty -LiteralPath $SizerPath -Name 'DetailsContainerSizer' -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $SizerPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Host "Sizer reset warning: $($_.Exception.Message)"
    }
}
else {
    Write-Host 'Sizer cache key not present; skipping.'
}

if ($EnableStrongRepair) {
    Write-Section 'Phase 3 - Optional stronger repair'
    Write-Host 'Strong repair is enabled. Removing only suspicious preview-handler associations.'

    foreach ($association in $associationsBefore) {
        $handlerText = @(
            $association.PreviewHandlerClsid
            $association.PreviewHandlerName
            $association.PreviewHandlerInprocServer32
        ) -join ' '

        $isMicrosoftHandler = $handlerText -match 'Microsoft|Windows Media Player'
        $isSuspiciousHandler = $handlerText -match 'MPC-HC|MPC-BE|Media Player Classic|Icaros|K-Lite|LAV|PotPlayer|Daum|VLC|Monaco|PowerToys'
        $isMissingHandler = [string]::IsNullOrWhiteSpace($association.PreviewHandlerClsid) -or ($association.PreviewHandlerName -eq $null -and $association.PreviewHandlerInprocServer32 -eq $null)

        if ($isMicrosoftHandler -and -not $isSuspiciousHandler) {
            Write-Host "Keeping Microsoft/default preview handler for $($association.Extension)."
            continue
        }

        if ($isSuspiciousHandler -or $isMissingHandler) {
            foreach ($candidatePath in @(
                "HKCR\$($association.Extension)\ShellEx\$PreviewHandlerKey",
                "HKCR\SystemFileAssociations\$($association.Extension)\ShellEx\$PreviewHandlerKey"
            )) {
                $subKey = $candidatePath -replace '^HKCR\\', ''
                if (Open-ClassesRootKey -SubKey $subKey) {
                    Write-Host "Removing preview-handler association: $candidatePath"
                    Invoke-RegDeleteKey -RegistryPath $candidatePath
                }
            }
        }
        else {
            Write-Host "Leaving $($association.Extension) unchanged."
        }
    }
}
else {
    Write-Section 'Phase 3 - Optional stronger repair'
    Write-Host 'Strong repair is disabled. No preview-handler associations were removed.'
}

Write-Section 'Restart Explorer'
Write-Host 'Stopping Explorer and starting it again to flush preview-pane state.'
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe | Out-Null

$advancedKeyAfter = $advancedRoot.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', $false)
$advancedStateAfter = [pscustomobject]@{
    ShowPreviewHandlers = if ($advancedKeyAfter) { $advancedKeyAfter.GetValue('ShowPreviewHandlers', $null) } else { $null }
    NavPaneShowAllFolders = if ($advancedKeyAfter) { $advancedKeyAfter.GetValue('NavPaneShowAllFolders', $null) } else { $null }
    SeparateProcess = if ($advancedKeyAfter) { $advancedKeyAfter.GetValue('SeparateProcess', $null) } else { $null }
    HideFileExt = if ($advancedKeyAfter) { $advancedKeyAfter.GetValue('HideFileExt', $null) } else { $null }
}

$previewHandlersAfter = @(Get-PreviewHandlersReport)
$associationsAfter = foreach ($extension in $VideoExtensions) { Get-AssociationReport -Extension $extension }
$suspiciousHitsAfter = @(
    $previewHandlersAfter | Where-Object { $_.MatchedTerms }
    foreach ($association in $associationsAfter) {
        if ($association.PreviewHandlerName -and ($association.PreviewHandlerName -match 'MPC-HC|MPC-BE|Media Player Classic|Icaros|K-Lite|LAV|Microsoft|Windows Media Player')) {
            [pscustomobject]@{
                Scope = 'Association'
                Extension = $association.Extension
                MatchedTerms = $association.PreviewHandlerName
                Details = $association.PreviewHandlerInprocServer32
            }
        }
        foreach ($shellHit in @($association.ShellMatches)) {
            [pscustomobject]@{
                Scope = 'Shell'
                Extension = $shellHit.Extension
                MatchedTerms = $shellHit.MatchedTerm
                Details = $shellHit.Details
            }
        }
    }
)

$reportAfter = Format-Report -PreviewHandlers $previewHandlersAfter -Associations $associationsAfter -SuspiciousHits $suspiciousHitsAfter -AdvancedState $advancedStateAfter -Heading 'After repair'

$reportPath = Join-Path $backupRoot 'preview-pane-repair-report.txt'
Save-ReportFile -Path $reportPath -Content ($reportBefore + "`r`n`r`n" + $reportAfter)

$rollbackPath = New-RollbackScript -BackupRoot $backupRoot

Write-Section 'Before / after summary'
Write-Host "Report saved to: $reportPath"
Write-Host "Rollback script: $rollbackPath"
Write-Host ''
Write-Host 'Rollback command:'
Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File `"$rollbackPath`""
Write-Host ''
Write-Host 'After repair snapshot:'
Write-Host $reportAfter

Write-Host ''
Write-Host 'Done. Press any key to exit.'
Pause