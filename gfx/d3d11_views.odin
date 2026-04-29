#+private
package gfx

import d3d11 "vendor:directx/d3d11"

d3d11_create_view :: proc(ctx: ^Context, handle: View, desc: View_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	kind := view_desc_kind(desc)
	if kind == .Storage_Buffer {
		buffer := view_desc_buffer(desc)
		buffer_info, buffer_ok := state.buffers[buffer]
		if !buffer_ok || buffer_info.buffer == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: storage buffer view handle is unknown")
			return false
		}
		if !(.Storage in buffer_info.usage) {
			set_validation_error(ctx, "gfx.d3d11: storage buffer views require a storage-capable buffer")
			return false
		}
		if desc.storage_buffer.offset < 0 {
			set_validation_error(ctx, "gfx.d3d11: storage buffer view offset must be non-negative")
			return false
		}

		offset := desc.storage_buffer.offset
		size := desc.storage_buffer.size
		if size == 0 {
			size = int(buffer_info.size) - offset
		}
		if size <= 0 || offset > int(buffer_info.size) || size > int(buffer_info.size) - offset {
			set_validation_error(ctx, "gfx.d3d11: storage buffer view range is invalid")
			return false
		}
		if buffer_info.storage_stride > 0 {
			stride := int(buffer_info.storage_stride)
			if offset % stride != 0 || size % stride != 0 {
				set_validation_error(ctx, "gfx.d3d11: structured storage buffer view offset and size must align to storage_stride")
				return false
			}
		} else {
			if offset % 4 != 0 || size % 4 != 0 {
				set_validation_error(ctx, "gfx.d3d11: raw storage buffer view offset and size must be 4-byte aligned")
				return false
			}
		}

		view_info := D3D11_View {
			buffer = buffer,
			kind = kind,
			offset = offset,
			size = size,
			storage_stride = buffer_info.storage_stride,
		}

		srv_desc: d3d11.SHADER_RESOURCE_VIEW_DESC
		uav_desc: d3d11.UNORDERED_ACCESS_VIEW_DESC
		if buffer_info.storage_stride > 0 {
			stride := int(buffer_info.storage_stride)
			first_element := u32(offset / stride)
			element_count := u32(size / stride)
			srv_desc = {
				Format = .UNKNOWN,
				ViewDimension = .BUFFER,
				Buffer = d3d11.BUFFER_SRV {
					FirstElement = first_element,
					NumElements = element_count,
				},
			}
			uav_desc = {
				Format = .UNKNOWN,
				ViewDimension = .BUFFER,
				Buffer = d3d11.BUFFER_UAV {
					FirstElement = first_element,
					NumElements = element_count,
					Flags = {},
				},
			}
		} else {
			first_element := u32(offset / 4)
			element_count := u32(size / 4)
			srv_desc = {
				Format = .R32_TYPELESS,
				ViewDimension = .BUFFEREX,
				BufferEx = d3d11.BUFFEREX_SRV {
					FirstElement = first_element,
					NumElements = element_count,
					Flags = {.RAW},
				},
			}
			uav_desc = {
				Format = .R32_TYPELESS,
				ViewDimension = .BUFFER,
				Buffer = d3d11.BUFFER_UAV {
					FirstElement = first_element,
					NumElements = element_count,
					Flags = {.RAW},
				},
			}
		}

		hr := state.device.CreateShaderResourceView(
			state.device,
			cast(^d3d11.IResource)buffer_info.buffer,
			&srv_desc,
			&view_info.srv,
		)
		if d3d11_failed(hr) {
			set_backend_error(ctx, "gfx.d3d11: CreateShaderResourceView failed for storage buffer")
			return false
		}

		hr = state.device.CreateUnorderedAccessView(
			state.device,
			cast(^d3d11.IResource)buffer_info.buffer,
			&uav_desc,
			&view_info.uav,
		)
		if d3d11_failed(hr) {
			if view_info.srv != nil {
				view_info.srv.Release(view_info.srv)
			}
			set_backend_error(ctx, "gfx.d3d11: CreateUnorderedAccessView failed for storage buffer")
			return false
		}
		d3d11_set_view_debug_names(&view_info, desc.label)

		state.views[handle] = view_info
		return true
	}

	image := view_desc_image(desc)
	image_info, image_ok := state.images[image]
	if !image_ok || image_info.texture2d == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: view image handle is unknown")
		return false
	}
	if image_info.kind != .Image_2D {
		set_unsupported_error(ctx, "gfx.d3d11: only Image_2D views are implemented")
		return false
	}

	format := view_desc_format(desc)
	if format == .Invalid {
		format = image_info.format
	}
	if format != image_info.format {
		set_validation_error(ctx, "gfx.d3d11: view format must match image format for now")
		return false
	}

	base_mip: u32
	mip_count: u32
	base_layer: u32
	layer_count: u32
	switch kind {
	case .Sampled:
		base_mip = positive_u32_or_default(desc.texture.base_mip, 0)
		if base_mip >= image_info.mip_count {
			set_validation_error(ctx, "gfx.d3d11: view mip range is invalid")
			return false
		}
		mip_count = positive_u32_or_default(desc.texture.mip_count, image_info.mip_count - base_mip)

		base_layer = positive_u32_or_default(desc.texture.base_layer, 0)
		if base_layer >= image_info.array_count {
			set_validation_error(ctx, "gfx.d3d11: view layer range is invalid")
			return false
		}
		layer_count = positive_u32_or_default(desc.texture.layer_count, image_info.array_count - base_layer)

	case .Storage_Image:
		if desc.storage_image.mip_level < 0 || desc.storage_image.base_layer < 0 {
			set_validation_error(ctx, "gfx.d3d11: storage image view mip and layer must be non-negative")
			return false
		}

		base_mip = u32(desc.storage_image.mip_level)
		mip_count = 1
		base_layer = u32(desc.storage_image.base_layer)
		layer_count = positive_u32_or_default(desc.storage_image.layer_count, image_info.array_count - base_layer)

	case .Color_Attachment:
		if desc.color_attachment.mip_level < 0 || desc.color_attachment.layer < 0 {
			set_validation_error(ctx, "gfx.d3d11: color attachment view mip and layer must be non-negative")
			return false
		}

		base_mip = u32(desc.color_attachment.mip_level)
		mip_count = 1
		base_layer = u32(desc.color_attachment.layer)
		layer_count = 1

	case .Depth_Stencil_Attachment:
		if desc.depth_stencil_attachment.mip_level < 0 || desc.depth_stencil_attachment.layer < 0 {
			set_validation_error(ctx, "gfx.d3d11: depth-stencil attachment view mip and layer must be non-negative")
			return false
		}

		base_mip = u32(desc.depth_stencil_attachment.mip_level)
		mip_count = 1
		base_layer = u32(desc.depth_stencil_attachment.layer)
		layer_count = 1

	case .Storage_Buffer:
	}

	if mip_count == 0 || layer_count == 0 {
		set_validation_error(ctx, "gfx.d3d11: view range is empty")
		return false
	}

	if base_mip >= image_info.mip_count || base_mip + mip_count > image_info.mip_count {
		set_validation_error(ctx, "gfx.d3d11: view mip range is invalid")
		return false
	}
	if base_layer >= image_info.array_count || base_layer + layer_count > image_info.array_count {
		set_validation_error(ctx, "gfx.d3d11: view layer range is invalid")
		return false
	}
	if base_layer != 0 || layer_count != 1 {
		set_unsupported_error(ctx, "gfx.d3d11: only single-layer 2D views are implemented")
		return false
	}

	view_info := D3D11_View {
		image = image,
		kind = kind,
		width = image_info.width,
		height = image_info.height,
		mip_level = base_mip,
		base_layer = base_layer,
		layer_count = layer_count,
		format = format,
		sample_count = image_info.sample_count,
	}

	switch kind {
	case .Sampled:
		if !(.Texture in image_info.usage) {
			set_validation_error(ctx, "gfx.d3d11: sampled views require a shader-resource image")
			return false
		}
		if image_info.sample_count > 1 {
			set_unsupported_error(ctx, "gfx.d3d11: sampled views for multisampled images are not supported; resolve first")
			return false
		}

		view_desc := d3d11.SHADER_RESOURCE_VIEW_DESC {
			Format = d3d11_srv_format(format),
			ViewDimension = .TEXTURE2D,
			Texture2D = d3d11.TEX2D_SRV {
				MostDetailedMip = base_mip,
				MipLevels = mip_count,
			},
		}

		hr := state.device.CreateShaderResourceView(
			state.device,
			cast(^d3d11.IResource)image_info.texture2d,
			&view_desc,
			&view_info.srv,
		)
		if d3d11_failed(hr) {
			set_backend_error(ctx, "gfx.d3d11: CreateShaderResourceView failed")
			return false
		}

	case .Storage_Image:
		if !(.Storage_Image in image_info.usage) {
			set_validation_error(ctx, "gfx.d3d11: storage image views require a storage-capable image")
			return false
		}
		if image_info.sample_count > 1 {
			set_unsupported_error(ctx, "gfx.d3d11: multisampled storage image views are not supported")
			return false
		}
		if d3d11_is_depth_format(format) {
			set_unsupported_error(ctx, "gfx.d3d11: depth storage image views are not supported")
			return false
		}

		view_desc := d3d11.UNORDERED_ACCESS_VIEW_DESC {
			Format = d3d11_dxgi_format(format),
			ViewDimension = .TEXTURE2D,
			Texture2D = d3d11.TEX2D_UAV {
				MipSlice = base_mip,
			},
		}

		hr := state.device.CreateUnorderedAccessView(
			state.device,
			cast(^d3d11.IResource)image_info.texture2d,
			&view_desc,
			&view_info.uav,
		)
		if d3d11_failed(hr) {
			set_backend_error(ctx, "gfx.d3d11: CreateUnorderedAccessView failed for storage image")
			return false
		}

	case .Color_Attachment:
		if !(.Color_Attachment in image_info.usage) {
			set_validation_error(ctx, "gfx.d3d11: color attachment views require a color attachment image")
			return false
		}

		view_dimension := d3d11.RTV_DIMENSION.TEXTURE2D
		if image_info.sample_count > 1 {
			view_dimension = .TEXTURE2DMS
		}

		view_desc := d3d11.RENDER_TARGET_VIEW_DESC {
			Format = d3d11_dxgi_format(format),
			ViewDimension = view_dimension,
			Texture2D = d3d11.TEX2D_RTV {
				MipSlice = base_mip,
			},
		}

		hr := state.device.CreateRenderTargetView(
			state.device,
			cast(^d3d11.IResource)image_info.texture2d,
			&view_desc,
			&view_info.rtv,
		)
		if d3d11_failed(hr) {
			set_backend_error(ctx, "gfx.d3d11: CreateRenderTargetView failed")
			return false
		}

	case .Depth_Stencil_Attachment:
		if !(.Depth_Stencil_Attachment in image_info.usage) {
			set_validation_error(ctx, "gfx.d3d11: depth-stencil attachment views require a depth-stencil image")
			return false
		}

		view_dimension := d3d11.DSV_DIMENSION.TEXTURE2D
		if image_info.sample_count > 1 {
			view_dimension = .TEXTURE2DMS
		}

		view_desc := d3d11.DEPTH_STENCIL_VIEW_DESC {
			Format = d3d11_dsv_format(format),
			ViewDimension = view_dimension,
			Flags = {},
			Texture2D = d3d11.TEX2D_DSV {
				MipSlice = base_mip,
			},
		}

		hr := state.device.CreateDepthStencilView(
			state.device,
			cast(^d3d11.IResource)image_info.texture2d,
			&view_desc,
			&view_info.dsv,
		)
		if d3d11_failed(hr) {
			set_backend_error(ctx, "gfx.d3d11: CreateDepthStencilView failed")
			return false
		}
	case .Storage_Buffer:
	}

	d3d11_set_view_debug_names(&view_info, desc.label)
	state.views[handle] = view_info
	return true
}

d3d11_destroy_view :: proc(ctx: ^Context, handle: View) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if view_info, ok := state.views[handle]; ok {
		if view_info.srv != nil {
			view_info.srv.Release(view_info.srv)
		}
		if view_info.uav != nil {
			view_info.uav.Release(view_info.uav)
		}
		if view_info.rtv != nil {
			view_info.rtv.Release(view_info.rtv)
		}
		if view_info.dsv != nil {
			view_info.dsv.Release(view_info.dsv)
		}
		delete_key(&state.views, handle)
	}
}

d3d11_query_view_state :: proc(ctx: ^Context, handle: View) -> View_State {
	state := d3d11_state(ctx)
	if state == nil {
		return {}
	}

	if view_info, ok := state.views[handle]; ok {
		return {
			valid = view_info.srv != nil || view_info.uav != nil || view_info.rtv != nil || view_info.dsv != nil,
			kind = view_info.kind,
			image = view_info.image,
			buffer = view_info.buffer,
			width = i32(view_info.width),
			height = i32(view_info.height),
			offset = view_info.offset,
			size = view_info.size,
			mip_level = i32(view_info.mip_level),
			base_layer = i32(view_info.base_layer),
			layer_count = i32(view_info.layer_count),
			format = view_info.format,
			sample_count = i32(view_info.sample_count),
			storage_stride = int(view_info.storage_stride),
		}
	}

	return {}
}
