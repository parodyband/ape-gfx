package gfx

// range_slice converts a typed slice into a byte Range.
@(private)
range_slice :: proc(data: []$T) -> Range {
	if len(data) == 0 {
		return {}
	}

	return {ptr = raw_data(data), size = len(data) * size_of(T)}
}

// range_fixed_array converts a fixed-array pointer into a byte Range.
@(private)
range_fixed_array :: proc(data: ^[$N]$T) -> Range {
	when N == 0 {
		return {}
	}

	return {ptr = raw_data(data), size = N * size_of(T)}
}

// range_raw builds a byte Range from a raw pointer and byte size.
range_raw :: proc(ptr: rawptr, size: int) -> Range {
	return {ptr = ptr, size = size}
}

// range is an overload group for common upload/readback byte ranges.
range :: proc {
	range_slice,
	range_fixed_array,
	range_raw,
}

// apply_uniform uploads a typed uniform value using size_of(T).
apply_uniform :: proc(ctx: ^Context, group: u32, slot: int, value: ^$T) -> bool {
	return apply_uniforms(ctx, group, slot, range_raw(rawptr(value), size_of(T)))
}

// make_buffer is the Sokol-style handle-only compatibility alias for create_buffer.
make_buffer :: proc(ctx: ^Context, desc: Buffer_Desc) -> Buffer {
	handle, _ := create_buffer(ctx, desc)
	return handle
}

// make_image is the Sokol-style handle-only compatibility alias for create_image.
make_image :: proc(ctx: ^Context, desc: Image_Desc) -> Image {
	handle, _ := create_image(ctx, desc)
	return handle
}

// make_view is the Sokol-style handle-only compatibility alias for create_view.
make_view :: proc(ctx: ^Context, desc: View_Desc) -> View {
	handle, _ := create_view(ctx, desc)
	return handle
}

// make_sampler is the Sokol-style handle-only compatibility alias for create_sampler.
make_sampler :: proc(ctx: ^Context, desc: Sampler_Desc) -> Sampler {
	handle, _ := create_sampler(ctx, desc)
	return handle
}

// make_shader is the Sokol-style handle-only compatibility alias for create_shader.
make_shader :: proc(ctx: ^Context, desc: Shader_Desc) -> Shader {
	handle, _ := create_shader(ctx, desc)
	return handle
}

// make_pipeline is the Sokol-style handle-only compatibility alias for create_pipeline.
make_pipeline :: proc(ctx: ^Context, desc: Pipeline_Desc) -> Pipeline {
	handle, _ := create_pipeline(ctx, desc)
	return handle
}

// make_compute_pipeline is the Sokol-style handle-only compatibility alias for create_compute_pipeline.
make_compute_pipeline :: proc(ctx: ^Context, desc: Compute_Pipeline_Desc) -> Compute_Pipeline {
	handle, _ := create_compute_pipeline(ctx, desc)
	return handle
}

// destroy overloads the explicit destroy_* procedures for all public resource handles.
destroy :: proc {
	destroy_buffer,
	destroy_image,
	destroy_view,
	destroy_sampler,
	destroy_shader,
	destroy_pipeline,
	destroy_compute_pipeline,
	destroy_binding_group_layout,
	destroy_binding_group,
}
