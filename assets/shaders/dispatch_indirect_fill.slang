RWStructuredBuffer<uint> output_buffer : register(u0);

[shader("compute")]
[numthreads(4, 1, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	output_buffer[dispatch_id.x] = dispatch_id.x + 1;
}
