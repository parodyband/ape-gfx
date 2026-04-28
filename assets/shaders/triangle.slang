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

cbuffer FrameUniforms
{
	float4 ape_frame;
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position.xy + ape_frame.xy, input.position.z, 1.0);
	output.color = input.color;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return float4(input.color * ape_frame.z, 1.0);
}
