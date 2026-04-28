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

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$ShadercPath = Join-Path $BuildDir "ape_shaderc-$PID-$ShaderName.exe"
try {
	Invoke-Native -Command "odin" -Arguments @("build", (Join-Path $Root.Path "tools\ape_shaderc"), "-out:$ShadercPath")
	if ($All) {
		Invoke-Native -Command $ShadercPath -Arguments @(
			"-all",
			"-build-dir", $BuildDir
		)
	}
	else {
		if ([string]::IsNullOrWhiteSpace($SourcePath)) {
			$ShaderPath = Join-Path $Root.Path "assets\shaders\$ShaderName.slang"
		}
		else {
			$ShaderPath = $SourcePath
		}

		$PackagePath = Join-Path $BuildDir "$ShaderName.ashader"

		$GeneratedDir = Join-Path $Root.Path "assets\shaders\generated\$ShaderName"
		$GeneratedBindingsPath = Join-Path $GeneratedDir "bindings.odin"
		New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null

		Invoke-Native -Command $ShadercPath -Arguments @(
			"-shader-name", $ShaderName,
			"-kind", $Kind,
			"-source", $ShaderPath,
			"-build-dir", $BuildDir,
			"-package", $PackagePath,
			"-generated", $GeneratedBindingsPath
		)
	}
}
finally {
	Remove-Item -LiteralPath $ShadercPath -ErrorAction SilentlyContinue
}

if ($All) {
	Write-Host "Compiled all sample shader outputs and packages to $BuildDir"
}
else {
	Write-Host "Compiled $ShaderName shader outputs and package to $BuildDir"
}
