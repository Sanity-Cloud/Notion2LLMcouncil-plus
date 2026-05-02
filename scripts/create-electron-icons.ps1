$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ElectronDir = Join-Path $RepoRoot "electron"
New-Item -ItemType Directory -Force -Path $ElectronDir | Out-Null

# 32x32 PNG tray icon. Electron uses this for the Windows notification area near the clock.
$IconPngBase64 = @'
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAACJklEQVR4nOVXO27CQBQcotTbUKR0lVP4CIgejMQJKHwBVz5AXHACJJz0KEfwKagoU6TZCzgFfsvb9duPA1KKjISEvd6d8fsb+O+Y/WbTqu1739pHMZt0ZvLDIdJ7xCQJ6N/W/fqlNdefuwy6ygEAqu6sZxf7yyQRwcVV2/fvX4W55mQ+AbSm6s4S4xPyFCIHAP7mKSBhusrxuctG5yUJ4A/zQ+jwFJBlYiK8FuCbJdOjbIGyhf6+WL/QORJGfiG/+3xryANQc5vQjQkeD5YFuIl0lcsm5+RNATXProTNLVi5JaSY4DyiC1TdGQtYQgbyESGtD4JIBM8UyaIA8CzeZUKMiOGtiEDVHZaHC5YHYAPgeGZua+TUlWB8QWbxBQwXsDzIwYZBSIyYx0IwCyTyFMTemmPkglCu6yrH5jWcAdf1NKGigEcgVrDWIQFi/pf3SvJjsgWO5yLohtM2A4bC48Nif/sfDUJd5be0KttogPHCkwIjgMojb6G+Q47nwqQb4bTNTC0Qi9gAtxxbvYBqgXcGoBLbFBbJCFSuhYLkChBjQNWdaSDW/Xl2FVG20KVdF1TdWT2Ar3FL8AwAPN0QCFTEKo92Q24hvo+GG2835IvubGfIEamIg9ld10jkogAOSQS9mdWGWVuWskQ6JyiAq6TNU8Yxgq7y6GDqtYArItTTXdBzfKD1TcVJ3wXuMCkNqm6axYgnCZBEpOBhX0ZTxEz9Nvxz/ADa/jp/mIi68QAAAABJRU5ErkJggg==
'@

function Write-IcoFromPngBytes {
    param(
        [byte[]]$PngBytes,
        [string]$Path,
        [int]$Width = 32,
        [int]$Height = 32
    )

    # ICO container with PNG image payload:
    # ICONDIR: reserved=0, type=1, count=1
    # ICONDIRENTRY: width, height, colors, reserved, planes, bitcount, bytes, offset
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    try {
        $bw.Write([UInt16]0)
        $bw.Write([UInt16]1)
        $bw.Write([UInt16]1)
        $bw.Write([byte]$Width)
        $bw.Write([byte]$Height)
        $bw.Write([byte]0)
        $bw.Write([byte]0)
        $bw.Write([UInt16]1)
        $bw.Write([UInt16]32)
        $bw.Write([UInt32]$PngBytes.Length)
        $bw.Write([UInt32]22)
        $bw.Write($PngBytes)
        $bw.Flush()
        [IO.File]::WriteAllBytes($Path, $ms.ToArray())
    } finally {
        $bw.Dispose()
        $ms.Dispose()
    }
}

$IconPngPath = Join-Path $ElectronDir "icon.png"
$IconIcoPath = Join-Path $ElectronDir "icon.ico"

if (-not (Test-Path $IconPngPath)) {
    $pngBytes = [Convert]::FromBase64String($IconPngBase64.Trim())
    [IO.File]::WriteAllBytes($IconPngPath, $pngBytes)
    Write-Host "Wrote tray icon: $IconPngPath"
} else {
    Write-Host "Using existing icon: $IconPngPath"
}

if (-not (Test-Path $IconIcoPath)) {
    Write-IcoFromPngBytes -PngBytes ([IO.File]::ReadAllBytes($IconPngPath)) -Path $IconIcoPath -Width 32 -Height 32
    Write-Host "Wrote valid Windows icon: $IconIcoPath"
} else {
    Write-Host "Using existing ICO: $IconIcoPath"
}
