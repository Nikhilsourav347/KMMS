$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logo = [Drawing.Image]::FromFile((Join-Path $repo 'assets/images/company_logo.jpg'))

function Get-LogoPng([int]$size) {
    $bitmap = [Drawing.Bitmap]::new($size, $size, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $stream = [IO.MemoryStream]::new()
    try {
        $graphics.Clear([Drawing.Color]::White)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $scale = [Math]::Min($size / $logo.Width, $size / $logo.Height)
        $w = [single]($logo.Width * $scale)
        $h = [single]($logo.Height * $scale)
        $graphics.DrawImage($logo, [Drawing.RectangleF]::new(($size - $w) / 2, ($size - $h) / 2, $w, $h))
        $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    } finally {
        $stream.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Write-LogoPng([string]$path, [int]$size) {
    $target = Join-Path $repo $path
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    [IO.File]::WriteAllBytes($target, (Get-LogoPng $size))
}

try {
    $density = @{mdpi=48; hdpi=72; xhdpi=96; xxhdpi=144; xxxhdpi=192}
    foreach ($item in $density.GetEnumerator()) {
        Write-LogoPng "android/app/src/main/res/mipmap-$($item.Key)/ic_launcher.png" $item.Value
        Write-LogoPng "android/app/src/main/res/drawable-$($item.Key)/launch_logo.png" (2 * $item.Value)
    }

    $ios = 'ios/Runner/Assets.xcassets'
    $icons = Get-Content -Raw (Join-Path $repo "$ios/AppIcon.appiconset/Contents.json") | ConvertFrom-Json
    foreach ($icon in $icons.images) {
        $size = [double]::Parse(($icon.size -split 'x')[0], [Globalization.CultureInfo]::InvariantCulture)
        $scale = [int]$icon.scale.TrimEnd('x')
        Write-LogoPng "$ios/AppIcon.appiconset/$($icon.filename)" ([int]($size * $scale))
    }
    Write-LogoPng "$ios/LaunchImage.imageset/LaunchImage.png" 96
    Write-LogoPng "$ios/LaunchImage.imageset/LaunchImage@2x.png" 192
    Write-LogoPng "$ios/LaunchImage.imageset/LaunchImage@3x.png" 288

    Write-LogoPng 'web/favicon.png' 48
    foreach ($size in @(192, 512)) {
        Write-LogoPng "web/icons/Icon-$size.png" $size
        Write-LogoPng "web/icons/Icon-maskable-$size.png" $size
    }

    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $frames = @()
    foreach ($size in $sizes) { $frames += ,(Get-LogoPng $size) }
    $target = Join-Path $repo 'windows/runner/resources/app_icon.ico'
    $writer = [IO.BinaryWriter]::new([IO.File]::Create($target))
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $dimension = [byte]($sizes[$i] % 256)
            $writer.Write($dimension)
            $writer.Write($dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]24)
            $writer.Write([uint32]$frames[$i].Length)
            $writer.Write([uint32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
    } finally {
        $writer.Dispose()
    }
} finally {
    $logo.Dispose()
}
