#+private
package gfx

vulkan_init :: proc(ctx: ^Context) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: backend scaffold exists, instance/device creation is not implemented yet")
	return false
}

vulkan_shutdown :: proc(ctx: ^Context) {}

vulkan_create_buffer :: proc(ctx: ^Context, handle: Buffer, desc: Buffer_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: create_buffer is not implemented yet")
	return false
}

vulkan_destroy_buffer :: proc(ctx: ^Context, handle: Buffer) {}

vulkan_update_buffer :: proc(ctx: ^Context, desc: Buffer_Update_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: update_buffer is not implemented yet")
	return false
}

vulkan_read_buffer :: proc(ctx: ^Context, desc: Buffer_Read_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: read_buffer is not implemented yet")
	return false
}

vulkan_create_image :: proc(ctx: ^Context, handle: Image, desc: Image_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: create_image is not implemented yet")
	return false
}

vulkan_destroy_image :: proc(ctx: ^Context, handle: Image) {}

vulkan_update_image :: proc(ctx: ^Context, desc: Image_Update_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: update_image is not implemented yet")
	return false
}

vulkan_resolve_image :: proc(ctx: ^Context, desc: Image_Resolve_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: resolve_image is not implemented yet")
	return false
}

vulkan_create_view :: proc(ctx: ^Context, handle: View, desc: View_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: create_view is not implemented yet")
	return false
}

vulkan_destroy_view :: proc(ctx: ^Context, handle: View) {}

vulkan_query_buffer_state :: proc(ctx: ^Context, handle: Buffer) -> Buffer_State {
	return {}
}

vulkan_query_image_state :: proc(ctx: ^Context, handle: Image) -> Image_State {
	return {}
}

vulkan_query_view_state :: proc(ctx: ^Context, handle: View) -> View_State {
	return {}
}

vulkan_query_features :: proc(ctx: ^Context) -> Features {
	return {backend = .Vulkan}
}

vulkan_query_limits :: proc(ctx: ^Context) -> Limits {
	return api_limits()
}

vulkan_create_sampler :: proc(ctx: ^Context, handle: Sampler, desc: Sampler_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: create_sampler is not implemented yet")
	return false
}

vulkan_destroy_sampler :: proc(ctx: ^Context, handle: Sampler) {}

vulkan_create_shader :: proc(ctx: ^Context, handle: Shader, desc: Shader_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: create_shader is not implemented yet")
	return false
}

vulkan_destroy_shader :: proc(ctx: ^Context, handle: Shader) {}

vulkan_create_pipeline :: proc(ctx: ^Context, handle: Pipeline, desc: Pipeline_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: create_pipeline is not implemented yet")
	return false
}

vulkan_destroy_pipeline :: proc(ctx: ^Context, handle: Pipeline) {}

vulkan_create_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline, desc: Compute_Pipeline_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: create_compute_pipeline is not implemented yet")
	return false
}

vulkan_destroy_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline) {}

vulkan_resize :: proc(ctx: ^Context, width, height: i32) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: resize is not implemented yet")
	return false
}

vulkan_begin_pass :: proc(ctx: ^Context, desc: Pass_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: begin_pass is not implemented yet")
	return false
}

vulkan_begin_compute_pass :: proc(ctx: ^Context, desc: Compute_Pass_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: begin_compute_pass is not implemented yet")
	return false
}

vulkan_apply_pipeline :: proc(ctx: ^Context, pipeline: Pipeline) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: apply_pipeline is not implemented yet")
	return false
}

vulkan_apply_compute_pipeline :: proc(ctx: ^Context, pipeline: Compute_Pipeline) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: apply_compute_pipeline is not implemented yet")
	return false
}

vulkan_apply_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: apply_bindings is not implemented yet")
	return false
}

vulkan_apply_uniforms :: proc(ctx: ^Context, group: u32, slot: int, data: Range) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: apply_uniforms is not implemented yet")
	return false
}

vulkan_apply_uniform_at :: proc(ctx: ^Context, group: u32, slot: int, slice: Transient_Slice, byte_size: int) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: apply_uniform_at is not implemented yet")
	return false
}

vulkan_draw :: proc(ctx: ^Context, base_element: i32, num_elements: i32, num_instances: i32) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: draw is not implemented yet")
	return false
}

vulkan_dispatch :: proc(ctx: ^Context, group_count_x, group_count_y, group_count_z: u32) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: dispatch is not implemented yet")
	return false
}

vulkan_draw_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: u32) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: draw_indirect is not implemented yet")
	return false
}

vulkan_draw_indexed_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: u32) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: draw_indexed_indirect is not implemented yet")
	return false
}

vulkan_dispatch_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: dispatch_indirect is not implemented yet")
	return false
}

vulkan_end_pass :: proc(ctx: ^Context) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: end_pass is not implemented yet")
	return false
}

vulkan_end_compute_pass :: proc(ctx: ^Context) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: end_compute_pass is not implemented yet")
	return false
}

vulkan_barrier :: proc(ctx: ^Context, desc: Barrier_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: barrier is not implemented yet")
	return false
}

vulkan_commit :: proc(ctx: ^Context) -> bool {
	set_unsupported_error(ctx, "gfx.vulkan: commit is not implemented yet")
	return false
}

vulkan_create_transient_chunk :: proc(ctx: ^Context, role: Transient_Usage, capacity: int, label: string) -> (Buffer, rawptr, bool) {
	set_unsupported_error(ctx, "gfx.vulkan: transient allocator is not implemented yet")
	return Buffer_Invalid, nil, false
}

vulkan_destroy_transient_chunk :: proc(ctx: ^Context, buffer: Buffer) {}

vulkan_reset_transient_chunk :: proc(ctx: ^Context, buffer: Buffer) -> (rawptr, bool) {
	set_unsupported_error(ctx, "gfx.vulkan: transient allocator is not implemented yet")
	return nil, false
}

vulkan_resolve_transient_chunk_mapped :: proc(ctx: ^Context, buffer: Buffer) -> (rawptr, bool) {
	set_unsupported_error(ctx, "gfx.vulkan: transient allocator is not implemented yet")
	return nil, false
}
