// Bistro forward base pass with 3-cascade directional sun shadows.
// Vertex layout matches engine.assets.Mesh_Vertex (position, normal, tangent,
// uv0; stride 48).

struct VS_Input
{
	float3 position : POSITION;
	float3 normal   : NORMAL;
	float4 tangent  : TANGENT;
	float2 uv       : TEXCOORD0;
};

struct VS_Output
{
	float4 position       : SV_Position;
	float3 world_position : TEXCOORD0;
	float3 world_normal   : TEXCOORD1;
	float2 uv             : TEXCOORD2;
	float view_depth      : TEXCOORD3;
};

cbuffer ObjectUniforms
{
	row_major float4x4 ape_model;
};

cbuffer FrameUniforms
{
	row_major float4x4 ape_view_proj;
	row_major float4x4 ape_view;
	row_major float4x4 ape_shadow_view_proj_0;
	row_major float4x4 ape_shadow_view_proj_1;
	row_major float4x4 ape_shadow_view_proj_2;
	float4 ape_sun_direction;   // xyz: world-space direction from light to surface (will be negated)
	float4 ape_sun_color;       // rgb: linear color, w: intensity scalar
	float4 ape_ambient;         // rgb: ambient term
	float4 ape_view_pos;        // xyz: camera world position
	float4 ape_cascade_splits;  // xyz: camera-space far split for each cascade
	float4 ape_shadow_map_size; // xy: texel dimensions, zw: inverse dimensions
	float4 ape_shadow_settings; // x: PCF kernel size (1/3/5), y: depth bias, z: normal-offset bias
};

struct Material_Params
{
	Texture2D<float4> base_color_texture;
	SamplerState      base_color_sampler;
};

struct Shadow_Params
{
	Texture2D<float>       shadow_map_0;
	Texture2D<float>       shadow_map_1;
	Texture2D<float>       shadow_map_2;
	SamplerComparisonState shadow_sampler;
};

ParameterBlock<Material_Params> material;
ParameterBlock<Shadow_Params> shadow_resources;

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	float4 local = float4(input.position, 1.0);
	float4 world = mul(ape_model, local);

	VS_Output output;
	output.position = mul(ape_view_proj, world);
	output.world_position = world.xyz;
	output.world_normal = normalize(float3(
		dot(ape_model[0].xyz, input.normal),
		dot(ape_model[1].xyz, input.normal),
		dot(ape_model[2].xyz, input.normal)));
	output.uv = input.uv;
	output.view_depth = mul(ape_view, world).z;
	return output;
}

int select_cascade(float view_depth)
{
	if (view_depth <= ape_cascade_splits.x)
	{
		return 0;
	}
	if (view_depth <= ape_cascade_splits.y)
	{
		return 1;
	}
	return 2;
}

float4 shadow_position_for_cascade(int cascade_index, float4 world)
{
	if (cascade_index == 0)
	{
		return mul(ape_shadow_view_proj_0, world);
	}
	if (cascade_index == 1)
	{
		return mul(ape_shadow_view_proj_1, world);
	}
	return mul(ape_shadow_view_proj_2, world);
}

float sample_shadow_cascade(int cascade_index, float2 uv, float compare_depth)
{
	if (cascade_index == 0)
	{
		return shadow_resources.shadow_map_0.SampleCmpLevelZero(shadow_resources.shadow_sampler, uv, compare_depth);
	}
	if (cascade_index == 1)
	{
		return shadow_resources.shadow_map_1.SampleCmpLevelZero(shadow_resources.shadow_sampler, uv, compare_depth);
	}
	return shadow_resources.shadow_map_2.SampleCmpLevelZero(shadow_resources.shadow_sampler, uv, compare_depth);
}

float shadow_visibility(VS_Output input)
{
	float3 normal = normalize(input.world_normal);
	float3 biased_world = input.world_position + normal * ape_shadow_settings.z;
	int cascade_index = select_cascade(max(input.view_depth, 0.0));
	float4 shadow_position = shadow_position_for_cascade(cascade_index, float4(biased_world, 1.0));
	float3 projected = shadow_position.xyz / shadow_position.w;
	float2 uv = float2(projected.x * 0.5 + 0.5, -projected.y * 0.5 + 0.5);
	float compare_depth = projected.z - ape_shadow_settings.y;

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || compare_depth < 0.0 || compare_depth > 1.0)
	{
		return 1.0;
	}

	int kernel = (int)ape_shadow_settings.x;
	int radius = kernel <= 1 ? 0 : (kernel <= 3 ? 1 : 2);
	float2 texel_size = ape_shadow_map_size.zw;
	float visibility = 0.0;
	float sample_count = 0.0;

	[unroll]
	for (int y = -2; y <= 2; y += 1)
	{
		[unroll]
		for (int x = -2; x <= 2; x += 1)
		{
			if (abs(x) <= radius && abs(y) <= radius)
			{
				visibility += sample_shadow_cascade(cascade_index, uv + float2(x, y) * texel_size, compare_depth);
				sample_count += 1.0;
			}
		}
	}

	return visibility / max(sample_count, 1.0);
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	float4 base = material.base_color_texture.Sample(material.base_color_sampler, input.uv);
	float3 albedo = base.rgb;

	float3 normal = normalize(input.world_normal);
	float3 to_light = normalize(-ape_sun_direction.xyz);
	float ndotl = saturate(dot(normal, to_light));
	float shadow = shadow_visibility(input);

	float3 sun = ape_sun_color.rgb * ape_sun_color.w;
	float3 lit = ape_ambient.rgb * albedo + shadow * ndotl * sun * albedo;
	return float4(lit, 1.0);
}
