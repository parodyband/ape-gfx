param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\shaderc_parameter_block_groups"
$ShadercPath = Join-Path $TestDir "ape_shaderc.exe"
$SourcePath = Join-Path $TestDir "parameter_block_groups.slang"
$PackagePath = Join-Path $TestDir "parameter_block_groups.ashader"
$GeneratedPath = Join-Path $TestDir "bindings.odin"

function Assert-Contains {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Text,

		[Parameter(Mandatory = $true)]
		[string]$Snippet
	)

	if (-not $Text.Contains($Snippet)) {
		Write-Error "Missing generated ParameterBlock metadata: $Snippet"
	}
}

function Invoke-ShadercExpectFailure {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[string]$Source,

		[Parameter(Mandatory = $true)]
		[string]$ExpectedPattern
	)

	$FailureSourcePath = Join-Path $TestDir "$Name.slang"
	$FailurePackagePath = Join-Path $TestDir "$Name.ashader"
	$FailureGeneratedPath = Join-Path $TestDir "$($Name)_bindings.odin"
	Set-Content -LiteralPath $FailureSourcePath -Value $Source

	$previousErrorActionPreference = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	try {
		$output = & $ShadercPath `
			"-shader-name" $Name `
			"-source" $FailureSourcePath `
			"-build-dir" $TestDir `
			"-package" $FailurePackagePath `
			"-generated" $FailureGeneratedPath 2>&1
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

Set-Content -LiteralPath $SourcePath -Value @'
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

cbuffer FrameUniforms
{
	float4 tint;
};

struct Material_Params
{
	Texture2D<float4> diffuse_texture;
	SamplerState diffuse_sampler;
};

struct Shadow_Params
{
	Texture2D<float> shadow_map;
	SamplerState shadow_sampler;
};

ParameterBlock<Material_Params> material;
ParameterBlock<Shadow_Params> shadow_resources;

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
	float4 color = material.diffuse_texture.Sample(material.diffuse_sampler, input.uv);
	float shadow = shadow_resources.shadow_map.Sample(shadow_resources.shadow_sampler, input.uv);
	return color * tint * shadow;
}
'@

$Source = Get-Content -LiteralPath $SourcePath -Raw
if ($Source -match "register\s*\(") {
	throw "ParameterBlock group test shader must stay register-free"
}

Invoke-Native -Command "odin" -Arguments @(
	"build",
	(Join-Path $Root.Path "tools\ape_shaderc"),
	"-out:$ShadercPath"
)

Invoke-Native -Command $ShadercPath -Arguments @(
	"-shader-name", "parameter_block_groups",
	"-source", $SourcePath,
	"-build-dir", $TestDir,
	"-package", $PackagePath,
	"-generated", $GeneratedPath
)

$Generated = Get-Content -LiteralPath $GeneratedPath -Raw
$ExpectedSnippets = @(
	"GROUP_0 :: 0",
	"GROUP_1 :: 1",
	"GROUP_2 :: 2",
	"UB_FrameUniforms :: 0",
	"VIEW_material_diffuse_texture :: 0",
	"SMP_material_diffuse_sampler :: 0",
	"VIEW_shadow_resources_shadow_map :: 0",
	"SMP_shadow_resources_shadow_sampler :: 0",
	"D3D11_FS_VIEW_material_diffuse_texture :: 0",
	"D3D11_FS_SMP_material_diffuse_sampler :: 0",
	"D3D11_FS_VIEW_shadow_resources_shadow_map :: 1",
	"D3D11_FS_SMP_shadow_resources_shadow_sampler :: 1",
	"VK_FS_VIEW_material_diffuse_texture_SPACE :: 1",
	"VK_FS_SMP_material_diffuse_sampler_SPACE :: 1",
	"VK_FS_VIEW_shadow_resources_shadow_map_SPACE :: 2",
	"VK_FS_SMP_shadow_resources_shadow_sampler_SPACE :: 2",
	"name = cstring(`"material.diffuse_texture`")",
	"group = 1,",
	"name = cstring(`"shadow_resources.shadow_map`")",
	"group = 2,",
	'binding_group_layout_desc :: proc(group: u32 = 0, label: string = "") -> gfx.Binding_Group_Layout_Desc',
	"desc.group = group",
	"set_group_view_material_diffuse_texture :: proc(group: ^gfx.Binding_Group_Desc, view: gfx.View)",
	"set_group_sampler_material_diffuse_sampler :: proc(group: ^gfx.Binding_Group_Desc, sampler: gfx.Sampler)",
	"set_group_view_shadow_resources_shadow_map :: proc(group: ^gfx.Binding_Group_Desc, view: gfx.View)",
	"set_group_sampler_shadow_resources_shadow_sampler :: proc(group: ^gfx.Binding_Group_Desc, sampler: gfx.Sampler)",
	"bindings.views[GROUP_1][VIEW_material_diffuse_texture] = view",
	"bindings.views[GROUP_2][VIEW_shadow_resources_shadow_map] = view"
)

foreach ($Snippet in $ExpectedSnippets) {
	Assert-Contains -Text $Generated -Snippet $Snippet
}

Invoke-ShadercExpectFailure `
	-Name "invalid_parameter_block_data" `
	-ExpectedPattern "ParameterBlock ordinary data is not supported yet" `
	-Source @'
struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

struct Bad_Params
{
	float4 solid_color;
};

ParameterBlock<Bad_Params> bad_data;

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
	return bad_data.solid_color;
}
'@

Invoke-ShadercExpectFailure `
	-Name "invalid_parameter_block_array" `
	-ExpectedPattern "ParameterBlock arrays are not supported yet" `
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

struct Bad_Params
{
	Texture2D<float4> textures[2];
	SamplerState sampler;
};

ParameterBlock<Bad_Params> bad_array;

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
	return bad_array.textures[0].Sample(bad_array.sampler, input.uv);
}
'@

Invoke-ShadercExpectFailure `
	-Name "invalid_parameter_block_nested" `
	-ExpectedPattern "nested ParameterBlock fields are not supported yet" `
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

struct Inner_Params
{
	Texture2D<float4> texture;
	SamplerState sampler;
};

struct Outer_Params
{
	ParameterBlock<Inner_Params> inner;
};

ParameterBlock<Outer_Params> bad_nested;

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
	return bad_nested.inner.texture.Sample(bad_nested.inner.sampler, input.uv);
}
'@

Invoke-ShadercExpectFailure `
	-Name "invalid_parameter_block_constant_buffer" `
	-ExpectedPattern "ParameterBlock constant buffer fields are not supported yet" `
	-Source @'
struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

struct Data
{
	float4 tint;
};

struct Bad_Params
{
	ConstantBuffer<Data> data;
};

ParameterBlock<Bad_Params> bad_constant_buffer;

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
	return bad_constant_buffer.data.tint;
}
'@

Invoke-ShadercExpectFailure `
	-Name "invalid_parameter_block_texture_shape" `
	-ExpectedPattern "unsupported resource texture shape" `
	-Source @'
struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

struct Bad_Params
{
	TextureCube<float4> cube_texture;
	SamplerState sampler;
};

ParameterBlock<Bad_Params> bad_texture_shape;

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
	return bad_texture_shape.cube_texture.Sample(bad_texture_shape.sampler, float3(1.0, 0.0, 0.0));
}
'@

Write-Host "Shaderc ParameterBlock group reflection test passed"
