param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\shaderc_tests\modern_component_compile"
$ShadercPath = Join-Path $TestDir "ape_shaderc-modern-component-compile.exe"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Invoke-Native -Command "odin" -Arguments @("build", (Join-Path $Root.Path "tools\ape_shaderc"), "-out:$ShadercPath")
Invoke-Native -Command $ShadercPath -Arguments @(
	"-compare-modern-compile",
	"-shader-name", "triangle",
	"-build-dir", $TestDir
)

Write-Host "Shaderc modern Slang component compile comparison passed"
