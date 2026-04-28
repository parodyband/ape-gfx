param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\shaderc_tests"
$ShaderPath = Join-Path $TestDir "invalid_vertex_layout.slang"
$PackagePath = Join-Path $TestDir "invalid_vertex_layout.ashader"
$GeneratedPath = Join-Path $TestDir "invalid_vertex_layout_bindings.odin"
$ShadercPath = Join-Path $TestDir "ape_shaderc-invalid-vertex-layout.exe"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $ShaderPath -Value @'
struct VS_Input
{
	uint id : COLOR0;
};

struct VS_Output
{
	float4 position : SV_Position;
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(float(input.id), 0.0, 0.0, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return float4(1.0, 0.0, 1.0, 1.0);
}
'@

try {
	Invoke-Native -Command "odin" -Arguments @("build", (Join-Path $Root.Path "tools\ape_shaderc"), "-out:$ShadercPath")

	$previousErrorActionPreference = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	$output = & $ShadercPath `
		"-shader-name" "invalid_vertex_layout" `
		"-source" $ShaderPath `
		"-build-dir" $TestDir `
		"-package" $PackagePath `
		"-generated" $GeneratedPath 2>&1
	$exitCode = $LASTEXITCODE
	$ErrorActionPreference = $previousErrorActionPreference
	$outputText = $output | Out-String

	if ($exitCode -eq 0) {
		throw "ape_shaderc unexpectedly accepted invalid vertex input layout"
	}
	if ($outputText -notmatch "unsupported vertex input type") {
		Write-Host $outputText
		throw "ape_shaderc failed for the wrong reason"
	}

	Write-Host "Invalid vertex layout shader failed as expected"
}
finally {
	Remove-Item -LiteralPath $ShadercPath -ErrorAction SilentlyContinue
}
