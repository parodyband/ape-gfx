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

Texture2D<float4> ape_texture;
SamplerState ape_sampler;

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
	float sampled_depth = ape_texture.Sample(ape_sampler, input.uv).r;
	float shade = saturate((1.0 - sampled_depth) * 28.0);
	return float4(shade, shade, shade, 1.0);
}
