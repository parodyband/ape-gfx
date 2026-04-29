param(
	[switch]$SkipShaderCompile,
	[switch]$SkipGitDiffCheck
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ToolDir = Join-Path $Root.Path "build\tools"
$ApePath = Join-Path $ToolDir "ape.exe"

New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null

Invoke-Native -Command "odin" -Arguments @("build", (Join-Path $Root.Path "tools\ape"), "-out:$ApePath")

$ApeArguments = @("validate", "core", "-root", $Root.Path)
if ($SkipShaderCompile) {
	$ApeArguments += "-skip-shader-compile"
}
if ($SkipGitDiffCheck) {
	$ApeArguments += "-skip-git-diff-check"
}

Invoke-Native -Command $ApePath -Arguments $ApeArguments
