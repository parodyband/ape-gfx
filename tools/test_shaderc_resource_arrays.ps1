param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\shaderc_resource_arrays"
$ShadercPath = Join-Path $TestDir "ape_shaderc.exe"

function Invoke-ShadercExpectFailure {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[string]$Source,

		[Parameter(Mandatory = $true)]
		[string]$ExpectedPattern
	)

	$SourcePath = Join-Path $TestDir "$Name.slang"
	$PackagePath = Join-Path $TestDir "$Name.ashader"
	$GeneratedPath = Join-Path $TestDir "$($Name)_bindings.odin"
	Set-Content -LiteralPath $SourcePath -Value $Source

	$previousErrorActionPreference = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	try {
		$output = & $ShadercPath `
			"-shader-name" $Name `
			"-source" $SourcePath `
			"-build-dir" $TestDir `
			"-package" $PackagePath `
			"-generated" $GeneratedPath 2>&1
		$exitCode = $LASTEXITCODE
	}
	finally {
		$ErrorActionPreference = $previousErrorActionPreference
	}
	$outputText = $output | Out-String

	if ($exitCode -eq 0) {
		throw "ape_shaderc unexpectedly accepted $Name"
	}
	if ($outputText -notmatch $ExpectedPattern) {
		Write-Host $outputText
		throw "ape_shaderc failed $Name for the wrong reason"
	}
}

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Invoke-Native -Command "odin" -Arguments @(
	"build",
	(Join-Path $Root.Path "tools\ape_shaderc"),
	"-out:$ShadercPath"
)

Invoke-ShadercExpectFailure `
	-Name "global_texture_array" `
	-ExpectedPattern "resource arrays are not supported yet" `
	-Source @'
struct VS_Input
{
	float3 position : POSITION;
	float2 uv : TEXCOORD;
};

struct VS_Output
{
	float4 position : SV_Position;
	float2 uv : TEXCOORD;
};

Texture2D<float4> textures[2];
SamplerState sampler;

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	output.uv = input.uv;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return textures[0].Sample(sampler, input.uv);
}
'@

Invoke-ShadercExpectFailure `
	-Name "global_sampler_array" `
	-ExpectedPattern "resource arrays are not supported yet" `
	-Source @'
struct VS_Input
{
	float3 position : POSITION;
	float2 uv : TEXCOORD;
};

struct VS_Output
{
	float4 position : SV_Position;
	float2 uv : TEXCOORD;
};

Texture2D<float4> texture;
SamplerState samplers[2];

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	output.uv = input.uv;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return texture.Sample(samplers[0], input.uv);
}
'@

Write-Host "Shaderc resource-array rejection test passed"
