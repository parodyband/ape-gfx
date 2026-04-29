param(
	[int]$AutoExitFrames = 5,
	[switch]$SkipShaderCompile,
	[switch]$SkipD3D11Builds,
	[switch]$SkipD3D11Runs,
	[switch]$SkipGitDiffCheck
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ToolDir = Join-Path $Root.Path "build\tools"
$ApePath = Join-Path $ToolDir "ape.exe"

New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null

Invoke-Native -Command "odin" -Arguments @("build", (Join-Path $Root.Path "tools\ape"), "-out:$ApePath")

$ApeArguments = @(
	"validate", "full",
	"-root", $Root.Path,
	"-auto-exit-frames", $AutoExitFrames
)
if ($SkipShaderCompile) {
	$ApeArguments += "-skip-shader-compile"
}
if ($SkipD3D11Builds) {
	$ApeArguments += "-skip-d3d11-builds"
}
if ($SkipD3D11Runs) {
	$ApeArguments += "-skip-d3d11-runs"
}
if ($SkipGitDiffCheck) {
	$ApeArguments += "-skip-git-diff-check"
}

Invoke-Native -Command $ApePath -Arguments $ApeArguments
