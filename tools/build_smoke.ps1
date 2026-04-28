param(
	[string]$OutName = "smoke.exe"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildDir = Join-Path $Root.Path "build"
$SampleDir = Join-Path $Root.Path "samples\smoke"
$OutPath = Join-Path $BuildDir $OutName

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

Invoke-Native -Command "odin" -Arguments @("run", $SampleDir, "-collection:ape=$($Root.Path)", "-out:$OutPath")
