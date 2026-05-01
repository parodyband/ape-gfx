param(
	[string]$OutName = "ape_shader_library_test.exe"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildDir = Join-Path $Root.Path "build"
$TestDir = Join-Path $Root.Path "tools\ape_shader_library_test"
$OutPath = Join-Path $BuildDir $OutName

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

Invoke-Native -Command "odin" -Arguments @("build", $TestDir, "-collection:ape=$($Root.Path)", "-out:$OutPath")
Invoke-Native -Command $OutPath
