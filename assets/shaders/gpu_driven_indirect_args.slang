// Compute shader for samples/gpu_driven_indirect (AAA roadmap item 15).
// Writes a single gfx.Draw_Indirect_Args record into a raw indirect buffer so a
// later draw_indirect call can consume it without a CPU-side update.

RWByteAddressBuffer indirect_args;

cbuffer ComputeUniforms
{
	uint quad_count;
	uint vertices_per_quad;
	uint pad0;
	uint pad1;
};

[shader("compute")]
[numthreads(1, 1, 1)]
void cs_main(uint3 tid : SV_DispatchThreadID)
{
	// Layout matches gfx.Draw_Indirect_Args:
	//   { vertex_count, instance_count, first_vertex, first_instance }
	indirect_args.Store4(0, uint4(quad_count * vertices_per_quad, 1, 0, 0));
}
