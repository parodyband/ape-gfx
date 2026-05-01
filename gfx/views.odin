package gfx

// create_view creates one sampled, storage, color, or depth-stencil view.
// On failure, the returned handle is View_Invalid and last_error explains why.
create_view :: proc(ctx: ^Context, desc: View_Desc) -> (View, bool) {
	if !require_initialized(ctx, "gfx.create_view") {
		return View_Invalid, false
	}

	if view_desc_active_count(desc) != 1 {
		set_validation_error(ctx, "gfx.create_view: exactly one view flavor must be specified")
		return View_Invalid, false
	}

	if !validate_view_desc_resource(ctx, desc) {
		return View_Invalid, false
	}

	kind := view_desc_kind(desc)
	features := backend_query_features(ctx)
	if kind == .Storage_Image && !features.storage_images {
		set_unsupported_error(ctx, "gfx.create_view: backend does not support storage image views")
		return View_Invalid, false
	}
	if kind == .Storage_Buffer && !features.storage_buffers {
		set_unsupported_error(ctx, "gfx.create_view: backend does not support storage buffer views")
		return View_Invalid, false
	}
	if image := view_desc_image(desc); image_valid(image) {
		image_state := query_image_state(ctx, image)
		if image_state.valid && image_state.sample_count > 1 {
			if kind == .Sampled {
				set_validation_error(ctx, "gfx.create_view: multisampled images cannot use sampled views yet; resolve into a single-sampled texture")
				return View_Invalid, false
			}
			if kind == .Storage_Image {
				set_unsupported_error(ctx, "gfx.create_view: multisampled storage image views are not supported")
				return View_Invalid, false
			}
		}
	}
	if !validate_view_desc_shape(ctx, desc, kind) {
		return View_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.view_pool, "gfx.create_view")
	if handle_id == 0 {
		return View_Invalid, false
	}

	handle := View(handle_id)
	if !backend_create_view(ctx, handle, desc) {
		cancel_resource_id(&ctx.view_pool, handle_id)
		return View_Invalid, false
	}

	return handle, true
}

// destroy_view releases a live view handle.
destroy_view :: proc(ctx: ^Context, view: View) {
	if !require_initialized(ctx, "gfx.destroy_view") {
		return
	}
	if !require_resource(ctx, &ctx.view_pool, u64(view), "gfx.destroy_view", "view") {
		return
	}
	if message := view_blocked_from_destroy(ctx, view); message != "" {
		set_validation_error(ctx, message)
		return
	}

	backend_destroy_view(ctx, view)
	release_resource_id(&ctx.view_pool, u64(view))
}

// query_view_state returns read-only state for a live view, or zero if invalid.
query_view_state :: proc(ctx: ^Context, view: View) -> View_State {
	if ctx == nil || !ctx.initialized || !resource_id_alive(ctx, &ctx.view_pool, u64(view)) {
		return {}
	}

	return backend_query_view_state(ctx, view)
}

// query_view_image returns the parent image for image-backed views.
query_view_image :: proc(ctx: ^Context, view: View) -> Image {
	view_state := query_view_state(ctx, view)
	return view_state.image
}

// query_view_buffer returns the parent buffer for storage-buffer views.
query_view_buffer :: proc(ctx: ^Context, view: View) -> Buffer {
	view_state := query_view_state(ctx, view)
	return view_state.buffer
}

// query_view_compatible reports whether a view is live and has the requested kind.
query_view_compatible :: proc(ctx: ^Context, view: View, kind: View_Kind) -> bool {
	view_state := query_view_state(ctx, view)
	return view_state.valid && view_state.kind == kind
}

@(private)
validate_view_desc_shape :: proc(ctx: ^Context, desc: View_Desc, kind: View_Kind) -> bool {
	switch kind {
	case .Storage_Buffer:
		return validate_storage_buffer_view_desc(ctx, desc.storage_buffer)
	case .Sampled, .Storage_Image, .Color_Attachment, .Depth_Stencil_Attachment:
		return validate_image_view_desc(ctx, desc, kind)
	}

	return true
}

@(private)
validate_storage_buffer_view_desc :: proc(ctx: ^Context, desc: Storage_Buffer_View_Desc) -> bool {
	buffer_state := query_buffer_state(ctx, desc.buffer)
	if !buffer_state.valid {
		set_invalid_handle_error(ctx, "gfx.create_view: storage buffer handle is invalid")
		return false
	}
	if !(.Storage in buffer_state.usage) {
		set_validation_error(ctx, "gfx.create_view: storage buffer views require a storage-capable buffer")
		return false
	}
	if desc.offset < 0 {
		set_validation_error(ctx, "gfx.create_view: storage buffer view offset must be non-negative")
		return false
	}

	size := desc.size
	if size == 0 {
		size = buffer_state.size - desc.offset
	}
	if size <= 0 || desc.offset > buffer_state.size || size > buffer_state.size - desc.offset {
		set_validation_error(ctx, "gfx.create_view: storage buffer view range is invalid")
		return false
	}
	if buffer_state.storage_stride > 0 {
		stride := buffer_state.storage_stride
		if desc.offset % stride != 0 || size % stride != 0 {
			set_validation_error(ctx, "gfx.create_view: structured storage buffer view offset and size must align to storage_stride")
			return false
		}
	} else if desc.offset % 4 != 0 || size % 4 != 0 {
		set_validation_error(ctx, "gfx.create_view: raw storage buffer view offset and size must be 4-byte aligned")
		return false
	}

	return true
}

@(private)
validate_image_view_desc :: proc(ctx: ^Context, desc: View_Desc, kind: View_Kind) -> bool {
	image := view_desc_image(desc)
	image_state := query_image_state(ctx, image)
	if !image_state.valid {
		set_invalid_handle_error(ctx, "gfx.create_view: image handle is invalid")
		return false
	}

	format := view_desc_format(desc)
	if format == .Invalid {
		format = image_state.format
	}
	if format != image_state.format {
		set_validation_error(ctx, "gfx.create_view: view format must match image format for now")
		return false
	}

	base_mip: i32
	mip_count: i32
	base_layer: i32
	layer_count: i32
	switch kind {
	case .Sampled:
		if desc.texture.base_mip < 0 || desc.texture.mip_count < 0 || desc.texture.base_layer < 0 || desc.texture.layer_count < 0 {
			set_validation_error(ctx, "gfx.create_view: texture view mip and layer ranges must be non-negative")
			return false
		}
		base_mip = desc.texture.base_mip
		mip_count = desc.texture.mip_count
		if mip_count == 0 {
			mip_count = image_state.mip_count - base_mip
		}
		base_layer = desc.texture.base_layer
		layer_count = desc.texture.layer_count
		if layer_count == 0 {
			layer_count = image_state.array_count - base_layer
		}
	case .Storage_Image:
		if desc.storage_image.mip_level < 0 || desc.storage_image.base_layer < 0 || desc.storage_image.layer_count < 0 {
			set_validation_error(ctx, "gfx.create_view: storage image view mip and layer ranges must be non-negative")
			return false
		}
		base_mip = desc.storage_image.mip_level
		mip_count = 1
		base_layer = desc.storage_image.base_layer
		layer_count = desc.storage_image.layer_count
		if layer_count == 0 {
			layer_count = image_state.array_count - base_layer
		}
	case .Color_Attachment:
		if desc.color_attachment.mip_level < 0 || desc.color_attachment.layer < 0 {
			set_validation_error(ctx, "gfx.create_view: color attachment view mip and layer must be non-negative")
			return false
		}
		base_mip = desc.color_attachment.mip_level
		mip_count = 1
		base_layer = desc.color_attachment.layer
		layer_count = 1
	case .Depth_Stencil_Attachment:
		if desc.depth_stencil_attachment.mip_level < 0 || desc.depth_stencil_attachment.layer < 0 {
			set_validation_error(ctx, "gfx.create_view: depth-stencil attachment view mip and layer must be non-negative")
			return false
		}
		base_mip = desc.depth_stencil_attachment.mip_level
		mip_count = 1
		base_layer = desc.depth_stencil_attachment.layer
		layer_count = 1
	case .Storage_Buffer:
		return true
	}

	if mip_count <= 0 || layer_count <= 0 {
		set_validation_error(ctx, "gfx.create_view: view range is empty")
		return false
	}
	if base_mip >= image_state.mip_count || base_mip + mip_count > image_state.mip_count {
		set_validation_error(ctx, "gfx.create_view: view mip range is invalid")
		return false
	}
	if base_layer >= image_state.array_count || base_layer + layer_count > image_state.array_count {
		set_validation_error(ctx, "gfx.create_view: view layer range is invalid")
		return false
	}

	switch kind {
	case .Sampled:
		if !(.Texture in image_state.usage) {
			set_validation_error(ctx, "gfx.create_view: sampled views require a Texture image")
			return false
		}
		if image_state.sample_count > 1 {
			set_validation_error(ctx, "gfx.create_view: multisampled images cannot use sampled views yet; resolve into a single-sampled texture")
			return false
		}
	case .Storage_Image:
		if !(.Storage_Image in image_state.usage) {
			set_validation_error(ctx, "gfx.create_view: storage image views require a storage-capable image")
			return false
		}
		if image_state.sample_count > 1 {
			set_unsupported_error(ctx, "gfx.create_view: multisampled storage image views are not supported")
			return false
		}
		if pixel_format_is_depth(format) {
			set_unsupported_error(ctx, "gfx.create_view: depth storage image views are not supported")
			return false
		}
	case .Color_Attachment:
		if !(.Color_Attachment in image_state.usage) {
			set_validation_error(ctx, "gfx.create_view: color attachment views require a color attachment image")
			return false
		}
	case .Depth_Stencil_Attachment:
		if !(.Depth_Stencil_Attachment in image_state.usage) {
			set_validation_error(ctx, "gfx.create_view: depth-stencil attachment views require a depth-stencil image")
			return false
		}
	case .Storage_Buffer:
	}

	return true
}

@(private)
view_state_aliases_active_pass_attachment :: proc(ctx: ^Context, view_state: View_State) -> bool {
	if ctx == nil {
		return false
	}

	for attachment in ctx.pass_color_attachments {
		if !view_valid(attachment) {
			continue
		}

		attachment_state := query_view_state(ctx, attachment)
		if attachment_state.valid && view_states_alias_resource(view_state, attachment_state) {
			return true
		}
	}

	if view_valid(ctx.pass_depth_stencil_attachment) {
		attachment_state := query_view_state(ctx, ctx.pass_depth_stencil_attachment)
		if attachment_state.valid && view_states_alias_resource(view_state, attachment_state) {
			return true
		}
	}

	return false
}

@(private)
view_states_alias_resource :: proc(a, b: View_State) -> bool {
	if image_valid(a.image) || image_valid(b.image) {
		return image_valid(a.image) && image_valid(b.image) && a.image == b.image
	}

	if buffer_valid(a.buffer) || buffer_valid(b.buffer) {
		if !buffer_valid(a.buffer) || !buffer_valid(b.buffer) || a.buffer != b.buffer {
			return false
		}

		if a.size <= 0 || b.size <= 0 {
			return true
		}

		a_start := a.offset
		a_end := a.offset + a.size
		b_start := b.offset
		b_end := b.offset + b.size
		return a_start < b_end && b_start < a_end
	}

	return false
}

@(private)
view_state_reads_resource :: proc(view_state: View_State) -> bool {
	switch view_state.kind {
	case .Sampled:
		return true
	case .Storage_Image, .Storage_Buffer, .Color_Attachment, .Depth_Stencil_Attachment:
		return false
	}

	return false
}

@(private)
view_state_writes_resource :: proc(view_state: View_State) -> bool {
	switch view_state.kind {
	case .Storage_Image, .Storage_Buffer, .Color_Attachment, .Depth_Stencil_Attachment:
		return true
	case .Sampled:
		return false
	}

	return false
}

@(private)
view_desc_active_count :: proc(desc: View_Desc) -> int {
	count := 0
	if image_valid(desc.texture.image) {
		count += 1
	}
	if image_valid(desc.storage_image.image) {
		count += 1
	}
	if buffer_valid(desc.storage_buffer.buffer) {
		count += 1
	}
	if image_valid(desc.color_attachment.image) {
		count += 1
	}
	if image_valid(desc.depth_stencil_attachment.image) {
		count += 1
	}

	return count
}

@(private)
validate_view_desc_resource :: proc(ctx: ^Context, desc: View_Desc) -> bool {
	if buffer_valid(desc.storage_buffer.buffer) {
		return require_resource(ctx, &ctx.buffer_pool, u64(desc.storage_buffer.buffer), "gfx.create_view", "buffer")
	}

	image := view_desc_image(desc)
	if image_valid(image) {
		return require_resource(ctx, &ctx.image_pool, u64(image), "gfx.create_view", "image")
	}

	set_invalid_handle_error(ctx, "gfx.create_view: view resource handle is invalid")
	return false
}

@(private)
view_desc_image :: proc(desc: View_Desc) -> Image {
	if image_valid(desc.texture.image) {
		return desc.texture.image
	}
	if image_valid(desc.storage_image.image) {
		return desc.storage_image.image
	}
	if image_valid(desc.color_attachment.image) {
		return desc.color_attachment.image
	}
	if image_valid(desc.depth_stencil_attachment.image) {
		return desc.depth_stencil_attachment.image
	}

	return Image_Invalid
}

@(private)
view_desc_buffer :: proc(desc: View_Desc) -> Buffer {
	if buffer_valid(desc.storage_buffer.buffer) {
		return desc.storage_buffer.buffer
	}

	return Buffer_Invalid
}

@(private)
view_desc_kind :: proc(desc: View_Desc) -> View_Kind {
	if image_valid(desc.storage_image.image) {
		return .Storage_Image
	}
	if buffer_valid(desc.storage_buffer.buffer) {
		return .Storage_Buffer
	}
	if image_valid(desc.color_attachment.image) {
		return .Color_Attachment
	}
	if image_valid(desc.depth_stencil_attachment.image) {
		return .Depth_Stencil_Attachment
	}

	return .Sampled
}

@(private)
view_desc_format :: proc(desc: View_Desc) -> Pixel_Format {
	if image_valid(desc.texture.image) {
		return desc.texture.format
	}
	if image_valid(desc.storage_image.image) {
		return desc.storage_image.format
	}
	if image_valid(desc.color_attachment.image) {
		return desc.color_attachment.format
	}
	if image_valid(desc.depth_stencil_attachment.image) {
		return desc.depth_stencil_attachment.format
	}

	return .Invalid
}
