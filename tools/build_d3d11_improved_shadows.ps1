param(
	[string]$OutName = "d3d11_improved_shadows.exe"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildDir = Join-Path $Root.Path "build"
$SampleDir = Join-Path $Root.Path "samples\d3d11_improved_shadows"
$OutPath = Join-Path $BuildDir $OutName
$TextureSource = Join-Path $Root.Path "assets\textures\texture.jpg"
$TextureOutput = Join-Path $BuildDir "textures\texture.aptex"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

& (Join-Path $PSScriptRoot "compile_shaders.ps1") -ShaderName "shadow_depth"
& (Join-Path $PSScriptRoot "compile_shaders.ps1") -ShaderName "improved_shadows"
& (Join-Path $PSScriptRoot "convert_texture_rgba8.ps1") -InputPath $TextureSource -OutputPath $TextureOutput
Invoke-Native -Command "odin" -Arguments @("build", $SampleDir, "-collection:ape=$($Root.Path)", "-out:$OutPath")
