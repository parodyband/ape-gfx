param(
	[string]$OutName = "d3d11_cube.exe"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildDir = Join-Path $Root.Path "build"
$SampleDir = Join-Path $Root.Path "samples\d3d11_cube"
$OutPath = Join-Path $BuildDir $OutName

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

& (Join-Path $PSScriptRoot "compile_shaders.ps1") -ShaderName "cube"
Invoke-Native -Command "odin" -Arguments @("build", $SampleDir, "-collection:ape=$($Root.Path)", "-out:$OutPath")
