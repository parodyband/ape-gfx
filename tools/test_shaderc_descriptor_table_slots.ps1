param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\shaderc_descriptor_table_slots"
$ShadercPath = Join-Path $TestDir "ape_shaderc.exe"
$SourcePath = Join-Path $TestDir "descriptor_table_slots.slang"
$PackagePath = Join-Path $TestDir "descriptor_table_slots.ashader"
$GeneratedPath = Join-Path $TestDir "bindings.odin"

function Assert-Contains {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Text,

		[Parameter(Mandatory = $true)]
		[string]$Snippet
	)

	if (-not $Text.Contains($Snippet)) {
		Write-Error "Missing generated descriptor-table metadata: $Snippet"
	}
}

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $SourcePath -Value @'
struct Item
{
	float4 value;
	uint id;
};

cbuffer FrameUniforms
{
	float4 tint;
};

Texture2D<float4> input_texture;
SamplerState input_sampler;
RWTexture2D<float4> output_image;
RWStructuredBuffer<Item> output_items;

[shader("compute")]
[numthreads(8, 4, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	float2 uv = float2(0.5, 0.5);
	float4 color = input_texture.SampleLevel(input_sampler, uv, 0.0) * tint;

	output_image[dispatch_id.xy] = color;

	Item item;
	item.value = color;
	item.id = dispatch_id.x;
	output_items[dispatch_id.y * 1024 + dispatch_id.x] = item;
}
'@

$Source = Get-Content -LiteralPath $SourcePath -Raw
if ($Source -match "register\s*\(") {
	throw "descriptor table slot test shader must stay register-free"
}

Invoke-Native -Command "odin" -Arguments @(
	"build",
	(Join-Path $Root.Path "tools\ape_shaderc"),
	"-out:$ShadercPath"
)

Invoke-Native -Command $ShadercPath -Arguments @(
	"-shader-name", "descriptor_table_slots",
	"-kind", "compute",
	"-source", $SourcePath,
	"-build-dir", $TestDir,
	"-package", $PackagePath,
	"-generated", $GeneratedPath
)

$Generated = Get-Content -LiteralPath $GeneratedPath -Raw
$ExpectedSnippets = @(
	"BINDING_RECORD_COUNT :: 10",
	"D3D11_CS_UB_FrameUniforms :: 0",
	"D3D11_CS_VIEW_input_texture :: 0",
	"D3D11_CS_SMP_input_sampler :: 0",
	"D3D11_CS_VIEW_output_image :: 0",
	"D3D11_CS_VIEW_output_items :: 1",
	"VK_CS_UB_FrameUniforms :: 0",
	"VK_CS_VIEW_input_texture :: 1",
	"VK_CS_SMP_input_sampler :: 2",
	"VK_CS_VIEW_output_image :: 3",
	"VK_CS_VIEW_output_items :: 4",
	"UB_FrameUniforms :: 0",
	"VIEW_input_texture :: 0",
	"VIEW_output_image :: 1",
	"VIEW_output_items :: 2",
	"SMP_input_sampler :: 0",
	"VIEW_KIND_input_texture :: gfx.View_Kind.Sampled",
	"VIEW_ACCESS_input_texture :: gfx.Shader_Resource_Access.Read",
	"VIEW_KIND_output_image :: gfx.View_Kind.Storage_Image",
	"VIEW_ACCESS_output_image :: gfx.Shader_Resource_Access.Read_Write",
	"VIEW_FORMAT_output_image :: gfx.Pixel_Format.RGBA32F",
	"VIEW_KIND_output_items :: gfx.View_Kind.Storage_Buffer",
	"VIEW_ACCESS_output_items :: gfx.Shader_Resource_Access.Read_Write",
	"VIEW_STRIDE_output_items :: 20",
	"Binding_Uniform_Block_Desc :: struct",
	"Binding_Resource_View_Desc :: struct",
	"uniform_block: Binding_Uniform_Block_Desc",
	"resource_view: Binding_Resource_View_Desc",
	"uniform_block = {",
	"resource_view = {",
	"storage_buffer_stride = 20",
	"target = gfx.Backend.D3D11",
	"target = gfx.Backend.Vulkan",
	"native_slot = 4"
)

foreach ($Snippet in $ExpectedSnippets) {
	Assert-Contains -Text $Generated -Snippet $Snippet
}

if ($Generated -match "native_space: u32,\s*size: u32,") {
	Write-Error "Generated binding records still expose flat uniform-block payload fields"
}

Write-Host "Shaderc descriptor-table slot reflection test passed"
