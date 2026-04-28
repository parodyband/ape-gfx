struct VS_Input
{
	float3 position : POSITION;
	float3 normal : NORMAL;
	float2 uv : TEXCOORD0;
};

struct VS_Output
{
	float4 position : SV_Position;
	float3 world_position : TEXCOORD0;
	float3 normal : TEXCOORD1;
	float2 uv : TEXCOORD2;
	float4 shadow_position : TEXCOORD3;
};

cbuffer ObjectUniforms : register(b0)
{
	float4 ape_model_row0;
	float4 ape_model_row1;
	float4 ape_model_row2;
	float4 ape_model_row3;
	float4 ape_light_view_proj_row0;
	float4 ape_light_view_proj_row1;
	float4 ape_light_view_proj_row2;
	float4 ape_light_view_proj_row3;
};

cbuffer FrameUniforms : register(b1)
{
	float4 ape_view_proj_row0;
	float4 ape_view_proj_row1;
	float4 ape_view_proj_row2;
	float4 ape_view_proj_row3;
	float4 ape_light_pos;
	float4 ape_view_pos;
	float4 ape_shadow_map_size;
};

Texture2D<float4> diffuse_texture : register(t0);
Texture2D<float> shadow_map : register(t1);
SamplerState diffuse_sampler : register(s0);
SamplerState shadow_sampler : register(s1);

static const float SHADOW_BIAS_MIN = 0.005;
static const float SHADOW_BIAS_SLOPE = 0.05;

float4 transform_rows(float4 row0, float4 row1, float4 row2, float4 row3, float4 value)
{
	return float4(
		dot(row0, value),
		dot(row1, value),
		dot(row2, value),
		dot(row3, value));
}

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	float4 local = float4(input.position, 1.0);
	float4 world = transform_rows(ape_model_row0, ape_model_row1, ape_model_row2, ape_model_row3, local);

	VS_Output output;
	output.position = transform_rows(ape_view_proj_row0, ape_view_proj_row1, ape_view_proj_row2, ape_view_proj_row3, world);
	output.world_position = world.xyz;
	output.normal = normalize(float3(
		dot(ape_model_row0.xyz, input.normal),
		dot(ape_model_row1.xyz, input.normal),
		dot(ape_model_row2.xyz, input.normal)));
	output.uv = input.uv;
	output.shadow_position = transform_rows(
		ape_light_view_proj_row0,
		ape_light_view_proj_row1,
		ape_light_view_proj_row2,
		ape_light_view_proj_row3,
		world);
	return output;
}

float shadow_factor(VS_Output input)
{
	float3 projected = input.shadow_position.xyz / input.shadow_position.w;
	float2 uv = float2(projected.x * 0.5 + 0.5, -projected.y * 0.5 + 0.5);
	float current_depth = projected.z;

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || current_depth < 0.0 || current_depth > 1.0)
	{
		return 0.0;
	}

	float3 normal = normalize(input.normal);
	float3 light_dir = normalize(ape_light_pos.xyz - input.world_position);
	float ndotl = saturate(dot(normal, light_dir));
	float bias = max(SHADOW_BIAS_SLOPE * (1.0 - ndotl), SHADOW_BIAS_MIN);
	float2 texel_size = 1.0 / ape_shadow_map_size.xy;

	float shadow = 0.0;
	for (int x = -1; x <= 1; x += 1)
	{
		for (int y = -1; y <= 1; y += 1)
		{
			float closest_depth = shadow_map.Sample(shadow_sampler, uv + float2(x, y) * texel_size);
			shadow += current_depth - bias > closest_depth ? 1.0 : 0.0;
		}
	}

	return shadow / 9.0;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	float3 albedo = diffuse_texture.Sample(diffuse_sampler, input.uv).rgb;
	float3 normal = normalize(input.normal);
	float3 light_dir = normalize(ape_light_pos.xyz - input.world_position);
	float3 view_dir = normalize(ape_view_pos.xyz - input.world_position);
	float3 halfway_dir = normalize(light_dir + view_dir);

	float diffuse_amount = max(dot(normal, light_dir), 0.0);
	float specular_amount = pow(max(dot(normal, halfway_dir), 0.0), 64.0);
	float shadow = shadow_factor(input);

	float3 ambient = 0.25 * albedo;
	float3 direct = (diffuse_amount * 0.9 * albedo) + (specular_amount * 0.22);
	float3 color = ambient + (1.0 - shadow) * direct;
	return float4(color, 1.0);
}
