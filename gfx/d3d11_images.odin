#+private
package gfx

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"

d3d11_create_image :: proc(ctx: ^Context, handle: Image, desc: Image_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	if desc.kind != .Image_2D {
		set_unsupported_error(ctx, "gfx.d3d11: only Image_2D is implemented")
		return false
	}
	if !d3d11_validate_image_usage(ctx, desc.usage) {
		return false
	}

	has_depth := .Depth_Stencil_Attachment in desc.usage
	has_color := .Color_Attachment in desc.usage
	has_storage := .Storage_Image in desc.usage
	has_dynamic := d3d11_image_has_dynamic_update(desc.usage)
	has_immutable := .Immutable in desc.usage
	has_mip_data := d3d11_image_desc_has_mip_data(desc)
	if has_depth && !d3d11_is_depth_format(desc.format) {
		set_validation_error(ctx, "gfx.d3d11: depth-stencil images require a depth format")
		return false
	}
	if !has_depth && !d3d11_is_color_format(desc.format) {
		set_validation_error(ctx, "gfx.d3d11: color images require a color format")
		return false
	}

	mip_count := positive_u32_or_default(desc.mip_count, 1)
	array_count := positive_u32_or_default(desc.array_count, 1)
	sample_count := positive_u32_or_default(desc.sample_count, 1)
	if mip_count == 0 || mip_count > MAX_IMAGE_MIPS {
		set_validation_error(ctx, "gfx.d3d11: image mip count is out of range")
		return false
	}
	if array_count != 1 {
		set_validation_error(ctx, "gfx.d3d11: images currently require one layer")
		return false
	}
	if sample_count > 1 {
		if mip_count != 1 {
			set_validation_error(ctx, "gfx.d3d11: multisampled images cannot have mipmaps")
			return false
		}
		if has_storage || has_dynamic || has_immutable || has_mip_data || desc.data.ptr != nil || desc.data.size > 0 {
			set_validation_error(ctx, "gfx.d3d11: multisampled images must be GPU-only render attachments")
			return false
		}
		if !has_color && !has_depth {
			set_validation_error(ctx, "gfx.d3d11: multisampled images must be render attachments")
			return false
		}

		quality_levels: u32
		hr := state.device.CheckMultisampleQualityLevels(
			state.device,
			d3d11_dxgi_format(desc.format),
			sample_count,
			&quality_levels,
		)
		if d3d11_failed(hr) || quality_levels == 0 {
			set_unsupported_error(ctx, "gfx.d3d11: multisample count is not supported for image format")
			return false
		}
	}
	if mip_count > 1 && !has_dynamic && !(has_immutable && has_mip_data) {
		set_validation_error(ctx, "gfx.d3d11: immutable mip chains require explicit mip data")
		return false
	}
	if has_dynamic && desc.data.ptr != nil && mip_count != 1 {
		set_validation_error(ctx, "gfx.d3d11: initial dynamic image data only supports one mip level; use update_image for mip chains")
		return false
	}
	if has_dynamic && has_mip_data {
		set_validation_error(ctx, "gfx.d3d11: dynamic images do not accept initial mip-chain data; use update_image")
		return false
	}

	pixel_size := d3d11_pixel_size(desc.format)
	if pixel_size == 0 {
		set_unsupported_error(ctx, "gfx.d3d11: unsupported image format")
		return false
	}

	if has_immutable && !d3d11_validate_initial_image_data(ctx, desc, mip_count, pixel_size) {
		return false
	}
	if .Color_Attachment in desc.usage && (desc.data.ptr != nil || has_mip_data) {
		set_validation_error(ctx, "gfx.d3d11: color attachment images do not accept initial pixel data yet")
		return false
	}
	if has_storage && (desc.data.ptr != nil || has_mip_data) {
		set_validation_error(ctx, "gfx.d3d11: storage images do not accept initial pixel data yet")
		return false
	}
	if has_depth && (desc.data.ptr != nil || has_mip_data) {
		set_validation_error(ctx, "gfx.d3d11: depth-stencil images do not accept initial data yet")
		return false
	}

	texture_desc := d3d11.TEXTURE2D_DESC {
		Width = u32(desc.width),
		Height = u32(desc.height),
		MipLevels = mip_count,
		ArraySize = array_count,
		Format = d3d11_texture_format(desc.format, desc.usage),
		SampleDesc = dxgi.SAMPLE_DESC{Count = sample_count, Quality = 0},
		Usage = d3d11_image_usage(desc.usage),
		BindFlags = d3d11_image_bind_flags(desc.usage),
		CPUAccessFlags = d3d11_image_cpu_access(desc.usage),
		MiscFlags = {},
	}

	initial_data: [MAX_IMAGE_MIPS]d3d11.SUBRESOURCE_DATA
	initial_data_ptr: ^d3d11.SUBRESOURCE_DATA
	if has_immutable || (has_dynamic && desc.data.ptr != nil) {
		for mip in 0..<int(mip_count) {
			mip_data := d3d11_image_mip_data(desc, mip)
			mip_width := d3d11_mip_dimension(u32(desc.width), u32(mip))
			mip_height := d3d11_mip_dimension(u32(desc.height), u32(mip))
			row_pitch := d3d11_image_mip_row_pitch(mip_data, mip_width, pixel_size)
			slice_pitch := d3d11_image_mip_slice_pitch(mip_data, row_pitch, mip_height)
			initial_data[mip] = d3d11.SUBRESOURCE_DATA {
				pSysMem = mip_data.data.ptr,
				SysMemPitch = row_pitch,
				SysMemSlicePitch = slice_pitch,
			}
		}
		initial_data_ptr = &initial_data[0]
	}

	native_texture: ^d3d11.ITexture2D
	hr := state.device.CreateTexture2D(state.device, &texture_desc, initial_data_ptr, &native_texture)
	if d3d11_failed(hr) {
		d3d11_set_error_hr(ctx, state, "gfx.d3d11: CreateTexture2D failed", hr)
		return false
	}
	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)native_texture, desc.label)

	state.images[handle] = D3D11_Image {
		texture2d = native_texture,
		kind = desc.kind,
		usage = desc.usage,
		width = u32(desc.width),
		height = u32(desc.height),
		mip_count = mip_count,
		array_count = array_count,
		sample_count = sample_count,
		format = desc.format,
	}
	return true
}

d3d11_destroy_image :: proc(ctx: ^Context, handle: Image) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if image_info, ok := state.images[handle]; ok {
		if image_info.texture2d != nil {
			image_info.texture2d.Release(image_info.texture2d)
		}
		delete_key(&state.images, handle)
	}
}

d3d11_update_image :: proc(ctx: ^Context, desc: Image_Update_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	image_info, image_ok := state.images[desc.image]
	if !image_ok || image_info.texture2d == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: image handle is unknown")
		return false
	}
	if !d3d11_image_has_dynamic_update(image_info.usage) {
		set_validation_error(ctx, "gfx.d3d11: update_image requires a dynamic image")
		return false
	}
	if image_info.kind != .Image_2D {
		set_validation_error(ctx, "gfx.d3d11: update_image only supports Image_2D")
		return false
	}
	if !d3d11_is_color_format(image_info.format) {
		set_validation_error(ctx, "gfx.d3d11: update_image only supports color images")
		return false
	}

	mip_level := u32(desc.mip_level)
	array_layer := u32(desc.array_layer)
	if mip_level >= image_info.mip_count || array_layer >= image_info.array_count {
		set_validation_error(ctx, "gfx.d3d11: image update subresource is out of range")
		return false
	}

	mip_width := d3d11_mip_dimension(image_info.width, mip_level)
	mip_height := d3d11_mip_dimension(image_info.height, mip_level)
	update_width := u32(desc.width)
	update_height := u32(desc.height)
	if desc.width <= 0 {
		update_width = mip_width
	}
	if desc.height <= 0 {
		update_height = mip_height
	}

	if u32(desc.x) + update_width > mip_width || u32(desc.y) + update_height > mip_height {
		set_validation_error(ctx, "gfx.d3d11: image update rectangle is out of range")
		return false
	}
	pixel_size := d3d11_pixel_size(image_info.format)
	row_pitch := u32(desc.row_pitch)
	if desc.row_pitch <= 0 {
		row_pitch = update_width * pixel_size
	}
	min_row_pitch := update_width * pixel_size
	if row_pitch < min_row_pitch {
		set_validation_error(ctx, "gfx.d3d11: image update row pitch is too small")
		return false
	}
	required_size := int(row_pitch) * int(update_height - 1) + int(min_row_pitch)
	if desc.data.size < required_size {
		set_validation_error(ctx, "gfx.d3d11: image update data range is too small")
		return false
	}

	null_srvs: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	state.immediate.VSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	state.immediate.PSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])

	subresource := array_layer * image_info.mip_count + mip_level
	update_box := d3d11.BOX {
		left = u32(desc.x),
		top = u32(desc.y),
		front = 0,
		right = u32(desc.x) + update_width,
		bottom = u32(desc.y) + update_height,
		back = 1,
	}
	state.immediate.UpdateSubresource(
		state.immediate,
		cast(^d3d11.IResource)image_info.texture2d,
		subresource,
		&update_box,
		desc.data.ptr,
		row_pitch,
		row_pitch * update_height,
	)
	return true
}

d3d11_resolve_image :: proc(ctx: ^Context, desc: Image_Resolve_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	source_info, source_ok := state.images[desc.source]
	if !source_ok || source_info.texture2d == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: resolve source image handle is unknown")
		return false
	}
	destination_info, destination_ok := state.images[desc.destination]
	if !destination_ok || destination_info.texture2d == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: resolve destination image handle is unknown")
		return false
	}
	if source_info.sample_count <= 1 || destination_info.sample_count != 1 {
		set_validation_error(ctx, "gfx.d3d11: resolve requires multisampled source and single-sampled destination")
		return false
	}
	if source_info.format != destination_info.format ||
	   source_info.width != destination_info.width ||
	   source_info.height != destination_info.height {
		set_validation_error(ctx, "gfx.d3d11: resolve source and destination must have matching format and dimensions")
		return false
	}
	if !d3d11_is_color_format(source_info.format) {
		set_unsupported_error(ctx, "gfx.d3d11: only color image resolves are supported")
		return false
	}

	null_srvs: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	state.immediate.VSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	state.immediate.PSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	d3d11_clear_compute_resource_bindings(state)

	state.immediate.ResolveSubresource(
		state.immediate,
		cast(^d3d11.IResource)destination_info.texture2d,
		0,
		cast(^d3d11.IResource)source_info.texture2d,
		0,
		d3d11_dxgi_format(source_info.format),
	)
	return d3d11_drain_info_queue(ctx, state, "ResolveSubresource")
}

d3d11_query_image_state :: proc(ctx: ^Context, handle: Image) -> Image_State {
	state := d3d11_state(ctx)
	if state == nil {
		return {}
	}

	if image_info, ok := state.images[handle]; ok {
		return {
			valid = image_info.texture2d != nil,
			kind = image_info.kind,
			usage = image_info.usage,
			width = i32(image_info.width),
			height = i32(image_info.height),
			depth = 1,
			mip_count = i32(image_info.mip_count),
			array_count = i32(image_info.array_count),
			sample_count = i32(image_info.sample_count),
			format = image_info.format,
		}
	}

	return {}
}

d3d11_validate_image_usage :: proc(ctx: ^Context, usage: Image_Usage) -> bool {
	if usage == {} {
		set_validation_error(ctx, "gfx.d3d11: image usage must not be empty")
		return false
	}

	has_texture := .Texture in usage
	has_storage := .Storage_Image in usage
	has_color := .Color_Attachment in usage
	has_depth := .Depth_Stencil_Attachment in usage
	has_immutable := .Immutable in usage
	has_dynamic := d3d11_image_has_dynamic_update(usage)

	if !has_texture && !has_storage && !has_color && !has_depth {
		set_validation_error(ctx, "gfx.d3d11: image usage must include texture, storage image, color attachment, or depth-stencil attachment")
		return false
	}
	if has_color && has_depth {
		set_validation_error(ctx, "gfx.d3d11: image usage cannot combine color and depth-stencil attachments")
		return false
	}
	if has_storage && has_depth {
		set_validation_error(ctx, "gfx.d3d11: storage images cannot use depth-stencil formats")
		return false
	}
	if has_immutable && (has_storage || has_color || has_depth || has_dynamic) {
		set_validation_error(ctx, "gfx.d3d11: immutable images must be texture-only for now")
		return false
	}
	if has_dynamic && !has_texture {
		set_validation_error(ctx, "gfx.d3d11: dynamic image updates require texture usage")
		return false
	}
	if has_dynamic && (has_storage || has_color || has_depth) {
		set_unsupported_error(ctx, "gfx.d3d11: dynamic storage or attachment images are not implemented yet")
		return false
	}
	if .Dynamic_Update in usage && .Stream_Update in usage {
		set_validation_error(ctx, "gfx.d3d11: image usage has conflicting update flags")
		return false
	}

	return true
}

d3d11_image_usage :: proc(usage: Image_Usage) -> d3d11.USAGE {
	if .Immutable in usage {
		return .IMMUTABLE
	}

	return .DEFAULT
}

d3d11_image_cpu_access :: proc(usage: Image_Usage) -> d3d11.CPU_ACCESS_FLAGS {
	return {}
}

d3d11_image_bind_flags :: proc(usage: Image_Usage) -> d3d11.BIND_FLAGS {
	flags: d3d11.BIND_FLAGS
	if .Texture in usage {
		flags += {.SHADER_RESOURCE}
	}
	if .Color_Attachment in usage {
		flags += {.RENDER_TARGET}
	}
	if .Depth_Stencil_Attachment in usage {
		flags += {.DEPTH_STENCIL}
	}
	if .Storage_Image in usage {
		flags += {.UNORDERED_ACCESS}
	}

	return flags
}

d3d11_image_has_dynamic_update :: proc(usage: Image_Usage) -> bool {
	return .Dynamic_Update in usage || .Stream_Update in usage
}

d3d11_image_desc_has_mip_data :: proc(desc: Image_Desc) -> bool {
	for mip_data in desc.mips {
		if mip_data.data.ptr != nil || mip_data.data.size > 0 {
			return true
		}
	}

	return false
}

d3d11_image_mip_data :: proc(desc: Image_Desc, mip: int) -> Image_Subresource_Data {
	mip_data := desc.mips[mip]
	if mip == 0 && mip_data.data.ptr == nil && mip_data.data.size <= 0 {
		mip_data.data = desc.data
	}

	return mip_data
}

d3d11_validate_initial_image_data :: proc(ctx: ^Context, desc: Image_Desc, mip_count, pixel_size: u32) -> bool {
	for mip in 0..<int(mip_count) {
		mip_data := d3d11_image_mip_data(desc, mip)
		if mip_data.data.ptr == nil || mip_data.data.size <= 0 {
			set_validation_errorf(ctx, "gfx.d3d11: immutable image mip %d requires initial pixel data", mip)
			return false
		}

		mip_width := d3d11_mip_dimension(u32(desc.width), u32(mip))
		mip_height := d3d11_mip_dimension(u32(desc.height), u32(mip))
		row_pitch := d3d11_image_mip_row_pitch(mip_data, mip_width, pixel_size)
		min_row_pitch := mip_width * pixel_size
		if row_pitch < min_row_pitch {
			set_validation_errorf(ctx, "gfx.d3d11: immutable image mip %d row pitch is too small", mip)
			return false
		}

		required_size := int(row_pitch) * int(mip_height - 1) + int(min_row_pitch)
		if mip_data.data.size < required_size {
			set_validation_errorf(ctx, "gfx.d3d11: immutable image mip %d data range is too small", mip)
			return false
		}
	}

	return true
}

d3d11_image_mip_row_pitch :: proc(mip_data: Image_Subresource_Data, width, pixel_size: u32) -> u32 {
	if mip_data.row_pitch > 0 {
		return u32(mip_data.row_pitch)
	}

	return width * pixel_size
}

d3d11_image_mip_slice_pitch :: proc(mip_data: Image_Subresource_Data, row_pitch, height: u32) -> u32 {
	if mip_data.slice_pitch > 0 {
		return u32(mip_data.slice_pitch)
	}

	return row_pitch * height
}
