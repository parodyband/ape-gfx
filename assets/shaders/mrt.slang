struct VS_Input
{
	float3 position : POSITION;
	float3 color : COLOR0;
};

struct VS_Output
{
	float4 position : SV_Position;
	float3 color : COLOR0;
	float2 uv : TEXCOORD0;
};

struct FS_Output
{
	float4 color0 : SV_Target0;
	float4 color1 : SV_Target1;
};

cbuffer FrameUniforms : register(b0)
{
	float4 ape_frame;
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position.xy + ape_frame.xy, input.position.z, 1.0);
	output.color = input.color;
	output.uv = input.position.xy * 0.5 + 0.5;
	return output;
}

[shader("fragment")]
FS_Output fs_main(VS_Output input)
{
	float pulse = ape_frame.z;
	float3 warm = input.color * float3(1.0, 0.78, 0.48);
	float3 cool = float3(input.uv.x, input.uv.y, 1.0 - input.uv.x) * (1.0 - input.color * 0.35);

	FS_Output output;
	output.color0 = float4(warm * pulse, 1.0);
	output.color1 = float4(cool, 1.0);
	return output;
}
