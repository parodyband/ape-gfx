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
	destroy_pipeline_layout,
	destroy_binding_group,
}
