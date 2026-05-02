$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ElectronDir = Join-Path $RepoRoot "electron"
if (-not (Test-Path $ElectronDir)) {
    New-Item -ItemType Directory -Force -Path $ElectronDir | Out-Null
}

$IconPngPath = Join-Path $ElectronDir "icon.png"
$IconIcoPath = Join-Path $ElectronDir "icon.ico"

# Ensure we have System.Drawing for robust conversion
Add-Type -AssemblyName System.Drawing

function Convert-To-ValidPng {
    param([string]$SourcePath, [string]$DestPath)
    $img = [System.Drawing.Image]::FromFile($SourcePath)
    try {
        # Create a new bitmap to ensure we lose any weird metadata/formats
        $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.DrawImage($img, 0, 0, $img.Width, $img.Height)
        $g.Dispose()
        $bmp.Save($DestPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    } finally {
        $img.Dispose()
    }
}

function Write-IcoFromPng {
    param(
        [string]$PngPath,
        [string]$IcoPath
    )

    $PngBytes = [IO.File]::ReadAllBytes($PngPath)
    $img = [System.Drawing.Image]::FromFile($PngPath)
    $w = $img.Width
    $h = $img.Height
    $img.Dispose()

    # ICO limits: if > 256, use 0 in header
    $headerW = if ($w -ge 256) { 0 } else { $w }
    $headerH = if ($h -ge 256) { 0 } else { $h }

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    try {
        $bw.Write([UInt16]0) # Reserved
        $bw.Write([UInt16]1) # Type (1 = Icon)
        $bw.Write([UInt16]1) # Count
        
        $bw.Write([byte]$headerW)
        $bw.Write([byte]$headerH)
        $bw.Write([byte]0) # Colors
        $bw.Write([byte]0) # Reserved
        $bw.Write([UInt16]1) # Planes
        $bw.Write([UInt16]32) # BitCount
        $bw.Write([UInt32]$PngBytes.Length)
        $bw.Write([UInt32]22) # Offset (6 header + 16 entry)
        
        $bw.Write($PngBytes)
        $bw.Flush()
        [IO.File]::WriteAllBytes($IcoPath, $ms.ToArray())
    } finally {
        $bw.Dispose()
        $ms.Dispose()
    }
}

# 1. Fix the PNG if it's actually a JPEG or malformed
if (Test-Path $IconPngPath) {
    $bytes = [IO.File]::ReadAllBytes($IconPngPath)
    if ($bytes[0] -ne 0x89 -or $bytes[1] -ne 0x50) {
        Write-Host "Detected non-PNG signature. Converting to valid PNG..."
        $tempPath = "$IconPngPath.tmp"
        Move-Item $IconPngPath $tempPath
        Convert-To-ValidPng -SourcePath $tempPath -DestPath $IconPngPath
        Remove-Item $tempPath
    }
} else {
    # Fallback to embedded base64 if missing (unlikely in this repo state)
    Write-Error "Missing icon.png in electron directory."
}

# 2. Generate the ICO from the valid PNG
Write-Host "Generating valid Windows ICO from $IconPngPath..."
Write-IcoFromPng -PngPath $IconPngPath -IcoPath $IconIcoPath
Write-Host "Done. icon.ico is now a valid Windows Icon container."

