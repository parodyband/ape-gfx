param(
	[string]$OutName = "d3d11_depth_render_to_texture.exe"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildDir = Join-Path $Root.Path "build"
$SampleDir = Join-Path $Root.Path "samples\d3d11_depth_render_to_texture"
$OutPath = Join-Path $BuildDir $OutName

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

& (Join-Path $PSScriptRoot "compile_shaders.ps1") -ShaderName "cube"
& (Join-Path $PSScriptRoot "compile_shaders.ps1") -ShaderName "depth_visualize"
Invoke-Native -Command "odin" -Arguments @("build", $SampleDir, "-collection:ape=$($Root.Path)", "-out:$OutPath")
