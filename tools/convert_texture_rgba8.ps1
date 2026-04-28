param(
	[string]$InputPath = (Join-Path $PSScriptRoot "..\assets\textures\texture.jpg"),
	[string]$OutputPath = (Join-Path $PSScriptRoot "..\build\textures\texture.aptex")
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$InputFull = Resolve-Path $InputPath
$OutputFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$OutputDir = Split-Path -Parent $OutputFull

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$Bitmap = [System.Drawing.Bitmap]::new($InputFull.Path)
$Width = $Bitmap.Width
$Height = $Bitmap.Height
try {
	$Stream = [System.IO.File]::Open($OutputFull, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
	$Writer = [System.IO.BinaryWriter]::new($Stream)
	try {
		$Writer.Write([uint32]0x58545041) # "APTX"
		$Writer.Write([uint32]1)
		$Writer.Write([uint32]$Width)
		$Writer.Write([uint32]$Height)

		for ($Y = 0; $Y -lt $Height; $Y++) {
			for ($X = 0; $X -lt $Width; $X++) {
				$Pixel = $Bitmap.GetPixel($X, $Y)
				$Writer.Write([byte]$Pixel.R)
				$Writer.Write([byte]$Pixel.G)
				$Writer.Write([byte]$Pixel.B)
				$Writer.Write([byte]$Pixel.A)
			}
		}
	}
	finally {
		$Writer.Dispose()
	}
}
finally {
	$Bitmap.Dispose()
}

Write-Host "Converted $($InputFull.Path) to $OutputFull ($($Width)x$($Height) RGBA8)"
