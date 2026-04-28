param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\shaderc_storage_resource_metadata"
$ShadercPath = Join-Path $TestDir "ape_shaderc.exe"
$SourcePath = Join-Path $TestDir "storage_metadata.slang"
$StructuredSourcePath = Join-Path $TestDir "structured_storage_metadata.slang"
$InvalidSourcePath = Join-Path $TestDir "invalid_storage_image_format.slang"
$PackagePath = Join-Path $TestDir "storage_metadata.ashader"
$StructuredPackagePath = Join-Path $TestDir "structured_storage_metadata.ashader"
$InvalidPackagePath = Join-Path $TestDir "invalid_storage_image_format.ashader"
$GeneratedPath = Join-Path $TestDir "bindings.odin"
$StructuredGeneratedPath = Join-Path $TestDir "structured_bindings.odin"
$InvalidGeneratedPath = Join-Path $TestDir "invalid_storage_image_format_bindings.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $SourcePath -Value @'
struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

RWTexture2D<float4> output_image : register(u1);
RWByteAddressBuffer output_buffer : register(u2);

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	output_image[uint2(0, 0)] = float4(1.0, 0.0, 0.0, 1.0);
	output_buffer.Store(0, 7);
	return float4(0.0, 0.0, 0.0, 1.0);
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"build",
	(Join-Path $Root.Path "tools\ape_shaderc"),
	"-out:$ShadercPath"
)

Invoke-Native -Command $ShadercPath -Arguments @(
	"-shader-name", "storage_metadata",
	"-source", $SourcePath,
	"-build-dir", $TestDir,
	"-package", $PackagePath,
	"-generated", $GeneratedPath
)

$Generated = Get-Content -LiteralPath $GeneratedPath -Raw
$ExpectedSnippets = @(
	"VIEW_KIND_output_image :: gfx.View_Kind.Storage_Image",
	"VIEW_ACCESS_output_image :: gfx.Shader_Resource_Access.Read_Write",
	"VIEW_FORMAT_output_image :: gfx.Pixel_Format.RGBA32F",
	"VIEW_KIND_output_buffer :: gfx.View_Kind.Storage_Buffer",
	"VIEW_ACCESS_output_buffer :: gfx.Shader_Resource_Access.Read_Write",
	"VIEW_STRIDE_output_buffer :: 0"
)

foreach ($Snippet in $ExpectedSnippets) {
	if (-not $Generated.Contains($Snippet)) {
		Write-Error "Missing generated storage metadata: $Snippet"
	}
}

Set-Content -LiteralPath $StructuredSourcePath -Value @'
struct Item
{
	float4 value;
	uint id;
};

RWStructuredBuffer<Item> output_items : register(u0);

[shader("compute")]
[numthreads(1, 1, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	Item item;
	item.value = float4(1.0, 0.0, 0.0, 1.0);
	item.id = 7;
	output_items[0] = item;
}
'@

Invoke-Native -Command $ShadercPath -Arguments @(
	"-shader-name", "structured_storage_metadata",
	"-kind", "compute",
	"-source", $StructuredSourcePath,
	"-build-dir", $TestDir,
	"-package", $StructuredPackagePath,
	"-generated", $StructuredGeneratedPath
)

$StructuredGenerated = Get-Content -LiteralPath $StructuredGeneratedPath -Raw
$StructuredExpectedSnippets = @(
	"VIEW_KIND_output_items :: gfx.View_Kind.Storage_Buffer",
	"VIEW_ACCESS_output_items :: gfx.Shader_Resource_Access.Read_Write",
	"VIEW_STRIDE_output_items :: 20"
)

foreach ($Snippet in $StructuredExpectedSnippets) {
	if (-not $StructuredGenerated.Contains($Snippet)) {
		Write-Error "Missing generated structured storage metadata: $Snippet"
	}
}

Set-Content -LiteralPath $InvalidSourcePath -Value @'
RWTexture2D<float2> bad_output : register(u0);

[shader("compute")]
[numthreads(1, 1, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	bad_output[dispatch_id.xy] = float2(1.0, 0.0);
}
'@

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$output = & $ShadercPath `
	"-shader-name" "invalid_storage_image_format" `
	"-kind" "compute" `
	"-source" $InvalidSourcePath `
	"-build-dir" $TestDir `
	"-package" $InvalidPackagePath `
	"-generated" $InvalidGeneratedPath 2>&1
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
$outputText = $output | Out-String

if ($exitCode -eq 0) {
	throw "ape_shaderc unexpectedly accepted unsupported storage image format"
}
if ($outputText -notmatch "unsupported storage image result type") {
	Write-Host $outputText
	throw "ape_shaderc failed invalid storage image format for the wrong reason"
}

Write-Host "Shaderc storage resource metadata test passed"
