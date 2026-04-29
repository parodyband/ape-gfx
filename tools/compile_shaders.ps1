param(
	[string]$ShaderName = "triangle",
	[ValidateSet("graphics", "compute")]
	[string]$Kind = "graphics",
	[string]$SourcePath = "",
	[switch]$All
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildDir = Join-Path $Root.Path "build\shaders"
$ToolDir = Join-Path $Root.Path "build\tools"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null

$ApePath = Join-Path $ToolDir "ape-shader-compile-$PID.exe"

try {
	Invoke-Native -Command "odin" -Arguments @("build", (Join-Path $Root.Path "tools\ape"), "-out:$ApePath")

	$ApeArguments = @(
		"shader", "compile",
		"-root", $Root.Path,
		"-build-dir", $BuildDir
	)

	if ($All) {
		$ApeArguments += "-all"
	}
	else {
		$ApeArguments += @(
			"-shader-name", $ShaderName,
			"-kind", $Kind
		)

		if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
			$ApeArguments += @("-source", $SourcePath)
		}
	}

	Invoke-Native -Command $ApePath -Arguments $ApeArguments
}
finally {
	Remove-Item -LiteralPath $ApePath -ErrorAction SilentlyContinue
}
