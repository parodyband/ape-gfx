param(
	[int]$AutoExitFrames = 0
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildDir = Join-Path $Root.Path "build"
$SampleDir = Join-Path $Root.Path "samples\d3d11_transient_uniforms"
$OutPath = Join-Path $BuildDir "d3d11_transient_uniforms.exe"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$define = "-define:AUTO_EXIT_FRAMES=$AutoExitFrames"
Invoke-Native -Command "odin" -Arguments @("run", $SampleDir, "-collection:ape=$($Root.Path)", "-out:$OutPath", $define)
