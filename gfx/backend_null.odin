#+private
package gfx

Null_State :: struct {
	buffers: map[Buffer]Buffer_State,
	images: map[Image]Image_State,
	views: map[View]View_State,
}

backend_init :: proc(ctx: ^Context) -> bool {
	switch ctx.backend {
	case .Null:
		return null_init(ctx)
	case .D3D11:
		return d3d11_init(ctx)
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
	case .D3D11:
		d3d11_shutdown(ctx)
	case .Vulkan:
		vulkan_shutdown(ctx)
	case .Auto:
	}
}

backend_create_buffer :: proc(ctx: ^Context, handle: Buffer, desc: Buffer_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_create_buffer(ctx, handle, desc)
	case .D3D11:
		return d3d11_create_buffer(ctx, handle, desc)
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
	case .D3D11:
		d3d11_destroy_buffer(ctx, handle)
	case .Vulkan:
		vulkan_destroy_buffer(ctx, handle)
	case .Auto:
	}
}

backend_update_buffer :: proc(ctx: ^Context, desc: Buffer_Update_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_update_buffer(ctx, desc)
	case .D3D11:
		return d3d11_update_buffer(ctx, desc)
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
	case .D3D11:
		return d3d11_read_buffer(ctx, desc)
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
	case .D3D11:
		return d3d11_create_image(ctx, handle, desc)
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
	case .D3D11:
		d3d11_destroy_image(ctx, handle)
	case .Vulkan:
		vulkan_destroy_image(ctx, handle)
	case .Auto:
	}
}

backend_update_image :: proc(ctx: ^Context, desc: Image_Update_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_update_image(ctx, desc)
	case .D3D11:
		return d3d11_update_image(ctx, desc)
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
	case .D3D11:
		return d3d11_resolve_image(ctx, desc)
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
	case .D3D11:
		return d3d11_create_view(ctx, handle, desc)
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
	case .D3D11:
		d3d11_destroy_view(ctx, handle)
	case .Vulkan:
		vulkan_destroy_view(ctx, handle)
	case .Auto:
	}
}

backend_query_buffer_state :: proc(ctx: ^Context, handle: Buffer) -> Buffer_State {
	switch ctx.backend {
	case .Null:
		return null_query_buffer_state(ctx, handle)
	case .D3D11:
		return d3d11_query_buffer_state(ctx, handle)
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
	case .D3D11:
		return d3d11_query_image_state(ctx, handle)
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
	case .D3D11:
		return d3d11_query_view_state(ctx, handle)
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
	case .D3D11:
		return d3d11_query_features(ctx)
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
	case .D3D11:
		return d3d11_query_limits(ctx)
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
	case .D3D11:
		return d3d11_create_sampler(ctx, handle, desc)
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
	case .D3D11:
		d3d11_destroy_sampler(ctx, handle)
	case .Vulkan:
		vulkan_destroy_sampler(ctx, handle)
	case .Auto:
	}
}

backend_create_shader :: proc(ctx: ^Context, handle: Shader, desc: Shader_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_create_shader(ctx, handle, desc)
	case .D3D11:
		return d3d11_create_shader(ctx, handle, desc)
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
	case .D3D11:
		d3d11_destroy_shader(ctx, handle)
	case .Vulkan:
		vulkan_destroy_shader(ctx, handle)
	case .Auto:
	}
}

backend_create_pipeline :: proc(ctx: ^Context, handle: Pipeline, desc: Pipeline_Desc) -> bool {
	switch ctx.backend {
	case .Null:
		return null_create_pipeline(ctx, handle, desc)
	case .D3D11:
		return d3d11_create_pipeline(ctx, handle, desc)
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
	case .D3D11:
		return d3d11_create_compute_pipeline(ctx, handle, desc)
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
	case .D3D11:
		d3d11_destroy_pipeline(ctx, handle)
	case .Vulkan:
		vulkan_destroy_pipeline(ctx, handle)
	case .Auto:
	}
}

backend_destroy_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline) {
	switch ctx.backend {
	case .Null:
		null_destroy_compute_pipeline(ctx, handle)
	case .D3D11:
		d3d11_destroy_compute_pipeline(ctx, handle)
	case .Vulkan:
		vulkan_destroy_compute_pipeline(ctx, handle)
	case .Auto:
	}
}

backend_resize :: proc(ctx: ^Context, width, height: i32) -> bool {
	switch ctx.backend {
	case .Null:
		return null_resize(ctx, width, height)
	case .D3D11:
		return d3d11_resize(ctx, width, height)
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
	case .D3D11:
		return d3d11_begin_pass(ctx, desc)
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
	case .D3D11:
		return d3d11_begin_compute_pass(ctx, desc)
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
	case .D3D11:
		return d3d11_apply_pipeline(ctx, pipeline)
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
	case .D3D11:
		return d3d11_apply_compute_pipeline(ctx, pipeline)
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
	case .D3D11:
		return d3d11_apply_bindings(ctx, bindings)
	case .Vulkan:
		return vulkan_apply_bindings(ctx, bindings)
	case .Auto:
	}

	return false
}

backend_apply_uniforms :: proc(ctx: ^Context, slot: int, data: Range) -> bool {
	switch ctx.backend {
	case .Null:
		return null_apply_uniforms(ctx, slot, data)
	case .D3D11:
		return d3d11_apply_uniforms(ctx, slot, data)
	case .Vulkan:
		return vulkan_apply_uniforms(ctx, slot, data)
	case .Auto:
	}

	return false
}

backend_draw :: proc(ctx: ^Context, base_element: i32, num_elements: i32, num_instances: i32) -> bool {
	switch ctx.backend {
	case .Null:
		return null_draw(ctx, base_element, num_elements, num_instances)
	case .D3D11:
		return d3d11_draw(ctx, base_element, num_elements, num_instances)
	case .Vulkan:
		return vulkan_draw(ctx, base_element, num_elements, num_instances)
	case .Auto:
	}

	return false
}

backend_dispatch :: proc(ctx: ^Context, group_count_x, group_count_y, group_count_z: u32) -> bool {
	switch ctx.backend {
	case .Null:
		return null_dispatch(ctx, group_count_x, group_count_y, group_count_z)
	case .D3D11:
		return d3d11_dispatch(ctx, group_count_x, group_count_y, group_count_z)
	case .Vulkan:
		return vulkan_dispatch(ctx, group_count_x, group_count_y, group_count_z)
	case .Auto:
	}

	return false
}

backend_end_pass :: proc(ctx: ^Context) -> bool {
	switch ctx.backend {
	case .Null:
		return null_end_pass(ctx)
	case .D3D11:
		return d3d11_end_pass(ctx)
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
	case .D3D11:
		return d3d11_end_compute_pass(ctx)
	case .Vulkan:
		return vulkan_end_compute_pass(ctx)
	case .Auto:
	}

	return false
}

backend_commit :: proc(ctx: ^Context) -> bool {
	switch ctx.backend {
	case .Null:
		return null_commit(ctx)
	case .D3D11:
		return d3d11_commit(ctx)
	case .Vulkan:
		return vulkan_commit(ctx)
	case .Auto:
	}

	return false
}

null_init :: proc(ctx: ^Context) -> bool {
	state := new(Null_State)
	state.buffers = make(map[Buffer]Buffer_State)
	state.images = make(map[Image]Image_State)
	state.views = make(map[View]View_State)
	ctx.backend_data = state
	return true
}

null_shutdown :: proc(ctx: ^Context) {
	state := null_state(ctx)
	if state == nil {
		return
	}

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

null_apply_uniforms :: proc(ctx: ^Context, slot: int, data: Range) -> bool {
	return true
}

null_draw :: proc(ctx: ^Context, base_element: i32, num_elements: i32, num_instances: i32) -> bool {
	return true
}

null_dispatch :: proc(ctx: ^Context, group_count_x, group_count_y, group_count_z: u32) -> bool {
	set_unsupported_error(ctx, "gfx.null: compute is not supported")
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

null_state :: proc(ctx: ^Context) -> ^Null_State {
	if ctx == nil || ctx.backend_data == nil {
		return nil
	}

	return cast(^Null_State)ctx.backend_data
}
