param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\shaderc_tests"
$ShadercPath = Join-Path $TestDir "ape_shaderc-modern-api-probe.exe"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Invoke-Native -Command "odin" -Arguments @("build", (Join-Path $Root.Path "tools\ape_shaderc"), "-out:$ShadercPath")
Invoke-Native -Command $ShadercPath -Arguments @("-probe-modern-api")

Write-Host "Shaderc modern Slang API probe passed"
