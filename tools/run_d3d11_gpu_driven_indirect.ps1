param(
	[int]$AutoExitFrames = 0
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildDir = Join-Path $Root.Path "build"
$SampleDir = Join-Path $Root.Path "samples\d3d11_gpu_driven_indirect"
$OutPath = Join-Path $BuildDir "d3d11_gpu_driven_indirect.exe"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

& (Join-Path $PSScriptRoot "compile_shaders.ps1") -ShaderName "triangle"
& (Join-Path $PSScriptRoot "compile_shaders.ps1") -ShaderName "gpu_driven_indirect_args" -Kind "compute"

$define = "-define:AUTO_EXIT_FRAMES=$AutoExitFrames"
Invoke-Native -Command "odin" -Arguments @("run", $SampleDir, "-collection:ape=$($Root.Path)", "-out:$OutPath", $define)
