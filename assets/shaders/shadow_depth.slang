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
	float4 ape_model_row0;
	float4 ape_model_row1;
	float4 ape_model_row2;
	float4 ape_model_row3;
	float4 ape_light_view_proj_row0;
	float4 ape_light_view_proj_row1;
	float4 ape_light_view_proj_row2;
	float4 ape_light_view_proj_row3;
};

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
	output.position = transform_rows(
		ape_light_view_proj_row0,
		ape_light_view_proj_row1,
		ape_light_view_proj_row2,
		ape_light_view_proj_row3,
		world);
	return output;
}

[shader("fragment")]
void fs_main(VS_Output input)
{
}
