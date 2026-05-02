#+private
package gfx

backend_init :: proc(ctx: ^Context) -> bool {
	switch ctx.backend {
	case .Null:
		return null_init(ctx)
	case .D3D12:
		return d3d12_init(ctx)
	case .Vulkan:
		return vulkan_init(ctx)
	case .Auto:
		set_validation_error(ctx, "gfx: backend must be resolved before initialization")
		return false
	}

	return false
}

backend_shutdown :: proc(ctx: ^Context) {
	switch ctx.backend {
	case .Null:
		null_shutdown(ctx)
	case .D3D12:
		d3d12_shutdown(ctx)
	case .Vulkan:
		vulkan_shutdown(ctx)
	case .Auto:
	}
}

backend_create_buffer :: proc(ctx: ^Context, handle: Buffer, desc: Buffer_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_create_buffer(ctx, handle, desc)
	case .D3D12:
		return d3d12_create_buffer(ctx, handle, desc)
	case .Vulkan:
		return vulkan_create_buffer(ctx, handle, desc)
	case .Auto:
	}

	return false
}

backend_destroy_buffer :: proc(ctx: ^Context, handle: Buffer) {
	switch ctx.backend {
	case .Null:
		null_destroy_buffer(ctx, handle)
	case .D3D12:
		d3d12_destroy_buffer(ctx, handle)
	case .Vulkan:
		vulkan_destroy_buffer(ctx, handle)
	case .Auto:
	}
}

backend_update_buffer :: proc(ctx: ^Context, desc: Buffer_Update_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_update_buffer(ctx, desc)
	case .D3D12:
		return d3d12_update_buffer(ctx, desc)
	case .Vulkan:
		return vulkan_update_buffer(ctx, desc)
	case .Auto:
	}

	return false
}

backend_read_buffer :: proc(ctx: ^Context, desc: Buffer_Read_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_read_buffer(ctx, desc)
	case .D3D12:
		return d3d12_read_buffer(ctx, desc)
	case .Vulkan:
		return vulkan_read_buffer(ctx, desc)
	case .Auto:
	}

	return false
}

backend_create_image :: proc(ctx: ^Context, handle: Image, desc: Image_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_create_image(ctx, handle, desc)
	case .D3D12:
		return d3d12_create_image(ctx, handle, desc)
	case .Vulkan:
		return vulkan_create_image(ctx, handle, desc)
	case .Auto:
	}

	return false
}

backend_destroy_image :: proc(ctx: ^Context, handle: Image) {
	switch ctx.backend {
	case .Null:
		null_destroy_image(ctx, handle)
	case .D3D12:
		d3d12_destroy_image(ctx, handle)
	case .Vulkan:
		vulkan_destroy_image(ctx, handle)
	case .Auto:
	}
}

backend_update_image :: proc(ctx: ^Context, desc: Image_Update_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_update_image(ctx, desc)
	case .D3D12:
		return d3d12_update_image(ctx, desc)
	case .Vulkan:
		return vulkan_update_image(ctx, desc)
	case .Auto:
	}

	return false
}

backend_resolve_image :: proc(ctx: ^Context, desc: Image_Resolve_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_resolve_image(ctx, desc)
	case .D3D12:
		return d3d12_resolve_image(ctx, desc)
	case .Vulkan:
		return vulkan_resolve_image(ctx, desc)
	case .Auto:
	}

	return false
}

backend_create_view :: proc(ctx: ^Context, handle: View, desc: View_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_create_view(ctx, handle, desc)
	case .D3D12:
		return d3d12_create_view(ctx, handle, desc)
	case .Vulkan:
		return vulkan_create_view(ctx, handle, desc)
	case .Auto:
	}

	return false
}

backend_destroy_view :: proc(ctx: ^Context, handle: View) {
	switch ctx.backend {
	case .Null:
		null_destroy_view(ctx, handle)
	case .D3D12:
		d3d12_destroy_view(ctx, handle)
	case .Vulkan:
		vulkan_destroy_view(ctx, handle)
	case .Auto:
	}
}

backend_query_buffer_state :: proc(ctx: ^Context, handle: Buffer) -> Buffer_State {
	switch ctx.backend {
	case .Null:
		return null_query_buffer_state(ctx, handle)
	case .D3D12:
		return d3d12_query_buffer_state(ctx, handle)
	case .Vulkan:
		return vulkan_query_buffer_state(ctx, handle)
	case .Auto:
	}

	return {}
}

backend_query_image_state :: proc(ctx: ^Context, handle: Image) -> Image_State {
	switch ctx.backend {
	case .Null:
		return null_query_image_state(ctx, handle)
	case .D3D12:
		return d3d12_query_image_state(ctx, handle)
	case .Vulkan:
		return vulkan_query_image_state(ctx, handle)
	case .Auto:
	}

	return {}
}

backend_query_view_state :: proc(ctx: ^Context, handle: View) -> View_State {
	switch ctx.backend {
	case .Null:
		return null_query_view_state(ctx, handle)
	case .D3D12:
		return d3d12_query_view_state(ctx, handle)
	case .Vulkan:
		return vulkan_query_view_state(ctx, handle)
	case .Auto:
	}

	return {}
}

backend_query_features :: proc(ctx: ^Context) -> Features {
	switch ctx.backend {
	case .Null:
		return null_query_features(ctx)
	case .D3D12:
		return d3d12_query_features(ctx)
	case .Vulkan:
		return vulkan_query_features(ctx)
	case .Auto:
	}

	return {}
}

backend_query_limits :: proc(ctx: ^Context) -> Limits {
	switch ctx.backend {
	case .Null:
		return null_query_limits(ctx)
	case .D3D12:
		return d3d12_query_limits(ctx)
	case .Vulkan:
		return vulkan_query_limits(ctx)
	case .Auto:
	}

	return {}
}

backend_create_sampler :: proc(ctx: ^Context, handle: Sampler, desc: Sampler_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_create_sampler(ctx, handle, desc)
	case .D3D12:
		return d3d12_create_sampler(ctx, handle, desc)
	case .Vulkan:
		return vulkan_create_sampler(ctx, handle, desc)
	case .Auto:
	}

	return false
}

backend_destroy_sampler :: proc(ctx: ^Context, handle: Sampler) {
	switch ctx.backend {
	case .Null:
		null_destroy_sampler(ctx, handle)
	case .D3D12:
		d3d12_destroy_sampler(ctx, handle)
	case .Vulkan:
		vulkan_destroy_sampler(ctx, handle)
	case .Auto:
	}
}

backend_create_shader :: proc(ctx: ^Context, handle: Shader, desc: Shader_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_create_shader(ctx, handle, desc)
	case .D3D12:
		return d3d12_create_shader(ctx, handle, desc)
	case .Vulkan:
		return vulkan_create_shader(ctx, handle, desc)
	case .Auto:
	}

	return false
}

backend_destroy_shader :: proc(ctx: ^Context, handle: Shader) {
	switch ctx.backend {
	case .Null:
		null_destroy_shader(ctx, handle)
	case .D3D12:
		d3d12_destroy_shader(ctx, handle)
	case .Vulkan:
		vulkan_destroy_shader(ctx, handle)
	case .Auto:
	}
}

backend_create_pipeline :: proc(ctx: ^Context, handle: Pipeline, desc: Pipeline_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_create_pipeline(ctx, handle, desc)
	case .D3D12:
		return d3d12_create_pipeline(ctx, handle, desc)
	case .Vulkan:
		return vulkan_create_pipeline(ctx, handle, desc)
	case .Auto:
	}

	return false
}

backend_create_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline, desc: Compute_Pipeline_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_create_compute_pipeline(ctx, handle, desc)
	case .D3D12:
		return d3d12_create_compute_pipeline(ctx, handle, desc)
	case .Vulkan:
		return vulkan_create_compute_pipeline(ctx, handle, desc)
	case .Auto:
	}

	return false
}

backend_destroy_pipeline :: proc(ctx: ^Context, handle: Pipeline) {
	switch ctx.backend {
	case .Null:
		null_destroy_pipeline(ctx, handle)
	case .D3D12:
		d3d12_destroy_pipeline(ctx, handle)
	case .Vulkan:
		vulkan_destroy_pipeline(ctx, handle)
	case .Auto:
	}
}

backend_destroy_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline) {
	switch ctx.backend {
	case .Null:
		null_destroy_compute_pipeline(ctx, handle)
	case .D3D12:
		d3d12_destroy_compute_pipeline(ctx, handle)
	case .Vulkan:
		vulkan_destroy_compute_pipeline(ctx, handle)
	case .Auto:
	}
}

backend_resize :: proc(ctx: ^Context, width, height: i32) -> bool {
	switch ctx.backend {
	case .Null:
		return null_resize(ctx, width, height)
	case .D3D12:
		return d3d12_resize(ctx, width, height)
	case .Vulkan:
		return vulkan_resize(ctx, width, height)
	case .Auto:
	}

	return false
}

backend_begin_pass :: proc(ctx: ^Context, desc: Pass_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_begin_pass(ctx, desc)
	case .D3D12:
		return d3d12_begin_pass(ctx, desc)
	case .Vulkan:
		return vulkan_begin_pass(ctx, desc)
	case .Auto:
	}

	return false
}

backend_begin_compute_pass :: proc(ctx: ^Context, desc: Compute_Pass_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_begin_compute_pass(ctx, desc)
	case .D3D12:
		return d3d12_begin_compute_pass(ctx, desc)
	case .Vulkan:
		return vulkan_begin_compute_pass(ctx, desc)
	case .Auto:
	}

	return false
}

backend_apply_pipeline :: proc(ctx: ^Context, pipeline: Pipeline) -> bool {
	switch ctx.backend {
	case .Null:
		return null_apply_pipeline(ctx, pipeline)
	case .D3D12:
		return d3d12_apply_pipeline(ctx, pipeline)
	case .Vulkan:
		return vulkan_apply_pipeline(ctx, pipeline)
	case .Auto:
	}

	return false
}

backend_apply_compute_pipeline :: proc(ctx: ^Context, pipeline: Compute_Pipeline) -> bool {
	switch ctx.backend {
	case .Null:
		return null_apply_compute_pipeline(ctx, pipeline)
	case .D3D12:
		return d3d12_apply_compute_pipeline(ctx, pipeline)
	case .Vulkan:
		return vulkan_apply_compute_pipeline(ctx, pipeline)
	case .Auto:
	}

	return false
}

backend_apply_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	switch ctx.backend {
	case .Null:
		return null_apply_bindings(ctx, bindings)
	case .D3D12:
		return d3d12_apply_bindings(ctx, bindings)
	case .Vulkan:
		return vulkan_apply_bindings(ctx, bindings)
	case .Auto:
	}

	return false
}

backend_apply_uniforms :: proc(ctx: ^Context, group: u32, slot: int, data: Range) -> bool {
	switch ctx.backend {
	case .Null:
		return null_apply_uniforms(ctx, group, slot, data)
	case .D3D12:
		return d3d12_apply_uniforms(ctx, group, slot, data)
	case .Vulkan:
		return vulkan_apply_uniforms(ctx, group, slot, data)
	case .Auto:
	}

	return false
}

backend_apply_uniform_at :: proc(ctx: ^Context, group: u32, slot: int, slice: Transient_Slice, byte_size: int) -> bool {
	switch ctx.backend {
	case .Null:
		return null_apply_uniform_at(ctx, group, slot, slice, byte_size)
	case .D3D12:
		return d3d12_apply_uniform_at(ctx, group, slot, slice, byte_size)
	case .Vulkan:
		return vulkan_apply_uniform_at(ctx, group, slot, slice, byte_size)
	case .Auto:
	}

	return false
}

backend_draw :: proc(ctx: ^Context, base_element: i32, num_elements: i32, num_instances: i32, base_instance: i32, base_vertex: i32) -> bool {
	switch ctx.backend {
	case .Null:
		return null_draw(ctx, base_element, num_elements, num_instances, base_instance, base_vertex)
	case .D3D12:
		return d3d12_draw(ctx, base_element, num_elements, num_instances, base_instance, base_vertex)
	case .Vulkan:
		return vulkan_draw(ctx, base_element, num_elements, num_instances, base_instance, base_vertex)
	case .Auto:
	}

	return false
}

backend_dispatch :: proc(ctx: ^Context, group_count_x, group_count_y, group_count_z: u32) -> bool {
	switch ctx.backend {
	case .Null:
		return null_dispatch(ctx, group_count_x, group_count_y, group_count_z)
	case .D3D12:
		return d3d12_dispatch(ctx, group_count_x, group_count_y, group_count_z)
	case .Vulkan:
		return vulkan_dispatch(ctx, group_count_x, group_count_y, group_count_z)
	case .Auto:
	}

	return false
}

backend_draw_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: u32) -> bool {
	switch ctx.backend {
	case .Null:
		return null_draw_indirect(ctx, indirect_buffer, offset, draw_count, stride)
	case .D3D12:
		return d3d12_draw_indirect(ctx, indirect_buffer, offset, draw_count, stride)
	case .Vulkan:
		return vulkan_draw_indirect(ctx, indirect_buffer, offset, draw_count, stride)
	case .Auto:
	}

	return false
}

backend_draw_indexed_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: u32) -> bool {
	switch ctx.backend {
	case .Null:
		return null_draw_indexed_indirect(ctx, indirect_buffer, offset, draw_count, stride)
	case .D3D12:
		return d3d12_draw_indexed_indirect(ctx, indirect_buffer, offset, draw_count, stride)
	case .Vulkan:
		return vulkan_draw_indexed_indirect(ctx, indirect_buffer, offset, draw_count, stride)
	case .Auto:
	}

	return false
}

backend_draw_indexed_indirect_count :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, count_buffer: Buffer, count_offset: int, max_draw_count: u32, stride: u32) -> bool {
	switch ctx.backend {
	case .Null:
		return null_draw_indexed_indirect_count(ctx, indirect_buffer, offset, count_buffer, count_offset, max_draw_count, stride)
	case .D3D12:
		return d3d12_draw_indexed_indirect_count(ctx, indirect_buffer, offset, count_buffer, count_offset, max_draw_count, stride)
	case .Vulkan:
		return vulkan_draw_indexed_indirect_count(ctx, indirect_buffer, offset, count_buffer, count_offset, max_draw_count, stride)
	case .Auto:
	}

	return false
}

backend_dispatch_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int) -> bool {
	switch ctx.backend {
	case .Null:
		return null_dispatch_indirect(ctx, indirect_buffer, offset)
	case .D3D12:
		return d3d12_dispatch_indirect(ctx, indirect_buffer, offset)
	case .Vulkan:
		return vulkan_dispatch_indirect(ctx, indirect_buffer, offset)
	case .Auto:
	}

	return false
}

backend_dispatch_mesh :: proc(ctx: ^Context, x, y, z: u32) -> bool {
	switch ctx.backend {
	case .Null:
		return true
	case .D3D12:
		return d3d12_dispatch_mesh(ctx, x, y, z)
	case .Vulkan:
		set_unsupported_error(ctx, "gfx.vulkan: dispatch_mesh not implemented")
		return false
	case .Auto:
	}
	return false
}

backend_begin_event :: proc(ctx: ^Context, name: string) -> bool {
	switch ctx.backend {
	case .Null:
		return true
	case .D3D12:
		return d3d12_begin_event(ctx, name)
	case .Vulkan:
		return true
	case .Auto:
	}
	return false
}

backend_end_event :: proc(ctx: ^Context) -> bool {
	switch ctx.backend {
	case .Null:
		return true
	case .D3D12:
		return d3d12_end_event(ctx)
	case .Vulkan:
		return true
	case .Auto:
	}
	return false
}

backend_end_pass :: proc(ctx: ^Context) -> bool {
	switch ctx.backend {
	case .Null:
		return null_end_pass(ctx)
	case .D3D12:
		return d3d12_end_pass(ctx)
	case .Vulkan:
		return vulkan_end_pass(ctx)
	case .Auto:
	}

	return false
}

backend_end_compute_pass :: proc(ctx: ^Context) -> bool {
	switch ctx.backend {
	case .Null:
		return null_end_compute_pass(ctx)
	case .D3D12:
		return d3d12_end_compute_pass(ctx)
	case .Vulkan:
		return vulkan_end_compute_pass(ctx)
	case .Auto:
	}

	return false
}

backend_create_transient_chunk :: proc(ctx: ^Context, role: Transient_Usage, capacity: int, label: string) -> (Buffer, rawptr, bool) {
	switch ctx.backend {
	case .Null:
		return null_create_transient_chunk(ctx, role, capacity, label)
	case .D3D12:
		return d3d12_create_transient_chunk(ctx, role, capacity, label)
	case .Vulkan:
		return vulkan_create_transient_chunk(ctx, role, capacity, label)
	case .Auto:
	}

	return Buffer_Invalid, nil, false
}

backend_destroy_transient_chunk :: proc(ctx: ^Context, buffer: Buffer) {
	switch ctx.backend {
	case .Null:
		null_destroy_transient_chunk(ctx, buffer)
	case .D3D12:
		d3d12_destroy_transient_chunk(ctx, buffer)
	case .Vulkan:
		vulkan_destroy_transient_chunk(ctx, buffer)
	case .Auto:
	}
}

backend_resolve_transient_chunk_mapped :: proc(ctx: ^Context, buffer: Buffer) -> (rawptr, bool) {
	switch ctx.backend {
	case .Null:
		return null_resolve_transient_chunk_mapped(ctx, buffer)
	case .D3D12:
		return d3d12_transient_chunk_ensure_mapped(ctx, buffer)
	case .Vulkan:
		return vulkan_resolve_transient_chunk_mapped(ctx, buffer)
	case .Auto:
	}

	return nil, false
}

backend_reset_transient_chunk :: proc(ctx: ^Context, buffer: Buffer) -> (rawptr, bool) {
	switch ctx.backend {
	case .Null:
		return null_reset_transient_chunk(ctx, buffer)
	case .D3D12:
		return d3d12_reset_transient_chunk(ctx, buffer)
	case .Vulkan:
		return vulkan_reset_transient_chunk(ctx, buffer)
	case .Auto:
	}

	return nil, false
}

backend_barrier :: proc(ctx: ^Context, desc: Barrier_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_barrier(ctx, desc)
	case .D3D12:
		return d3d12_barrier(ctx, desc)
	case .Vulkan:
		return vulkan_barrier(ctx, desc)
	case .Auto:
	}

	return false
}

backend_commit :: proc(ctx: ^Context) -> bool {
	switch ctx.backend {
	case .Null:
		return null_commit(ctx)
	case .D3D12:
		return d3d12_commit(ctx)
	case .Vulkan:
		return vulkan_commit(ctx)
	case .Auto:
	}

	return false
}

backend_gpu_timing_supported :: proc(ctx: ^Context) -> bool {
	switch ctx.backend {
	case .Null:
		return null_gpu_timing_supported(ctx)
	case .D3D12:
		return d3d12_gpu_timing_supported(ctx)
	case .Vulkan:
		return vulkan_gpu_timing_supported(ctx)
	case .Auto:
	}

	return false
}

backend_copy_gpu_timing_samples :: proc(ctx: ^Context, out: []Gpu_Timing_Sample) -> int {
	switch ctx.backend {
	case .Null:
		return null_copy_gpu_timing_samples(ctx, out)
	case .D3D12:
		return d3d12_copy_gpu_timing_samples(ctx, out)
	case .Vulkan:
		return vulkan_copy_gpu_timing_samples(ctx, out)
	case .Auto:
	}

	return 0
}
