struct VS_Input
{
	float3 position : POSITION;
	float2 uv : TEXCOORD0;
};

struct VS_Output
{
	float4 position : SV_Position;
	float2 uv : TEXCOORD0;
};

cbuffer FrameUniforms
{
	row_major float4x4 ape_mvp;
};

Texture2D<float4> ape_texture;
SamplerState ape_sampler;

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	float4 world = float4(input.position, 1.0);

	VS_Output output;
	output.position = mul(ape_mvp, world);
	output.uv = input.uv;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return ape_texture.Sample(ape_sampler, input.uv);
}
