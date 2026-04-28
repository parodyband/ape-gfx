struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

cbuffer ObjectUniforms : register(b0)
{
	row_major float4x4 ape_model;
	row_major float4x4 ape_light_view_proj;
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	float4 local = float4(input.position, 1.0);
	float4 world = mul(ape_model, local);

	VS_Output output;
	output.position = mul(ape_light_view_proj, world);
	return output;
}

[shader("fragment")]
void fs_main(VS_Output input)
{
}
