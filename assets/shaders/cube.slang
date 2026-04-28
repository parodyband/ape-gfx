struct VS_Input
{
	float3 position : POSITION;
	float3 color : COLOR0;
};

struct VS_Output
{
	float4 position : SV_Position;
	float3 color : COLOR0;
};

cbuffer FrameUniforms : register(b0)
{
	float4 ape_mvp_row0;
	float4 ape_mvp_row1;
	float4 ape_mvp_row2;
	float4 ape_mvp_row3;
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	float4 world = float4(input.position, 1.0);

	VS_Output output;
	output.position = float4(
		dot(ape_mvp_row0, world),
		dot(ape_mvp_row1, world),
		dot(ape_mvp_row2, world),
		dot(ape_mvp_row3, world));
	output.color = input.color;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return float4(input.color, 1.0);
}
