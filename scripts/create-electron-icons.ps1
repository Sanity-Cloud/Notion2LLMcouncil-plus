$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ElectronDir = Join-Path $RepoRoot "electron"
New-Item -ItemType Directory -Force -Path $ElectronDir | Out-Null

# 32x32 PNG tray icon. Electron uses this for the Windows notification area near the clock.
$IconPngBase64 = @'
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAACJklEQVR4nOVXO27CQBQcotTbUKR0lVP4CIgejMQJKHwBVz5AXHACJJz0KEfwKagoU6TZCzgFfsvb9duPA1KKjISEvd6d8fsb+O+Y/WbTqu1739pHMZt0ZvLDIdJ7xCQJ6N/W/fqlNdefuwy6ygEAqu6sZxf7yyQRwcVV2/fvX4W55mQ+AbSm6s4S4xPyFCIHAP7mKSBhusrxuctG5yUJ4A/zQ+jwFJBlYiK8FuCbJdOjbIGyhf6+WL/QORJGfiG/+3xryANQc5vQjQkeD5YFuIl0lcsm5+RNATXProTNLVi5JaSY4DyiC1TdGQtYQgbyESGtD4JIBM8UyaIA8CzeZUKMiOGtiEDVHZaHC5YHYAPgeGZua+TUlWB8QWbxBQwXsDzIwYZBSIyYx0IwCyTyFMTemmPkglCu6yrH5jWcAdf1NKGigEcgVrDWIQFi/pf3SvJjsgWO5yLohtM2A4bC48Nif/sfDUJd5be0KttogPHCkwIjgMojb6G+Q47nwqQb4bTNTC0Qi9gAtxxbvYBqgXcGoBLbFBbJCFSuhYLkChBjQNWdaSDW/Xl2FVG20KVdF1TdWT2Ar3FL8AwAPN0QCFTEKo92Q24hvo+GG2835IvubGfIEamIg9ld10jkogAOSQS9mdWGWVuWskQ6JyiAq6TNU8Yxgq7y6GDqtYArItTTXdBzfKD1TcVJ3wXuMCkNqm6axYgnCZBEpOBhX0ZTxEz9Nvxz/ADa/jp/mIi68QAAAABJRU5ErkJggg==
'@

$IconPngPath = Join-Path $ElectronDir "icon.png"
if (-not (Test-Path $IconPngPath)) {
    [IO.File]::WriteAllBytes($IconPngPath, [Convert]::FromBase64String($IconPngBase64.Trim()))
    Write-Host "Wrote tray icon: $IconPngPath"
} else {
    Write-Host "Using existing icon: $IconPngPath"
}

# Best-effort ICO for the Electron window. This is optional; the tray uses icon.png.
$IconIcoPath = Join-Path $ElectronDir "icon.ico"
if (-not (Test-Path $IconIcoPath)) {
    Copy-Item $IconPngPath $IconIcoPath -Force
    Write-Host "Wrote fallback window icon: $IconIcoPath"
}
