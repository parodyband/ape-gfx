#+private
package gfx

Null_State :: struct {
	buffers: map[Buffer]Buffer_State,
	images: map[Image]Image_State,
	views: map[View]View_State,
	transient_chunks: map[Buffer][]u8,
}

null_init :: proc(ctx: ^Context) -> bool {
	state := new(Null_State)
	state.buffers = make(map[Buffer]Buffer_State)
	state.images = make(map[Image]Image_State)
	state.views = make(map[View]View_State)
	state.transient_chunks = make(map[Buffer][]u8)
	ctx.backend_data = state
	return true
}

null_shutdown :: proc(ctx: ^Context) {
	state := null_state(ctx)
	if state == nil {
		return
	}

	for _, bytes in state.transient_chunks {
		delete(bytes)
	}
	delete(state.transient_chunks)
	delete(state.views)
	delete(state.images)
	delete(state.buffers)
	free(state)
	ctx.backend_data = nil
}

null_create_buffer :: proc(ctx: ^Context, handle: Buffer, desc: Buffer_Desc) -> bool {
	state := null_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.null: backend state is not initialized")
		return false
	}

	state.buffers[handle] = {
		valid = true,
		usage = desc.usage,
		size = desc.size,
		storage_stride = desc.storage_stride,
	}
	return true
}

null_destroy_buffer :: proc(ctx: ^Context, handle: Buffer) {
	if state := null_state(ctx); state != nil {
		delete_key(&state.buffers, handle)
	}
}

null_update_buffer :: proc(ctx: ^Context, desc: Buffer_Update_Desc) -> bool {
	return true
}

null_read_buffer :: proc(ctx: ^Context, desc: Buffer_Read_Desc) -> bool {
	return true
}

null_create_image :: proc(ctx: ^Context, handle: Image, desc: Image_Desc) -> bool {
	state := null_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.null: backend state is not initialized")
		return false
	}

	state.images[handle] = {
		valid = true,
		kind = desc.kind,
		usage = desc.usage,
		width = desc.width,
		height = desc.height,
		depth = image_desc_depth(desc),
		mip_count = image_desc_mip_count(desc),
		array_count = image_desc_array_count(desc),
		sample_count = image_desc_sample_count(desc),
		format = desc.format,
	}
	return true
}

null_destroy_image :: proc(ctx: ^Context, handle: Image) {
	if state := null_state(ctx); state != nil {
		delete_key(&state.images, handle)
	}
}

null_update_image :: proc(ctx: ^Context, desc: Image_Update_Desc) -> bool {
	return true
}

null_resolve_image :: proc(ctx: ^Context, desc: Image_Resolve_Desc) -> bool {
	return true
}

null_create_view :: proc(ctx: ^Context, handle: View, desc: View_Desc) -> bool {
	state := null_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.null: backend state is not initialized")
		return false
	}

	kind := view_desc_kind(desc)
	view_state := View_State {
		valid = true,
		kind = kind,
	}
	if kind == .Storage_Buffer {
		buffer_state := state.buffers[desc.storage_buffer.buffer]
		size := desc.storage_buffer.size
		if size == 0 {
			size = buffer_state.size - desc.storage_buffer.offset
		}
		view_state.buffer = desc.storage_buffer.buffer
		view_state.offset = desc.storage_buffer.offset
		view_state.size = size
		view_state.storage_stride = buffer_state.storage_stride
		state.views[handle] = view_state
		return true
	}

	image := view_desc_image(desc)
	image_state := state.images[image]
	format := view_desc_format(desc)
	if format == .Invalid {
		format = image_state.format
	}

	view_state.image = image
	view_state.width = image_state.width
	view_state.height = image_state.height
	view_state.format = format
	view_state.sample_count = image_state.sample_count
	switch kind {
	case .Sampled:
		view_state.mip_level = desc.texture.base_mip
		view_state.base_layer = desc.texture.base_layer
		view_state.layer_count = desc.texture.layer_count
		if view_state.layer_count == 0 {
			view_state.layer_count = image_state.array_count - view_state.base_layer
		}
	case .Storage_Image:
		view_state.mip_level = desc.storage_image.mip_level
		view_state.base_layer = desc.storage_image.base_layer
		view_state.layer_count = desc.storage_image.layer_count
		if view_state.layer_count == 0 {
			view_state.layer_count = image_state.array_count - view_state.base_layer
		}
	case .Color_Attachment:
		view_state.mip_level = desc.color_attachment.mip_level
		view_state.base_layer = desc.color_attachment.layer
		view_state.layer_count = 1
	case .Depth_Stencil_Attachment:
		view_state.mip_level = desc.depth_stencil_attachment.mip_level
		view_state.base_layer = desc.depth_stencil_attachment.layer
		view_state.layer_count = 1
	case .Storage_Buffer:
	}

	state.views[handle] = view_state
	return true
}

null_destroy_view :: proc(ctx: ^Context, handle: View) {
	if state := null_state(ctx); state != nil {
		delete_key(&state.views, handle)
	}
}

null_query_buffer_state :: proc(ctx: ^Context, handle: Buffer) -> Buffer_State {
	state := null_state(ctx)
	if state == nil {
		return {}
	}
	if buffer_state, ok := state.buffers[handle]; ok {
		return buffer_state
	}
	return {}
}

null_query_image_state :: proc(ctx: ^Context, handle: Image) -> Image_State {
	state := null_state(ctx)
	if state == nil {
		return {}
	}
	if image_state, ok := state.images[handle]; ok {
		return image_state
	}
	return {}
}

null_query_view_state :: proc(ctx: ^Context, handle: View) -> View_State {
	state := null_state(ctx)
	if state == nil {
		return {}
	}
	if view_state, ok := state.views[handle]; ok {
		return view_state
	}
	return {}
}

null_query_features :: proc(ctx: ^Context) -> Features {
	return {backend = .Null}
}

null_query_limits :: proc(ctx: ^Context) -> Limits {
	return api_limits()
}

null_create_sampler :: proc(ctx: ^Context, handle: Sampler, desc: Sampler_Desc) -> bool {
	return true
}

null_destroy_sampler :: proc(ctx: ^Context, handle: Sampler) {}

null_create_shader :: proc(ctx: ^Context, handle: Shader, desc: Shader_Desc) -> bool {
	return true
}

null_destroy_shader :: proc(ctx: ^Context, handle: Shader) {}

null_create_pipeline :: proc(ctx: ^Context, handle: Pipeline, desc: Pipeline_Desc) -> bool {
	return true
}

null_destroy_pipeline :: proc(ctx: ^Context, handle: Pipeline) {}

null_create_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline, desc: Compute_Pipeline_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.null: compute is not supported")
	return false
}

null_destroy_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline) {}

null_resize :: proc(ctx: ^Context, width, height: i32) -> bool {
	return true
}

null_begin_pass :: proc(ctx: ^Context, desc: Pass_Desc) -> bool {
	return true
}

null_begin_compute_pass :: proc(ctx: ^Context, desc: Compute_Pass_Desc) -> bool {
	set_unsupported_error(ctx, "gfx.null: compute is not supported")
	return false
}

null_apply_pipeline :: proc(ctx: ^Context, pipeline: Pipeline) -> bool {
	return true
}

null_apply_compute_pipeline :: proc(ctx: ^Context, pipeline: Compute_Pipeline) -> bool {
	set_unsupported_error(ctx, "gfx.null: compute is not supported")
	return false
}

null_apply_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	return true
}

null_barrier :: proc(ctx: ^Context, desc: Barrier_Desc) -> bool {
	return true
}

null_apply_uniforms :: proc(ctx: ^Context, group: u32, slot: int, data: Range) -> bool {
	return true
}

null_apply_uniform_at :: proc(ctx: ^Context, group: u32, slot: int, slice: Transient_Slice, byte_size: int) -> bool {
	return true
}

null_draw :: proc(ctx: ^Context, base_element: i32, num_elements: i32, num_instances: i32) -> bool {
	return true
}

null_dispatch :: proc(ctx: ^Context, group_count_x, group_count_y, group_count_z: u32) -> bool {
	set_unsupported_error(ctx, "gfx.null: compute is not supported")
	return false
}

null_draw_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: u32) -> bool {
	set_unsupported_error(ctx, "gfx.null: draw_indirect is not supported")
	return false
}

null_draw_indexed_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: u32) -> bool {
	set_unsupported_error(ctx, "gfx.null: draw_indexed_indirect is not supported")
	return false
}

null_dispatch_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int) -> bool {
	set_unsupported_error(ctx, "gfx.null: dispatch_indirect is not supported")
	return false
}

null_end_pass :: proc(ctx: ^Context) -> bool {
	return true
}

null_end_compute_pass :: proc(ctx: ^Context) -> bool {
	set_unsupported_error(ctx, "gfx.null: compute is not supported")
	return false
}

null_commit :: proc(ctx: ^Context) -> bool {
	return true
}

null_create_transient_chunk :: proc(ctx: ^Context, role: Transient_Usage, capacity: int, label: string) -> (Buffer, rawptr, bool) {
	state := null_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.null: backend state is not initialized")
		return Buffer_Invalid, nil, false
	}
	if capacity <= 0 {
		return Buffer_Invalid, nil, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.buffer_pool, "gfx.null.transient_chunk")
	if handle_id == 0 {
		return Buffer_Invalid, nil, false
	}
	handle := Buffer(handle_id)

	storage := make([]u8, capacity)
	state.transient_chunks[handle] = storage
	state.buffers[handle] = {
		valid = true,
		size  = capacity,
	}
	return handle, raw_data(storage), true
}

null_destroy_transient_chunk :: proc(ctx: ^Context, buffer: Buffer) {
	state := null_state(ctx)
	if state != nil {
		if storage, ok := state.transient_chunks[buffer]; ok {
			delete(storage)
			delete_key(&state.transient_chunks, buffer)
		}
		delete_key(&state.buffers, buffer)
	}
	release_resource_id(&ctx.buffer_pool, u64(buffer))
}

null_resolve_transient_chunk_mapped :: proc(ctx: ^Context, buffer: Buffer) -> (rawptr, bool) {
	state := null_state(ctx)
	if state == nil {
		return nil, false
	}
	storage, ok := state.transient_chunks[buffer]
	if !ok {
		return nil, false
	}
	return raw_data(storage), true
}

null_reset_transient_chunk :: proc(ctx: ^Context, buffer: Buffer) -> (rawptr, bool) {
	state := null_state(ctx)
	if state == nil {
		return nil, false
	}
	storage, ok := state.transient_chunks[buffer]
	if !ok {
		return nil, false
	}
	return raw_data(storage), true
}

null_state :: proc(ctx: ^Context) -> ^Null_State {
	if ctx == nil || ctx.backend_data == nil {
		return nil
	}

	return cast(^Null_State)ctx.backend_data
}
