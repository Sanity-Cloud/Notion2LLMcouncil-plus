$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ElectronDir = Join-Path $RepoRoot "electron"
New-Item -ItemType Directory -Force -Path $ElectronDir | Out-Null

$IconPngPath = Join-Path $ElectronDir "icon.png"
$IconIcoPath = Join-Path $ElectronDir "icon.ico"

# 32x32 PNG tray icon. Electron uses this for the Windows notification area near the clock.
$IconPngBase64 = @'
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAACJklEQVR4nOVXO27CQBQcotTbUKR0lVP4CIgejMQJKHwBVz5AXHACJJz0KEfwKagoU6TZCzgFfsvb9duPA1KKjISEvd6d8fsb+O+Y/WbTqu1739pHMZt0ZvLDIdJ7xCQJ6N/W/fqlNdefuwy6ygEAqu6sZxf7yyQRwcVV2/fvX4W55mQ+AbSm6s4S4xPyFCIHAP7mKSBhusrxuctG5yUJ4A/zQ+jwFJBlYiK8FuCbJdOjbIGyhf6+WL/QORJGfiG/+3xryANQc5vQjQkeD5YFuIl0lcsm5+RNATXProTNLVi5JaSY4DyiC1TdGQtYQgbyESGtD4JIBM8UyaIA8CzeZUKMiOGtiEDVHZaHC5YHYAPgeGZua+TUlWB8QWbxBQwXsDzIwYZBSIyYx0IwCyTyFMTemmPkglCu6yrH5jWcAdf1NKGigEcgVrDWIQFi/pf3SvJjsgWO5yLohtM2A4bC48Nif/sfDUJd5be0KttogPHCkwIjgMojb6G+Q47nwqQb4bTNTC0Qi9gAtxxbvYBqgXcGoBLbFBbJCFSuhYLkChBjQNWdaSDW/Xl2FVG20KVdF1TdWT2Ar3FL8AwAPN0QCFTEKo92Q24hvo+GG2835IvubGfIEamIg9ld10jkogAOSQS9mdWGWVuWskQ6JyiAq6TNU8Yxgq7y6GDqtYArItTTXdBzfKD1TcVJ3wXuMCkNqm6axYgnCZBEpOBhX0ZTxEz9Nvxz/ADa/jp/mIi68QAAAABJRU5ErkJggg==
'@

Add-Type -AssemblyName System.Drawing

function New-ResizedBitmap {
    param(
        [System.Drawing.Image]$Source,
        [int]$Size
    )

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.DrawImage($Source, 0, 0, $Size, $Size)
        return $bitmap
    } finally {
        $graphics.Dispose()
    }
}

function Convert-BitmapToIconDibBytes {
    param([System.Drawing.Bitmap]$Bitmap)

    $width = $Bitmap.Width
    $height = $Bitmap.Height
    $xorSize = $width * $height * 4

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    try {
        # BMP/DIB-backed ICO payload. For 32-bit alpha icons, omit a separate AND mask.
        # This matches the DIB shape produced by common icon writers and is accepted by NSIS.
        $bw.Write([UInt32]40)           # BITMAPINFOHEADER.biSize
        $bw.Write([Int32]$width)        # biWidth
        $bw.Write([Int32]($height * 2)) # biHeight = XOR height + AND-mask height
        $bw.Write([UInt16]1)            # biPlanes
        $bw.Write([UInt16]32)           # biBitCount
        $bw.Write([UInt32]0)            # biCompression = BI_RGB
        $bw.Write([UInt32]$xorSize)     # biSizeImage
        $bw.Write([Int32]0)             # biXPelsPerMeter
        $bw.Write([Int32]0)             # biYPelsPerMeter
        $bw.Write([UInt32]0)            # biClrUsed
        $bw.Write([UInt32]0)            # biClrImportant

        # ICO DIB pixel data is bottom-up BGRA.
        for ($y = $height - 1; $y -ge 0; $y--) {
            for ($x = 0; $x -lt $width; $x++) {
                $c = $Bitmap.GetPixel($x, $y)
                $bw.Write([byte]$c.B)
                $bw.Write([byte]$c.G)
                $bw.Write([byte]$c.R)
                $bw.Write([byte]$c.A)
            }
        }

        $bw.Flush()
        return $ms.ToArray()
    } finally {
        $bw.Dispose()
        $ms.Dispose()
    }
}

function Write-WindowsIco {
    param(
        [string]$SourcePng,
        [string]$DestinationIco
    )

    $source = [System.Drawing.Image]::FromFile($SourcePng)
    # Keep the icon conservative for older NSIS/makensis parsers.
    $sizes = @(16, 24, 32, 48)
    $entries = @()

    try {
        foreach ($size in $sizes) {
            $bmp = New-ResizedBitmap -Source $source -Size $size
            try {
                $dib = Convert-BitmapToIconDibBytes -Bitmap $bmp
                $entries += [pscustomobject]@{ Size = $size; Bytes = $dib }
            } finally {
                $bmp.Dispose()
            }
        }
    } finally {
        $source.Dispose()
    }

    $headerSize = 6 + (16 * $entries.Count)
    $offset = $headerSize
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    try {
        $bw.Write([UInt16]0) # reserved
        $bw.Write([UInt16]1) # image type: icon
        $bw.Write([UInt16]$entries.Count)

        foreach ($entry in $entries) {
            $bw.Write([byte]$entry.Size)
            $bw.Write([byte]$entry.Size)
            $bw.Write([byte]0)     # color count
            $bw.Write([byte]0)     # reserved
            $bw.Write([UInt16]1)   # color planes
            $bw.Write([UInt16]32)  # bits per pixel
            $bw.Write([UInt32]$entry.Bytes.Length)
            $bw.Write([UInt32]$offset)
            $offset += $entry.Bytes.Length
        }

        foreach ($entry in $entries) {
            $bw.Write($entry.Bytes)
        }

        $bw.Flush()
        [IO.File]::WriteAllBytes($DestinationIco, $ms.ToArray())
    } finally {
        $bw.Dispose()
        $ms.Dispose()
    }
}

[IO.File]::WriteAllBytes($IconPngPath, [Convert]::FromBase64String($IconPngBase64.Trim()))
Write-Host "Wrote tray PNG: $IconPngPath"

Write-WindowsIco -SourcePng $IconPngPath -DestinationIco $IconIcoPath
Write-Host "Wrote NSIS-readable BMP ICO: $IconIcoPath"
