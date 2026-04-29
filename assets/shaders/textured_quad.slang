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

struct Material_Params
{
	Texture2D<float4> ape_texture;
	SamplerState ape_sampler;
};

ParameterBlock<Material_Params> material;

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
	return material.ape_texture.Sample(material.ape_sampler, input.uv);
}
