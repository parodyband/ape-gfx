#+private
package gfx

import "core:fmt"
import "core:mem"
import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import win32 "core:sys/windows"

D3D11_MAX_UAV_SLOTS :: 8
D3D11_MAX_SAMPLE_COUNT :: 8
D3D11_FL10_TEXTURE2D_DIMENSION :: 8192
D3D11_E_INVALIDARG :: d3d11.HRESULT(-2147024809) // 0x80070057
D3D11_E_OUTOFMEMORY :: d3d11.HRESULT(-2147024882) // 0x8007000E
D3D11_E_FAIL :: d3d11.HRESULT(-2147467259) // 0x80004005
D3D11_DEBUG_NAME_MAX_UTF16 :: 256
D3D11_INFO_QUEUE_MESSAGE_LIMIT :: 256

D3D11_Buffer :: struct {
	buffer: ^d3d11.IBuffer,
	usage: Buffer_Usage,
	size: u32,
	storage_stride: u32,
}

D3D11_Image :: struct {
	texture2d: ^d3d11.ITexture2D,
	kind: Image_Kind,
	usage: Image_Usage,
	width: u32,
	height: u32,
	mip_count: u32,
	array_count: u32,
	sample_count: u32,
	format: Pixel_Format,
}

D3D11_View :: struct {
	srv: ^d3d11.IShaderResourceView,
	uav: ^d3d11.IUnorderedAccessView,
	rtv: ^d3d11.IRenderTargetView,
	dsv: ^d3d11.IDepthStencilView,
	image: Image,
	buffer: Buffer,
	kind: View_Kind,
	width: u32,
	height: u32,
	offset: int,
	size: int,
	storage_stride: u32,
	mip_level: u32,
	base_layer: u32,
	layer_count: u32,
	format: Pixel_Format,
	sample_count: u32,
}

D3D11_Sampler :: struct {
	sampler: ^d3d11.ISamplerState,
}

D3D11_Binding_Masks :: struct {
	uniforms: u32,
	views: u32,
	samplers: u32,
}

D3D11_Binding_Slot :: struct {
	active: bool,
	native_slot: u32,
	size: u32,
	view_kind: View_Kind,
	access: Shader_Resource_Access,
	storage_image_format: Pixel_Format,
	storage_buffer_stride: u32,
}

D3D11_Uniform_Slots :: [MAX_UNIFORM_BLOCKS]D3D11_Binding_Slot
D3D11_View_Slots :: [MAX_RESOURCE_VIEWS]D3D11_Binding_Slot
D3D11_Sampler_Slots :: [MAX_SAMPLERS]D3D11_Binding_Slot

D3D11_Shader :: struct {
	vertex: ^d3d11.IVertexShader,
	pixel: ^d3d11.IPixelShader,
	compute: ^d3d11.IComputeShader,
	vertex_bytecode: []u8,
	required: [3]D3D11_Binding_Masks,
	uniform_slots: [3]D3D11_Uniform_Slots,
	view_slots: [3]D3D11_View_Slots,
	sampler_slots: [3]D3D11_Sampler_Slots,
	has_binding_metadata: bool,
	has_vertex_input_metadata: bool,
	vertex_inputs: [MAX_VERTEX_ATTRIBUTES]Shader_Vertex_Input_Desc,
}

D3D11_Pipeline :: struct {
	shader: Shader,
	input_layout: ^d3d11.IInputLayout,
	raster_state: ^d3d11.IRasterizerState,
	depth_stencil_state: ^d3d11.IDepthStencilState,
	blend_state: ^d3d11.IBlendState,
	topology: d3d11.PRIMITIVE_TOPOLOGY,
	index_format: dxgi.FORMAT,
	vertex_strides: [MAX_VERTEX_BUFFERS]u32,
	has_index_buffer: bool,
	required_vertex_buffers: u32,
	required: [3]D3D11_Binding_Masks,
	uniform_slots: [3]D3D11_Uniform_Slots,
	view_slots: [3]D3D11_View_Slots,
	sampler_slots: [3]D3D11_Sampler_Slots,
	has_binding_metadata: bool,
	color_formats: [MAX_COLOR_ATTACHMENTS]Pixel_Format,
	depth_format: Pixel_Format,
	depth_enabled: bool,
	depth_only: bool,
}

D3D11_Compute_Pipeline :: struct {
	shader: Shader,
	required: [3]D3D11_Binding_Masks,
	uniform_slots: [3]D3D11_Uniform_Slots,
	view_slots: [3]D3D11_View_Slots,
	sampler_slots: [3]D3D11_Sampler_Slots,
	has_binding_metadata: bool,
}

D3D11_State :: struct {
	device: ^d3d11.IDevice,
	immediate: ^d3d11.IDeviceContext,
	swapchain: ^dxgi.ISwapChain,
	info_queue: ^d3d11.IInfoQueue,
	debug_enabled: bool,
	backbuffer_rtv: ^d3d11.IRenderTargetView,
	default_depth_texture: ^d3d11.ITexture2D,
	default_depth_dsv: ^d3d11.IDepthStencilView,
	uniform_buffers: [MAX_UNIFORM_BLOCKS]^d3d11.IBuffer,
	uniform_buffer_sizes: [MAX_UNIFORM_BLOCKS]u32,
	feature_level: d3d11.FEATURE_LEVEL,
	width: u32,
	height: u32,
	format: dxgi.FORMAT,
	sync_interval: u32,
	buffers: map[Buffer]D3D11_Buffer,
	images: map[Image]D3D11_Image,
	views: map[View]D3D11_View,
	samplers: map[Sampler]D3D11_Sampler,
	shaders: map[Shader]D3D11_Shader,
	pipelines: map[Pipeline]D3D11_Pipeline,
	compute_pipelines: map[Compute_Pipeline]D3D11_Compute_Pipeline,
	current_pipeline: Pipeline,
	current_compute_pipeline: Compute_Pipeline,
	current_vertex_buffers: u32,
	current_index_buffer: bool,
	current_bindings: [3]D3D11_Binding_Masks,
	current_pass_color_formats: [MAX_COLOR_ATTACHMENTS]Pixel_Format,
	current_pass_has_color: bool,
	current_pass_depth_format: Pixel_Format,
	current_pass_has_depth: bool,
}

d3d11_init :: proc(ctx: ^Context) -> bool {
	if ctx.desc.native_window == nil {
		set_validation_error(ctx, "gfx.d3d11: native_window is required")
		return false
	}

	state := new(D3D11_State)
	ctx.backend_data = state
	state.buffers = make(map[Buffer]D3D11_Buffer)
	state.images = make(map[Image]D3D11_Image)
	state.views = make(map[View]D3D11_View)
	state.samplers = make(map[Sampler]D3D11_Sampler)
	state.shaders = make(map[Shader]D3D11_Shader)
	state.pipelines = make(map[Pipeline]D3D11_Pipeline)
	state.compute_pipelines = make(map[Compute_Pipeline]D3D11_Compute_Pipeline)

	state.width = positive_u32_or_default(ctx.desc.width, 1280)
	state.height = positive_u32_or_default(ctx.desc.height, 720)
	state.format = d3d11_dxgi_format(ctx.desc.swapchain_format)
	state.sync_interval = 0
	if ctx.desc.vsync {
		state.sync_interval = 1
	}

	if !d3d11_create_device_and_swapchain(ctx, state, ctx.desc.debug) {
		d3d11_release_state(state)
		free(state)
		ctx.backend_data = nil
		return false
	}

	if !d3d11_create_backbuffer_view(ctx, state) {
		d3d11_release_state(state)
		free(state)
		ctx.backend_data = nil
		return false
	}

	if !d3d11_create_default_depth_view(ctx, state) {
		d3d11_release_state(state)
		free(state)
		ctx.backend_data = nil
		return false
	}

	return true
}

d3d11_shutdown :: proc(ctx: ^Context) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	d3d11_release_state(state)
	free(state)
	ctx.backend_data = nil
}

d3d11_create_buffer :: proc(ctx: ^Context, handle: Buffer, desc: Buffer_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	if u64(desc.size) > 0xffffffff {
		set_validation_error(ctx, "gfx.d3d11: buffer size exceeds D3D11 u32 limit")
		return false
	}
	if desc.storage_stride > d3d11.REQ_MULTI_ELEMENT_STRUCTURE_SIZE_IN_BYTES {
		set_validation_errorf(ctx, "gfx.d3d11: structured storage buffer stride exceeds D3D11 limit (%d)", d3d11.REQ_MULTI_ELEMENT_STRUCTURE_SIZE_IN_BYTES)
		return false
	}

	if !d3d11_validate_buffer_usage(ctx, desc.usage) {
		return false
	}

	if .Immutable in desc.usage && (desc.data.ptr == nil || desc.data.size <= 0) {
		set_validation_error(ctx, "gfx.d3d11: immutable buffers require initial data")
		return false
	}

	buffer_desc := d3d11.BUFFER_DESC {
		ByteWidth = u32(desc.size),
		Usage = d3d11_buffer_usage(desc.usage),
		BindFlags = d3d11_buffer_bind_flags(desc.usage),
		CPUAccessFlags = d3d11_buffer_cpu_access(desc.usage),
		MiscFlags = d3d11_buffer_misc_flags(desc.usage, desc.storage_stride),
		StructureByteStride = u32(desc.storage_stride),
	}

	initial_data: d3d11.SUBRESOURCE_DATA
	initial_data_ptr: ^d3d11.SUBRESOURCE_DATA
	if desc.data.ptr != nil && desc.data.size > 0 {
		initial_data = d3d11.SUBRESOURCE_DATA {
			pSysMem = desc.data.ptr,
			SysMemPitch = 0,
			SysMemSlicePitch = 0,
		}
		initial_data_ptr = &initial_data
	}

	native_buffer: ^d3d11.IBuffer
	hr := state.device.CreateBuffer(state.device, &buffer_desc, initial_data_ptr, &native_buffer)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: CreateBuffer failed")
		return false
	}
	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)native_buffer, desc.label)

	state.buffers[handle] = D3D11_Buffer {
		buffer = native_buffer,
		usage = desc.usage,
		size = u32(desc.size),
		storage_stride = u32(desc.storage_stride),
	}
	return true
}

d3d11_destroy_buffer :: proc(ctx: ^Context, handle: Buffer) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if buffer_info, ok := state.buffers[handle]; ok {
		if buffer_info.buffer != nil {
			buffer_info.buffer.Release(buffer_info.buffer)
		}
		delete_key(&state.buffers, handle)
	}
}

d3d11_update_buffer :: proc(ctx: ^Context, desc: Buffer_Update_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	buffer_info, buffer_ok := state.buffers[desc.buffer]
	if !buffer_ok || buffer_info.buffer == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: buffer handle is unknown")
		return false
	}

	if !d3d11_buffer_has_cpu_update(buffer_info.usage) {
		set_validation_error(ctx, "gfx.d3d11: update_buffer requires a dynamic or stream-updated buffer")
		return false
	}

	if desc.offset < 0 ||
	   desc.data.ptr == nil ||
	   desc.data.size <= 0 ||
	   desc.offset > int(buffer_info.size) ||
	   desc.data.size > int(buffer_info.size) - desc.offset {
		set_validation_error(ctx, "gfx.d3d11: update_buffer range is invalid")
		return false
	}

	if .Dynamic_Update in buffer_info.usage && (desc.offset != 0 || desc.data.size != int(buffer_info.size)) {
		set_validation_error(ctx, "gfx.d3d11: dynamic buffer updates must replace the full buffer; use Stream_Update for ranged writes")
		return false
	}

	map_type := d3d11.MAP.WRITE_DISCARD
	if .Stream_Update in buffer_info.usage && desc.offset != 0 {
		map_type = .WRITE_NO_OVERWRITE
	}

	mapped: d3d11.MAPPED_SUBRESOURCE
	hr := state.immediate.Map(
		state.immediate,
		cast(^d3d11.IResource)buffer_info.buffer,
		0,
		map_type,
		{},
		&mapped,
	)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to map buffer for update")
		return false
	}

	dst := rawptr(uintptr(mapped.pData) + uintptr(desc.offset))
	mem.copy(dst, desc.data.ptr, desc.data.size)
	state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)buffer_info.buffer, 0)
	return true
}

d3d11_read_buffer :: proc(ctx: ^Context, desc: Buffer_Read_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	buffer_info, buffer_ok := state.buffers[desc.buffer]
	if !buffer_ok || buffer_info.buffer == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: buffer handle is unknown")
		return false
	}

	if desc.offset < 0 ||
	   desc.data.ptr == nil ||
	   desc.data.size <= 0 ||
	   desc.offset > int(buffer_info.size) ||
	   desc.data.size > int(buffer_info.size) - desc.offset {
		set_validation_error(ctx, "gfx.d3d11: read_buffer range is invalid")
		return false
	}

	if u64(desc.data.size) > 0xffffffff {
		set_validation_error(ctx, "gfx.d3d11: read_buffer size exceeds D3D11 u32 limit")
		return false
	}

	staging_desc := d3d11.BUFFER_DESC {
		ByteWidth = u32(desc.data.size),
		Usage = .STAGING,
		BindFlags = {},
		CPUAccessFlags = {.READ},
		MiscFlags = {},
		StructureByteStride = 0,
	}

	staging: ^d3d11.IBuffer
	hr := state.device.CreateBuffer(state.device, &staging_desc, nil, &staging)
	if d3d11_failed(hr) || staging == nil {
		set_backend_error(ctx, "gfx.d3d11: failed to create staging readback buffer")
		return false
	}
	defer staging.Release(staging)

	source_box := d3d11.BOX {
		left = u32(desc.offset),
		top = 0,
		front = 0,
		right = u32(desc.offset + desc.data.size),
		bottom = 1,
		back = 1,
	}
	state.immediate.CopySubresourceRegion(
		state.immediate,
		cast(^d3d11.IResource)staging,
		0,
		0,
		0,
		0,
		cast(^d3d11.IResource)buffer_info.buffer,
		0,
		&source_box,
	)

	mapped: d3d11.MAPPED_SUBRESOURCE
	hr = state.immediate.Map(
		state.immediate,
		cast(^d3d11.IResource)staging,
		0,
		.READ,
		{},
		&mapped,
	)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to map readback buffer")
		return false
	}

	mem.copy(desc.data.ptr, mapped.pData, desc.data.size)
	state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)staging, 0)
	return true
}

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

d3d11_query_buffer_state :: proc(ctx: ^Context, handle: Buffer) -> Buffer_State {
	state := d3d11_state(ctx)
	if state == nil {
		return {}
	}

	if buffer_info, ok := state.buffers[handle]; ok {
		return {
			valid = buffer_info.buffer != nil,
			usage = buffer_info.usage,
			size = int(buffer_info.size),
			storage_stride = int(buffer_info.storage_stride),
		}
	}

	return {}
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

d3d11_query_features :: proc(ctx: ^Context) -> Features {
	state := d3d11_state(ctx)
	compute_supported := state != nil && state.feature_level >= ._11_0

	return {
		backend = .D3D11,
		render_to_texture = true,
		multiple_render_targets = true,
		msaa_render_targets = true,
		depth_attachment = true,
		depth_only_pass = true,
		sampled_depth = true,
		storage_images = true,
		storage_buffers = true,
		compute = compute_supported,
		dynamic_textures = true,
		mipmapped_textures = true,
		buffer_updates = true,
		buffer_readback = true,
	}
}

d3d11_query_limits :: proc(ctx: ^Context) -> Limits {
	limits := api_limits()
	state := d3d11_state(ctx)
	if state == nil {
		return limits
	}

	limits.max_image_dimension_2d = d3d11_texture2d_dimension_limit(state.feature_level)
	limits.max_image_array_layers = 1
	limits.max_image_sample_count = D3D11_MAX_SAMPLE_COUNT
	limits.max_compute_thread_groups_per_dimension = int(d3d11.CS_DISPATCH_MAX_THREAD_GROUPS_PER_DIMENSION)
	return limits
}

d3d11_create_sampler :: proc(ctx: ^Context, handle: Sampler, desc: Sampler_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	sampler_desc := d3d11.SAMPLER_DESC {
		Filter = d3d11_filter(desc.min_filter, desc.mag_filter, desc.mip_filter),
		AddressU = d3d11_wrap(desc.wrap_u),
		AddressV = d3d11_wrap(desc.wrap_v),
		AddressW = d3d11_wrap(desc.wrap_w),
		MipLODBias = 0,
		MaxAnisotropy = 1,
		ComparisonFunc = .ALWAYS,
		BorderColor = {0, 0, 0, 0},
		MinLOD = 0,
		MaxLOD = 3.4028234663852886e38,
	}

	native_sampler: ^d3d11.ISamplerState
	hr := state.device.CreateSamplerState(state.device, &sampler_desc, &native_sampler)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: CreateSamplerState failed")
		return false
	}
	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)native_sampler, desc.label)

	state.samplers[handle] = D3D11_Sampler {
		sampler = native_sampler,
	}
	return true
}

d3d11_destroy_sampler :: proc(ctx: ^Context, handle: Sampler) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if sampler_info, ok := state.samplers[handle]; ok {
		if sampler_info.sampler != nil {
			sampler_info.sampler.Release(sampler_info.sampler)
		}
		delete_key(&state.samplers, handle)
	}
}

d3d11_create_shader :: proc(ctx: ^Context, handle: Shader, desc: Shader_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	shader_info: D3D11_Shader
	for stage_desc in desc.stages {
		if stage_desc.bytecode.ptr == nil || stage_desc.bytecode.size <= 0 {
			continue
		}

		switch stage_desc.stage {
		case .Vertex:
			hr := state.device.CreateVertexShader(
				state.device,
				stage_desc.bytecode.ptr,
				d3d11.SIZE_T(stage_desc.bytecode.size),
				nil,
				&shader_info.vertex,
			)
			if d3d11_failed(hr) {
				d3d11_release_shader(&shader_info)
				set_backend_error(ctx, "gfx.d3d11: CreateVertexShader failed")
				return false
			}
			d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)shader_info.vertex, desc.label, "vertex shader")
			shader_info.vertex_bytecode = d3d11_copy_range(stage_desc.bytecode)
		case .Fragment:
			hr := state.device.CreatePixelShader(
				state.device,
				stage_desc.bytecode.ptr,
				d3d11.SIZE_T(stage_desc.bytecode.size),
				nil,
				&shader_info.pixel,
			)
			if d3d11_failed(hr) {
				d3d11_release_shader(&shader_info)
				set_backend_error(ctx, "gfx.d3d11: CreatePixelShader failed")
				return false
			}
			d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)shader_info.pixel, desc.label, "fragment shader")
		case .Compute:
			hr := state.device.CreateComputeShader(
				state.device,
				stage_desc.bytecode.ptr,
				d3d11.SIZE_T(stage_desc.bytecode.size),
				nil,
				&shader_info.compute,
			)
			if d3d11_failed(hr) {
				d3d11_release_shader(&shader_info)
				set_backend_error(ctx, "gfx.d3d11: CreateComputeShader failed")
				return false
			}
			d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)shader_info.compute, desc.label, "compute shader")
		}
	}

	if shader_info.vertex == nil && shader_info.pixel == nil && shader_info.compute == nil {
		set_validation_error(ctx, "gfx.d3d11: shader did not contain supported bytecode")
		return false
	}

	shader_info.has_binding_metadata = desc.has_binding_metadata
	shader_info.has_vertex_input_metadata = desc.has_vertex_input_metadata
	for input, slot in desc.vertex_inputs {
		shader_info.vertex_inputs[slot] = input
	}
	for binding in desc.bindings {
		if !binding.active {
			continue
		}

		stage := int(binding.stage)
		switch binding.kind {
		case .Uniform_Block:
			if binding.slot >= MAX_UNIFORM_BLOCKS {
				set_validation_errorf(ctx, "gfx.d3d11: uniform binding slot %d is out of range", binding.slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			if binding.native_slot >= MAX_UNIFORM_BLOCKS {
				set_validation_errorf(ctx, "gfx.d3d11: native uniform binding slot %d is out of range", binding.native_slot)
				d3d11_release_shader(&shader_info)
				return false
			}

			existing_slot := shader_info.uniform_slots[stage][int(binding.slot)]
			existing_size := existing_slot.size
			if existing_size != 0 && binding.size != 0 && existing_size != binding.size {
				set_validation_errorf(ctx, "gfx.d3d11: uniform binding slot %d has conflicting reflected sizes", binding.slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			shader_info.required[stage].uniforms |= d3d11_slot_mask(binding.slot)
			shader_info.uniform_slots[stage][int(binding.slot)] = {
				active = true,
				native_slot = binding.native_slot,
				size = binding.size,
			}
		case .Resource_View:
			if binding.slot >= MAX_RESOURCE_VIEWS {
				set_validation_errorf(ctx, "gfx.d3d11: resource view binding slot %d is out of range", binding.slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			if binding.native_slot >= MAX_RESOURCE_VIEWS {
				set_validation_errorf(ctx, "gfx.d3d11: native resource view binding slot %d is out of range", binding.native_slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			if !d3d11_resource_view_kind_supported(binding.view_kind) {
				set_unsupported_errorf(ctx, "gfx.d3d11: resource view binding slot %d has unsupported reflected view kind", binding.slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			if (binding.view_kind == .Storage_Image || binding.view_kind == .Storage_Buffer) && binding.native_slot >= D3D11_MAX_UAV_SLOTS {
				set_validation_errorf(ctx, "gfx.d3d11: native storage resource view binding slot %d is out of range", binding.native_slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			shader_info.required[stage].views |= d3d11_slot_mask(binding.slot)
			shader_info.view_slots[stage][int(binding.slot)] = {
				active = true,
				native_slot = binding.native_slot,
				view_kind = binding.view_kind,
				access = binding.access,
				storage_image_format = binding.storage_image_format,
				storage_buffer_stride = binding.storage_buffer_stride,
			}
		case .Sampler:
			if binding.slot >= MAX_SAMPLERS {
				set_validation_errorf(ctx, "gfx.d3d11: sampler binding slot %d is out of range", binding.slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			if binding.native_slot >= MAX_SAMPLERS {
				set_validation_errorf(ctx, "gfx.d3d11: native sampler binding slot %d is out of range", binding.native_slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			shader_info.required[stage].samplers |= d3d11_slot_mask(binding.slot)
			shader_info.sampler_slots[stage][int(binding.slot)] = {
				active = true,
				native_slot = binding.native_slot,
			}
		}
	}

	state.shaders[handle] = shader_info
	return true
}

d3d11_destroy_shader :: proc(ctx: ^Context, handle: Shader) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if shader_info, ok := state.shaders[handle]; ok {
		d3d11_release_shader(&shader_info)
		delete_key(&state.shaders, handle)
	}
}

d3d11_create_pipeline :: proc(ctx: ^Context, handle: Pipeline, desc: Pipeline_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	shader_info, shader_ok := state.shaders[desc.shader]
	if !shader_ok {
		set_invalid_handle_error(ctx, "gfx.d3d11: pipeline shader handle is unknown")
		return false
	}
	if shader_info.vertex == nil || shader_info.pixel == nil {
		set_validation_error(ctx, "gfx.d3d11: graphics pipeline requires vertex and fragment shaders")
		return false
	}

	pipeline_info := D3D11_Pipeline {
		shader = desc.shader,
		topology = d3d11_primitive_topology(desc.primitive_type),
		index_format = d3d11_index_format(desc.index_type),
		has_index_buffer = desc.index_type != .None,
		required = shader_info.required,
		uniform_slots = shader_info.uniform_slots,
		view_slots = shader_info.view_slots,
		sampler_slots = shader_info.sampler_slots,
		has_binding_metadata = shader_info.has_binding_metadata,
		depth_format = desc.depth.format,
		depth_enabled = desc.depth.enabled,
		depth_only = desc.depth_only,
	}

	for slot in 0..<MAX_COLOR_ATTACHMENTS {
		pipeline_info.color_formats[slot] = desc.color_formats[slot]
	}
	if desc.depth_only {
		if !desc.depth.enabled {
			d3d11_release_pipeline(&pipeline_info)
			set_validation_error(ctx, "gfx.d3d11: depth-only pipeline requires depth to be enabled")
			return false
		}
		for format in pipeline_info.color_formats {
			if format != .Invalid {
				d3d11_release_pipeline(&pipeline_info)
				set_validation_error(ctx, "gfx.d3d11: depth-only pipeline cannot declare color formats")
				return false
			}
		}
	} else if pipeline_info.color_formats[0] == .Invalid {
		pipeline_info.color_formats[0] = ctx.desc.swapchain_format
	}
	if pipeline_info.depth_enabled && pipeline_info.depth_format == .Invalid {
		d3d11_release_pipeline(&pipeline_info)
		set_validation_error(ctx, "gfx.d3d11: depth-enabled pipeline requires a depth format")
		return false
	}

	for i in 0..<MAX_VERTEX_BUFFERS {
		pipeline_info.vertex_strides[i] = desc.layout.buffers[i].stride
	}

	if !d3d11_validate_pipeline_vertex_inputs(ctx, shader_info, desc.layout) {
		d3d11_release_pipeline(&pipeline_info)
		return false
	}

	input_elements: [MAX_VERTEX_ATTRIBUTES]d3d11.INPUT_ELEMENT_DESC
	input_count: u32
	for attr in desc.layout.attrs {
		if attr.format == .Invalid || attr.semantic == nil {
			continue
		}

		if attr.buffer_slot >= MAX_VERTEX_BUFFERS {
			d3d11_release_pipeline(&pipeline_info)
			set_validation_error(ctx, "gfx.d3d11: vertex attribute buffer slot is out of range")
			return false
		}

		if desc.layout.buffers[int(attr.buffer_slot)].stride == 0 {
			d3d11_release_pipeline(&pipeline_info)
			set_validation_errorf(ctx, "gfx.d3d11: vertex buffer slot %d has zero stride", attr.buffer_slot)
			return false
		}

		input_elements[int(input_count)] = d3d11.INPUT_ELEMENT_DESC {
			SemanticName = attr.semantic,
			SemanticIndex = attr.semantic_index,
			Format = d3d11_vertex_format(attr.format),
			InputSlot = attr.buffer_slot,
			AlignedByteOffset = attr.offset,
			InputSlotClass = d3d11_input_class(desc.layout.buffers[int(attr.buffer_slot)].step_func),
			InstanceDataStepRate = desc.layout.buffers[int(attr.buffer_slot)].step_rate,
		}
		pipeline_info.required_vertex_buffers |= d3d11_slot_mask(attr.buffer_slot)
		input_count += 1
	}

	if input_count > 0 {
		if len(shader_info.vertex_bytecode) == 0 {
			set_validation_error(ctx, "gfx.d3d11: vertex shader bytecode signature is unavailable")
			return false
		}

		hr := state.device.CreateInputLayout(
			state.device,
			raw_data(input_elements[:]),
			input_count,
			raw_data(shader_info.vertex_bytecode),
			d3d11.SIZE_T(len(shader_info.vertex_bytecode)),
			&pipeline_info.input_layout,
		)
		if d3d11_failed(hr) {
			d3d11_release_pipeline(&pipeline_info)
			set_backend_error(ctx, "gfx.d3d11: CreateInputLayout failed")
			return false
		}
		d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)pipeline_info.input_layout, desc.label, "input layout")
	}

	if !d3d11_create_pipeline_states(ctx, state, &pipeline_info, desc) {
		d3d11_release_pipeline(&pipeline_info)
		return false
	}
	d3d11_set_pipeline_debug_names(&pipeline_info, desc.label)

	state.pipelines[handle] = pipeline_info
	return true
}

d3d11_destroy_pipeline :: proc(ctx: ^Context, handle: Pipeline) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if pipeline_info, ok := state.pipelines[handle]; ok {
		d3d11_release_pipeline(&pipeline_info)
		delete_key(&state.pipelines, handle)
		if state.current_pipeline == handle {
			state.current_pipeline = Pipeline_Invalid
		}
	}
}

d3d11_create_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline, desc: Compute_Pipeline_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	shader_info, shader_ok := state.shaders[desc.shader]
	if !shader_ok {
		set_invalid_handle_error(ctx, "gfx.d3d11: compute pipeline shader handle is unknown")
		return false
	}
	if shader_info.compute == nil {
		set_validation_error(ctx, "gfx.d3d11: compute pipeline requires a compute shader")
		return false
	}

	state.compute_pipelines[handle] = D3D11_Compute_Pipeline {
		shader = desc.shader,
		required = shader_info.required,
		uniform_slots = shader_info.uniform_slots,
		view_slots = shader_info.view_slots,
		sampler_slots = shader_info.sampler_slots,
		has_binding_metadata = shader_info.has_binding_metadata,
	}
	return true
}

d3d11_destroy_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if _, ok := state.compute_pipelines[handle]; ok {
		delete_key(&state.compute_pipelines, handle)
		if state.current_compute_pipeline == handle {
			state.current_compute_pipeline = Compute_Pipeline_Invalid
		}
	}
}

d3d11_resize :: proc(ctx: ^Context, width, height: i32) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil || state.immediate == nil || state.swapchain == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	new_width := u32(width)
	new_height := u32(height)
	if state.width == new_width && state.height == new_height {
		return true
	}

	state.immediate.OMSetRenderTargets(state.immediate, 0, nil, nil)
	d3d11_release_default_views(state)
	state.immediate.Flush(state.immediate)

	hr := state.swapchain.ResizeBuffers(state.swapchain, 0, new_width, new_height, state.format, {})
	if d3d11_failed(hr) {
		d3d11_set_error_hr(ctx, state, "gfx.d3d11: ResizeBuffers failed", hr)
		return false
	}

	state.width = new_width
	state.height = new_height

	if !d3d11_create_backbuffer_view(ctx, state) {
		return false
	}
	if !d3d11_create_default_depth_view(ctx, state) {
		d3d11_release_default_views(state)
		return false
	}

	return true
}

d3d11_begin_pass :: proc(ctx: ^Context, desc: Pass_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil || state.backbuffer_rtv == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	rtvs: [MAX_COLOR_ATTACHMENTS]^d3d11.IRenderTargetView
	color_count: u32
	pass_width := state.width
	pass_height := state.height
	has_custom_color := false

	state.current_pipeline = Pipeline_Invalid
	state.current_compute_pipeline = Compute_Pipeline_Invalid
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	state.current_pass_color_formats = {}
	state.current_pass_has_color = false
	state.current_pass_depth_format = .Invalid
	state.current_pass_has_depth = false

	for attachment, slot in desc.color_attachments {
		if !view_valid(attachment) {
			continue
		}

		view_info, view_ok := state.views[attachment]
		if !view_ok || view_info.rtv == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: color attachment view handle is unknown")
			return false
		}
		if view_info.kind != .Color_Attachment {
			set_validation_error(ctx, "gfx.d3d11: pass color attachment requires a color attachment view")
			return false
		}

		if !has_custom_color {
			pass_width = view_info.width
			pass_height = view_info.height
			has_custom_color = true
		} else if view_info.width != pass_width || view_info.height != pass_height {
			set_validation_error(ctx, "gfx.d3d11: color attachments must have matching dimensions")
			return false
		}

		rtvs[slot] = view_info.rtv
		state.current_pass_color_formats[slot] = view_info.format
		state.current_pass_has_color = true
		color_count = u32(slot + 1)
	}

	dsv := state.default_depth_dsv
	if view_valid(desc.depth_stencil_attachment) {
		view_info, view_ok := state.views[desc.depth_stencil_attachment]
		if !view_ok || view_info.dsv == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: depth-stencil attachment view handle is unknown")
			return false
		}
		if view_info.kind != .Depth_Stencil_Attachment {
			set_validation_error(ctx, "gfx.d3d11: pass depth attachment requires a depth-stencil attachment view")
			return false
		}
		if has_custom_color {
			if view_info.width != pass_width || view_info.height != pass_height {
				set_validation_error(ctx, "gfx.d3d11: depth-stencil attachment dimensions must match the color attachments")
				return false
			}
		} else {
			pass_width = view_info.width
			pass_height = view_info.height
		}

		dsv = view_info.dsv
		state.current_pass_depth_format = view_info.format
		state.current_pass_has_depth = true
	} else if has_custom_color {
		dsv = nil
	} else {
		rtvs[0] = state.backbuffer_rtv
		color_count = 1
		state.current_pass_color_formats[0] = ctx.desc.swapchain_format
		state.current_pass_has_color = true
		state.current_pass_has_depth = state.default_depth_dsv != nil
		if state.current_pass_has_depth {
			state.current_pass_depth_format = .D32F
		}
	}

	if color_count == 0 && dsv == nil {
		set_validation_error(ctx, "gfx.d3d11: pass requires at least one color or depth-stencil attachment")
		return false
	}

	null_srvs: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	state.immediate.VSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	state.immediate.PSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	d3d11_clear_compute_resource_bindings(state)

	viewport := d3d11.VIEWPORT {
		TopLeftX = 0,
		TopLeftY = 0,
		Width = f32(pass_width),
		Height = f32(pass_height),
		MinDepth = 0,
		MaxDepth = 1,
	}
	state.immediate.RSSetViewports(state.immediate, 1, &viewport)

	if color_count > 0 {
		state.immediate.OMSetRenderTargets(state.immediate, color_count, &rtvs[0], dsv)
	} else {
		state.immediate.OMSetRenderTargets(state.immediate, 0, nil, dsv)
	}

	for slot in 0..<int(color_count) {
		if rtvs[slot] == nil {
			continue
		}

		color_action := desc.action.colors[slot]
		if color_action.load_action == .Clear {
			clear_color := [4]f32 {
				color_action.clear_value.r,
				color_action.clear_value.g,
				color_action.clear_value.b,
				color_action.clear_value.a,
			}
			state.immediate.ClearRenderTargetView(state.immediate, rtvs[slot], &clear_color)
		}
	}

	if dsv != nil {
		clear_flags: d3d11.CLEAR_FLAGS
		if desc.action.depth.load_action == .Clear {
			clear_flags += {.DEPTH}
		}
		if state.current_pass_depth_format == .D24S8 && desc.action.stencil.load_action == .Clear {
			clear_flags += {.STENCIL}
		}
		if clear_flags == {} {
			return true
		}

		state.immediate.ClearDepthStencilView(
			state.immediate,
			dsv,
			clear_flags,
			desc.action.depth.clear_value,
			desc.action.stencil.clear_value,
		)
	}

	return true
}

d3d11_begin_compute_pass :: proc(ctx: ^Context, desc: Compute_Pass_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	state.immediate.OMSetRenderTargets(state.immediate, 0, nil, nil)
	d3d11_clear_graphics_resource_bindings(state)
	d3d11_clear_compute_resource_bindings(state)

	state.current_pipeline = Pipeline_Invalid
	state.current_compute_pipeline = Compute_Pipeline_Invalid
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	state.current_pass_color_formats = {}
	state.current_pass_has_color = false
	state.current_pass_depth_format = .Invalid
	state.current_pass_has_depth = false
	return true
}

d3d11_apply_pipeline :: proc(ctx: ^Context, pipeline: Pipeline) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.pipelines[pipeline]
	if !pipeline_ok {
		set_invalid_handle_error(ctx, "gfx.d3d11: pipeline handle is unknown")
		return false
	}

	shader_info, shader_ok := state.shaders[pipeline_info.shader]
	if !shader_ok {
		set_invalid_handle_error(ctx, "gfx.d3d11: pipeline shader handle is unknown")
		return false
	}

	if !d3d11_validate_pipeline_pass_compatibility(ctx, state, &pipeline_info) {
		return false
	}

	state.immediate.IASetPrimitiveTopology(state.immediate, pipeline_info.topology)
	state.immediate.IASetInputLayout(state.immediate, pipeline_info.input_layout)
	state.immediate.VSSetShader(state.immediate, shader_info.vertex, nil, 0)
	state.immediate.PSSetShader(state.immediate, shader_info.pixel, nil, 0)
	state.immediate.RSSetState(state.immediate, pipeline_info.raster_state)
	state.immediate.OMSetDepthStencilState(state.immediate, pipeline_info.depth_stencil_state, 0)

	blend_factor := [4]f32{1, 1, 1, 1}
	state.immediate.OMSetBlendState(state.immediate, pipeline_info.blend_state, &blend_factor, 0xffffffff)
	state.current_pipeline = pipeline
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	return true
}

d3d11_apply_compute_pipeline :: proc(ctx: ^Context, pipeline: Compute_Pipeline) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.compute_pipelines[pipeline]
	if !pipeline_ok {
		set_invalid_handle_error(ctx, "gfx.d3d11: compute pipeline handle is unknown")
		return false
	}

	shader_info, shader_ok := state.shaders[pipeline_info.shader]
	if !shader_ok || shader_info.compute == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: compute pipeline shader handle is unknown")
		return false
	}

	state.immediate.CSSetShader(state.immediate, shader_info.compute, nil, 0)
	state.current_pipeline = Pipeline_Invalid
	state.current_compute_pipeline = pipeline
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	return true
}

d3d11_apply_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	if ctx.pass_kind == .Compute {
		return d3d11_apply_compute_bindings(ctx, bindings)
	}

	pipeline_info, pipeline_ok := state.pipelines[state.current_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: apply_bindings requires an applied pipeline")
		return false
	}

	vertex_buffers: [MAX_VERTEX_BUFFERS]^d3d11.IBuffer
	strides: [MAX_VERTEX_BUFFERS]u32
	offsets: [MAX_VERTEX_BUFFERS]u32
	vertex_count: u32
	vertex_mask: u32

	for binding, slot in bindings.vertex_buffers {
		if !buffer_valid(binding.buffer) {
			continue
		}

		buffer_info, buffer_ok := state.buffers[binding.buffer]
		if !buffer_ok || buffer_info.buffer == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: vertex buffer handle is unknown")
			return false
		}
		if !(.Vertex in buffer_info.usage) {
			set_validation_error(ctx, "gfx.d3d11: bound buffer is not vertex-capable")
			return false
		}

		vertex_buffers[slot] = buffer_info.buffer
		strides[slot] = pipeline_info.vertex_strides[slot]
		offsets[slot] = u32(binding.offset)
		vertex_mask |= d3d11_slot_mask(u32(slot))
		vertex_count = u32(slot + 1)
	}

	if vertex_count > 0 {
		state.immediate.IASetVertexBuffers(
			state.immediate,
			0,
			vertex_count,
			&vertex_buffers[0],
			&strides[0],
			&offsets[0],
		)
	}
	state.current_vertex_buffers = vertex_mask

	if buffer_valid(bindings.index_buffer.buffer) {
		buffer_info, buffer_ok := state.buffers[bindings.index_buffer.buffer]
		if !buffer_ok || buffer_info.buffer == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: index buffer handle is unknown")
			return false
		}
		if !(.Index in buffer_info.usage) {
			set_validation_error(ctx, "gfx.d3d11: bound buffer is not index-capable")
			return false
		}

		state.immediate.IASetIndexBuffer(
			state.immediate,
			buffer_info.buffer,
			pipeline_info.index_format,
			u32(bindings.index_buffer.offset),
		)
		state.current_index_buffer = true
	} else {
		state.current_index_buffer = false
	}

	resource_views: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	resource_views_by_stage: [3][MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	resource_view_mask: u32
	resource_view_native_masks: [3]u32
	resource_view_logical_masks: [3]u32
	for view, slot in bindings.views {
		if !view_valid(view) {
			continue
		}

		view_info, view_ok := state.views[view]
		if !view_ok {
			set_invalid_handle_error(ctx, "gfx.d3d11: resource view handle is unknown")
			return false
		}

		logical_mask := d3d11_slot_mask(u32(slot))
		if pipeline_info.has_binding_metadata {
			used := false
			for stage in 0..<3 {
				binding_slot := pipeline_info.view_slots[stage][slot]
				if !binding_slot.active {
					continue
				}

				used = true
				if !d3d11_validate_resource_view_binding(ctx, &view_info, binding_slot, u32(slot), false) {
					return false
				}
				if binding_slot.view_kind == .Sampled {
					resource_views_by_stage[stage][int(binding_slot.native_slot)] = view_info.srv
					resource_view_native_masks[stage] |= d3d11_slot_mask(binding_slot.native_slot)
					resource_view_logical_masks[stage] |= logical_mask
				}
			}

			if !used {
				set_validation_errorf(ctx, "gfx.d3d11: resource view slot %d is not used by the current pipeline", slot)
				return false
			}
		} else {
			if view_info.srv == nil || view_info.kind != .Sampled {
				set_validation_error(ctx, "gfx.d3d11: shader resource binding requires a sampled view")
				return false
			}
			resource_views[slot] = view_info.srv
			resource_view_mask |= logical_mask
		}
	}
	if pipeline_info.has_binding_metadata {
		vs_count := d3d11_binding_span(resource_view_native_masks[int(Shader_Stage.Vertex)])
		if vs_count > 0 {
			state.immediate.VSSetShaderResources(state.immediate, 0, vs_count, &resource_views_by_stage[int(Shader_Stage.Vertex)][0])
		}

		ps_count := d3d11_binding_span(resource_view_native_masks[int(Shader_Stage.Fragment)])
		if ps_count > 0 {
			state.immediate.PSSetShaderResources(state.immediate, 0, ps_count, &resource_views_by_stage[int(Shader_Stage.Fragment)][0])
		}
	} else {
		resource_view_count := d3d11_binding_span(resource_view_mask)
		if resource_view_count > 0 {
			state.immediate.PSSetShaderResources(state.immediate, 0, resource_view_count, &resource_views[0])
		}
	}

	samplers: [MAX_SAMPLERS]^d3d11.ISamplerState
	samplers_by_stage: [3][MAX_SAMPLERS]^d3d11.ISamplerState
	sampler_mask: u32
	sampler_native_masks: [3]u32
	sampler_logical_masks: [3]u32
	for sampler, slot in bindings.samplers {
		if !sampler_valid(sampler) {
			continue
		}

		sampler_info, sampler_ok := state.samplers[sampler]
		if !sampler_ok || sampler_info.sampler == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: sampler handle is unknown")
			return false
		}

		logical_mask := d3d11_slot_mask(u32(slot))
		if pipeline_info.has_binding_metadata {
			used := false
			for stage in 0..<3 {
				binding_slot := pipeline_info.sampler_slots[stage][slot]
				if !binding_slot.active {
					continue
				}

				used = true
				samplers_by_stage[stage][int(binding_slot.native_slot)] = sampler_info.sampler
				sampler_native_masks[stage] |= d3d11_slot_mask(binding_slot.native_slot)
				sampler_logical_masks[stage] |= logical_mask
			}

			if !used {
				set_validation_errorf(ctx, "gfx.d3d11: sampler slot %d is not used by the current pipeline", slot)
				return false
			}
		} else {
			samplers[slot] = sampler_info.sampler
			sampler_mask |= logical_mask
		}
	}
	if pipeline_info.has_binding_metadata {
		vs_count := d3d11_binding_span(sampler_native_masks[int(Shader_Stage.Vertex)])
		if vs_count > 0 {
			state.immediate.VSSetSamplers(state.immediate, 0, vs_count, &samplers_by_stage[int(Shader_Stage.Vertex)][0])
		}

		ps_count := d3d11_binding_span(sampler_native_masks[int(Shader_Stage.Fragment)])
		if ps_count > 0 {
			state.immediate.PSSetSamplers(state.immediate, 0, ps_count, &samplers_by_stage[int(Shader_Stage.Fragment)][0])
		}
	} else {
		sampler_count := d3d11_binding_span(sampler_mask)
		if sampler_count > 0 {
			state.immediate.PSSetSamplers(state.immediate, 0, sampler_count, &samplers[0])
		}
	}

	if pipeline_info.has_binding_metadata {
		for stage in 0..<3 {
			state.current_bindings[stage].views = resource_view_logical_masks[stage]
			state.current_bindings[stage].samplers = sampler_logical_masks[stage]
		}
	} else {
		for stage in 0..<3 {
			state.current_bindings[stage].views = resource_view_mask
			state.current_bindings[stage].samplers = sampler_mask
		}
	}

	return true
}

d3d11_apply_compute_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.compute_pipelines[state.current_compute_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: apply_bindings requires an applied compute pipeline")
		return false
	}

	compute_stage := int(Shader_Stage.Compute)
	resource_views: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	unordered_views: [MAX_RESOURCE_VIEWS]^d3d11.IUnorderedAccessView
	resource_view_mask: u32
	unordered_view_mask: u32
	resource_view_logical_mask: u32
	for view, slot in bindings.views {
		if !view_valid(view) {
			continue
		}

		view_info, view_ok := state.views[view]
		if !view_ok {
			set_invalid_handle_error(ctx, "gfx.d3d11: resource view handle is unknown")
			return false
		}

		logical_mask := d3d11_slot_mask(u32(slot))
		if pipeline_info.has_binding_metadata {
			binding_slot := pipeline_info.view_slots[compute_stage][slot]
			if !binding_slot.active {
				set_validation_errorf(ctx, "gfx.d3d11: resource view slot %d is not used by the current compute pipeline", slot)
				return false
			}

			if !d3d11_validate_resource_view_binding(ctx, &view_info, binding_slot, u32(slot), true) {
				return false
			}

			switch binding_slot.view_kind {
			case .Sampled:
				resource_views[int(binding_slot.native_slot)] = view_info.srv
				resource_view_mask |= d3d11_slot_mask(binding_slot.native_slot)
			case .Storage_Image:
				unordered_views[int(binding_slot.native_slot)] = view_info.uav
				unordered_view_mask |= d3d11_slot_mask(binding_slot.native_slot)
			case .Storage_Buffer:
				if binding_slot.access == .Read {
					resource_views[int(binding_slot.native_slot)] = view_info.srv
					resource_view_mask |= d3d11_slot_mask(binding_slot.native_slot)
				} else {
					unordered_views[int(binding_slot.native_slot)] = view_info.uav
					unordered_view_mask |= d3d11_slot_mask(binding_slot.native_slot)
				}
			case .Color_Attachment, .Depth_Stencil_Attachment:
			}
			resource_view_logical_mask |= logical_mask
		} else {
			switch view_info.kind {
			case .Sampled:
				if view_info.srv == nil {
					set_validation_error(ctx, "gfx.d3d11: shader resource binding requires a sampled view")
					return false
				}
				resource_views[slot] = view_info.srv
				resource_view_mask |= logical_mask
			case .Storage_Image, .Storage_Buffer:
				if slot >= D3D11_MAX_UAV_SLOTS {
					set_validation_errorf(ctx, "gfx.d3d11: storage resource view slot %d is out of range", slot)
					return false
				}
				if view_info.uav == nil {
					set_validation_error(ctx, "gfx.d3d11: storage resource binding requires a storage view")
					return false
				}
				unordered_views[slot] = view_info.uav
				unordered_view_mask |= logical_mask
			case .Color_Attachment, .Depth_Stencil_Attachment:
				set_validation_error(ctx, "gfx.d3d11: compute resource binding requires sampled or storage views")
				return false
			}
			resource_view_logical_mask |= logical_mask
		}
	}

	d3d11_clear_compute_resource_bindings(state)
	resource_view_count := d3d11_binding_span(resource_view_mask)
	if resource_view_count > 0 {
		state.immediate.CSSetShaderResources(state.immediate, 0, resource_view_count, &resource_views[0])
	}
	unordered_view_count := d3d11_binding_span(unordered_view_mask)
	if unordered_view_count > 0 {
		state.immediate.CSSetUnorderedAccessViews(state.immediate, 0, unordered_view_count, &unordered_views[0], nil)
	}

	samplers: [MAX_SAMPLERS]^d3d11.ISamplerState
	sampler_mask: u32
	sampler_logical_mask: u32
	for sampler, slot in bindings.samplers {
		if !sampler_valid(sampler) {
			continue
		}

		sampler_info, sampler_ok := state.samplers[sampler]
		if !sampler_ok || sampler_info.sampler == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: sampler handle is unknown")
			return false
		}

		logical_mask := d3d11_slot_mask(u32(slot))
		if pipeline_info.has_binding_metadata {
			binding_slot := pipeline_info.sampler_slots[compute_stage][slot]
			if !binding_slot.active {
				set_validation_errorf(ctx, "gfx.d3d11: sampler slot %d is not used by the current compute pipeline", slot)
				return false
			}

			samplers[int(binding_slot.native_slot)] = sampler_info.sampler
			sampler_mask |= d3d11_slot_mask(binding_slot.native_slot)
			sampler_logical_mask |= logical_mask
		} else {
			samplers[slot] = sampler_info.sampler
			sampler_mask |= logical_mask
			sampler_logical_mask |= logical_mask
		}
	}

	sampler_count := d3d11_binding_span(sampler_mask)
	if sampler_count > 0 {
		state.immediate.CSSetSamplers(state.immediate, 0, sampler_count, &samplers[0])
	}

	state.current_bindings[compute_stage].views = resource_view_logical_mask
	state.current_bindings[compute_stage].samplers = sampler_logical_mask
	return true
}

d3d11_apply_uniforms :: proc(ctx: ^Context, slot: int, data: Range) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	if ctx.pass_kind == .Compute {
		return d3d11_apply_compute_uniforms(ctx, slot, data)
	}

	pipeline_info, pipeline_ok := state.pipelines[state.current_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: apply_uniforms requires an applied pipeline")
		return false
	}

	aligned_size := d3d11_uniform_buffer_size(data.size)
	if aligned_size == 0 || aligned_size > 64 * 1024 {
		set_validation_error(ctx, "gfx.d3d11: uniform data size is invalid")
		return false
	}

	if !d3d11_validate_uniform_upload(ctx, &pipeline_info, slot, data.size) {
		return false
	}

	if !d3d11_ensure_uniform_buffer(ctx, state, slot, aligned_size) {
		return false
	}

	buffer := state.uniform_buffers[slot]
	mapped: d3d11.MAPPED_SUBRESOURCE
	hr := state.immediate.Map(
		state.immediate,
		cast(^d3d11.IResource)buffer,
		0,
		.WRITE_DISCARD,
		{},
		&mapped,
	)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to map uniform buffer")
		return false
	}

	mem.copy(mapped.pData, data.ptr, data.size)
	if aligned_size > u32(data.size) {
		padding := int(aligned_size) - data.size
		padding_ptr := rawptr(uintptr(mapped.pData) + uintptr(data.size))
		mem.zero(padding_ptr, padding)
	}

	state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)buffer, 0)

	buffers := [1]^d3d11.IBuffer{buffer}
	slot_mask := d3d11_slot_mask(u32(slot))
	if pipeline_info.has_binding_metadata {
		vertex_slot := pipeline_info.uniform_slots[int(Shader_Stage.Vertex)][slot]
		if vertex_slot.active {
			state.immediate.VSSetConstantBuffers(state.immediate, vertex_slot.native_slot, 1, &buffers[0])
		}
		fragment_slot := pipeline_info.uniform_slots[int(Shader_Stage.Fragment)][slot]
		if fragment_slot.active {
			state.immediate.PSSetConstantBuffers(state.immediate, fragment_slot.native_slot, 1, &buffers[0])
		}
	} else {
		state.immediate.VSSetConstantBuffers(state.immediate, u32(slot), 1, &buffers[0])
		state.immediate.PSSetConstantBuffers(state.immediate, u32(slot), 1, &buffers[0])
	}
	if pipeline_info.has_binding_metadata {
		for stage in 0..<2 {
			if pipeline_info.uniform_slots[stage][slot].active {
				state.current_bindings[stage].uniforms |= slot_mask
			}
		}
	} else {
		for stage in 0..<2 {
			state.current_bindings[stage].uniforms |= slot_mask
		}
	}
	return true
}

d3d11_apply_compute_uniforms :: proc(ctx: ^Context, slot: int, data: Range) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.compute_pipelines[state.current_compute_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: apply_uniforms requires an applied compute pipeline")
		return false
	}

	aligned_size := d3d11_uniform_buffer_size(data.size)
	if aligned_size == 0 || aligned_size > 64 * 1024 {
		set_validation_error(ctx, "gfx.d3d11: uniform data size is invalid")
		return false
	}

	if !d3d11_validate_compute_uniform_upload(ctx, &pipeline_info, slot, data.size) {
		return false
	}

	if !d3d11_ensure_uniform_buffer(ctx, state, slot, aligned_size) {
		return false
	}

	buffer := state.uniform_buffers[slot]
	mapped: d3d11.MAPPED_SUBRESOURCE
	hr := state.immediate.Map(
		state.immediate,
		cast(^d3d11.IResource)buffer,
		0,
		.WRITE_DISCARD,
		{},
		&mapped,
	)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to map uniform buffer")
		return false
	}

	mem.copy(mapped.pData, data.ptr, data.size)
	if aligned_size > u32(data.size) {
		padding := int(aligned_size) - data.size
		padding_ptr := rawptr(uintptr(mapped.pData) + uintptr(data.size))
		mem.zero(padding_ptr, padding)
	}

	state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)buffer, 0)

	buffers := [1]^d3d11.IBuffer{buffer}
	compute_stage := int(Shader_Stage.Compute)
	slot_mask := d3d11_slot_mask(u32(slot))
	if pipeline_info.has_binding_metadata {
		compute_slot := pipeline_info.uniform_slots[compute_stage][slot]
		if compute_slot.active {
			state.immediate.CSSetConstantBuffers(state.immediate, compute_slot.native_slot, 1, &buffers[0])
			state.current_bindings[compute_stage].uniforms |= slot_mask
		}
	} else {
		state.immediate.CSSetConstantBuffers(state.immediate, u32(slot), 1, &buffers[0])
		state.current_bindings[compute_stage].uniforms |= slot_mask
	}
	return true
}

d3d11_draw :: proc(ctx: ^Context, base_element: i32, num_elements: i32, num_instances: i32) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.pipelines[state.current_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: draw requires an applied pipeline")
		return false
	}

	if !d3d11_validate_draw_bindings(ctx, state, &pipeline_info) {
		return false
	}

	if pipeline_info.has_index_buffer {
		if num_instances > 1 {
			state.immediate.DrawIndexedInstanced(
				state.immediate,
				u32(num_elements),
				u32(num_instances),
				u32(base_element),
				0,
				0,
			)
		} else {
			state.immediate.DrawIndexed(state.immediate, u32(num_elements), u32(base_element), 0)
		}
	} else {
		if num_instances > 1 {
			state.immediate.DrawInstanced(
				state.immediate,
				u32(num_elements),
				u32(num_instances),
				u32(base_element),
				0,
			)
		} else {
			state.immediate.Draw(state.immediate, u32(num_elements), u32(base_element))
		}
	}

	return true
}

d3d11_dispatch :: proc(ctx: ^Context, group_count_x, group_count_y, group_count_z: u32) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.compute_pipelines[state.current_compute_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: dispatch requires an applied compute pipeline")
		return false
	}

	if group_count_x > d3d11.CS_DISPATCH_MAX_THREAD_GROUPS_PER_DIMENSION ||
	   group_count_y > d3d11.CS_DISPATCH_MAX_THREAD_GROUPS_PER_DIMENSION ||
	   group_count_z > d3d11.CS_DISPATCH_MAX_THREAD_GROUPS_PER_DIMENSION {
		set_validation_error(ctx, "gfx.d3d11: dispatch thread group count exceeds D3D11 limits")
		return false
	}

	if !d3d11_validate_dispatch_bindings(ctx, state, &pipeline_info) {
		return false
	}

	state.immediate.Dispatch(state.immediate, group_count_x, group_count_y, group_count_z)
	return true
}

d3d11_end_pass :: proc(ctx: ^Context) -> bool {
	state := d3d11_state(ctx)
	if state != nil {
		if state.immediate != nil {
			state.immediate.OMSetRenderTargets(state.immediate, 0, nil, nil)
		}
		state.current_pipeline = Pipeline_Invalid
		state.current_compute_pipeline = Compute_Pipeline_Invalid
		state.current_vertex_buffers = 0
		state.current_index_buffer = false
		state.current_bindings = {}
		state.current_pass_color_formats = {}
		state.current_pass_has_color = false
		state.current_pass_depth_format = .Invalid
		state.current_pass_has_depth = false
	}
	return true
}

d3d11_end_compute_pass :: proc(ctx: ^Context) -> bool {
	state := d3d11_state(ctx)
	if state != nil {
		if state.immediate != nil {
			d3d11_clear_compute_resource_bindings(state)
			state.immediate.CSSetShader(state.immediate, nil, nil, 0)
		}
		state.current_pipeline = Pipeline_Invalid
		state.current_compute_pipeline = Compute_Pipeline_Invalid
		state.current_vertex_buffers = 0
		state.current_index_buffer = false
		state.current_bindings = {}
		state.current_pass_color_formats = {}
		state.current_pass_has_color = false
		state.current_pass_depth_format = .Invalid
		state.current_pass_has_depth = false
	}
	return true
}

d3d11_commit :: proc(ctx: ^Context) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.swapchain == nil {
		set_backend_error(ctx, "gfx.d3d11: swapchain is not initialized")
		return false
	}

	hr := state.swapchain.Present(state.swapchain, state.sync_interval, {})
	if d3d11_failed(hr) {
		if !d3d11_drain_info_queue(ctx, state, "Present failure") {
			return false
		}
		d3d11_set_error_hr(ctx, state, "gfx.d3d11: Present failed", hr)
		return false
	}
	if !d3d11_drain_info_queue(ctx, state, "Present") {
		return false
	}

	return true
}

d3d11_state :: proc(ctx: ^Context) -> ^D3D11_State {
	if ctx == nil || ctx.backend_data == nil {
		return nil
	}

	return cast(^D3D11_State)ctx.backend_data
}

d3d11_set_debug_name :: proc(object: ^d3d11.IDeviceChild, label: string) {
	if object == nil || label == "" {
		return
	}

	name_utf16: [D3D11_DEBUG_NAME_MAX_UTF16]u16
	name := win32.utf8_to_utf16(name_utf16[:], label)
	if len(name) == 0 {
		return
	}

	object.SetPrivateData(
		object,
		d3d11.WKPDID_D3DDebugObjectNameW_UUID,
		u32(len(name) * size_of(u16)),
		raw_data(name),
	)
}

d3d11_set_debug_name_suffixed :: proc(object: ^d3d11.IDeviceChild, label, suffix: string) {
	if object == nil {
		return
	}

	if label == "" {
		d3d11_set_debug_name(object, suffix)
		return
	}
	if suffix == "" {
		d3d11_set_debug_name(object, label)
		return
	}

	name_storage: [256]u8
	name := fmt.bprintf(name_storage[:], "%s %s", label, suffix)
	d3d11_set_debug_name(object, name)
}

d3d11_set_device_debug_name :: proc(device: ^d3d11.IDevice, label: string) {
	if device == nil || label == "" {
		return
	}

	name_utf16: [D3D11_DEBUG_NAME_MAX_UTF16]u16
	name := win32.utf8_to_utf16(name_utf16[:], label)
	if len(name) == 0 {
		return
	}

	device.SetPrivateData(
		device,
		d3d11.WKPDID_D3DDebugObjectNameW_UUID,
		u32(len(name) * size_of(u16)),
		raw_data(name),
	)
}

d3d11_set_dxgi_debug_name :: proc(object: ^dxgi.IObject, label: string) {
	if object == nil || label == "" {
		return
	}

	name_utf16: [D3D11_DEBUG_NAME_MAX_UTF16]u16
	name := win32.utf8_to_utf16(name_utf16[:], label)
	if len(name) == 0 {
		return
	}

	object.SetPrivateData(
		object,
		d3d11.WKPDID_D3DDebugObjectNameW_UUID,
		u32(len(name) * size_of(u16)),
		raw_data(name),
	)
}

d3d11_set_view_debug_names :: proc(view_info: ^D3D11_View, label: string) {
	if view_info == nil {
		return
	}

	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)view_info.srv, label)
	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)view_info.uav, label)
	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)view_info.rtv, label)
	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)view_info.dsv, label)
}

d3d11_set_pipeline_debug_names :: proc(pipeline_info: ^D3D11_Pipeline, label: string) {
	if pipeline_info == nil {
		return
	}

	d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)pipeline_info.raster_state, label, "rasterizer state")
	d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)pipeline_info.depth_stencil_state, label, "depth stencil state")
	d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)pipeline_info.blend_state, label, "blend state")
}

d3d11_label_or_fallback :: proc(label, fallback: string) -> string {
	if label != "" {
		return label
	}

	return fallback
}

d3d11_init_info_queue :: proc(state: ^D3D11_State) {
	if state == nil || state.device == nil || !state.debug_enabled {
		return
	}

	info_queue_raw: rawptr
	hr := state.device.QueryInterface(cast(^d3d11.IUnknown)state.device, d3d11.IInfoQueue_UUID, &info_queue_raw)
	if d3d11_failed(hr) || info_queue_raw == nil {
		return
	}

	state.info_queue = cast(^d3d11.IInfoQueue)info_queue_raw
	state.info_queue.SetMessageCountLimit(state.info_queue, D3D11_INFO_QUEUE_MESSAGE_LIMIT)
	state.info_queue.ClearStoredMessages(state.info_queue)
}

d3d11_drain_info_queue :: proc(ctx: ^Context, state: ^D3D11_State, op: string) -> bool {
	if state == nil || state.info_queue == nil {
		return true
	}

	count := state.info_queue.GetNumStoredMessagesAllowedByRetrievalFilter(state.info_queue)
	if count == 0 {
		return true
	}
	if count > D3D11_INFO_QUEUE_MESSAGE_LIMIT {
		count = D3D11_INFO_QUEUE_MESSAGE_LIMIT
	}

	warning: string
	for index: u64 = 0; index < count; index += 1 {
		message_size: d3d11.SIZE_T
		hr := state.info_queue.GetMessage(state.info_queue, index, nil, &message_size)
		if d3d11_failed(hr) || message_size == 0 {
			continue
		}

		message_bytes := make([]u8, int(message_size), context.temp_allocator)
		message := cast(^d3d11.MESSAGE)raw_data(message_bytes)
		hr = state.info_queue.GetMessage(state.info_queue, index, message, &message_size)
		if d3d11_failed(hr) {
			continue
		}

		if message.Severity == .CORRUPTION || message.Severity == .ERROR {
			set_backend_errorf(
				ctx,
				"gfx.d3d11: debug layer %s after %s: %s",
				d3d11_info_queue_severity_name(message.Severity),
				op,
				string(message.pDescription),
			)
			state.info_queue.ClearStoredMessages(state.info_queue)
			return false
		}
		if warning == "" && message.Severity == .WARNING {
			warning = string(message.pDescription)
		}
	}

	state.info_queue.ClearStoredMessages(state.info_queue)
	if warning != "" {
		set_backend_errorf(ctx, "gfx.d3d11: debug layer warning after %s: %s", op, warning)
	}
	return true
}

d3d11_info_queue_severity_name :: proc(severity: d3d11.MESSAGE_SEVERITY) -> string {
	switch severity {
	case .CORRUPTION:
		return "corruption"
	case .ERROR:
		return "error"
	case .WARNING:
		return "warning"
	case .INFO:
		return "info"
	case .MESSAGE:
		return "message"
	}

	return "message"
}

d3d11_create_device_and_swapchain :: proc(ctx: ^Context, state: ^D3D11_State, debug: bool) -> bool {
	swap_desc := dxgi.SWAP_CHAIN_DESC {
		BufferDesc = dxgi.MODE_DESC {
			Width = state.width,
			Height = state.height,
			RefreshRate = dxgi.RATIONAL{Numerator = 60, Denominator = 1},
			Format = state.format,
			ScanlineOrdering = .UNSPECIFIED,
			Scaling = .UNSPECIFIED,
		},
		SampleDesc = dxgi.SAMPLE_DESC{Count = 1, Quality = 0},
		BufferUsage = dxgi.USAGE{.RENDER_TARGET_OUTPUT},
		BufferCount = 1,
		OutputWindow = cast(dxgi.HWND)ctx.desc.native_window,
		Windowed = win32.TRUE,
		SwapEffect = .DISCARD,
		Flags = {},
	}

	feature_levels := [?]d3d11.FEATURE_LEVEL{._11_0, ._10_1, ._10_0}
	base_flags := d3d11.CREATE_DEVICE_FLAGS{.BGRA_SUPPORT}
	flags := base_flags
	if debug {
		flags += {.DEBUG}
	}
	debug_enabled := debug

	hr := d3d11.CreateDeviceAndSwapChain(
		nil,
		.HARDWARE,
		d3d11.HMODULE(nil),
		flags,
		raw_data(feature_levels[:]),
		u32(len(feature_levels)),
		d3d11.SDK_VERSION,
		&swap_desc,
		&state.swapchain,
		&state.device,
		&state.feature_level,
		&state.immediate,
	)
	debug_hr := hr

	if d3d11_failed(hr) && debug {
		debug_enabled = false
		hr = d3d11.CreateDeviceAndSwapChain(
			nil,
			.HARDWARE,
			d3d11.HMODULE(nil),
			base_flags,
			raw_data(feature_levels[:]),
			u32(len(feature_levels)),
			d3d11.SDK_VERSION,
			&swap_desc,
			&state.swapchain,
			&state.device,
			&state.feature_level,
			&state.immediate,
		)
	}

	if d3d11_failed(hr) {
		if debug && d3d11_failed(debug_hr) {
			set_backend_errorf(
				ctx,
				"gfx.d3d11: CreateDeviceAndSwapChain failed: debug=%s (0x%08X), fallback=%s (0x%08X)",
				d3d11_hresult_name(debug_hr),
				d3d11_hresult_code(debug_hr),
				d3d11_hresult_name(hr),
				d3d11_hresult_code(hr),
			)
		} else {
			d3d11_set_error_hr(ctx, state, "gfx.d3d11: CreateDeviceAndSwapChain failed", hr)
		}
		return false
	}

	state.debug_enabled = debug_enabled
	d3d11_set_device_debug_name(state.device, d3d11_label_or_fallback(ctx.desc.label, "ape gfx d3d11 device"))
	d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)state.immediate, ctx.desc.label, "immediate context")
	d3d11_set_dxgi_debug_name(cast(^dxgi.IObject)state.swapchain, d3d11_label_or_fallback(ctx.desc.label, "ape gfx swapchain"))
	d3d11_init_info_queue(state)
	return true
}

d3d11_create_backbuffer_view :: proc(ctx: ^Context, state: ^D3D11_State) -> bool {
	backbuffer_raw: rawptr
	hr := state.swapchain.GetBuffer(state.swapchain, 0, d3d11.ITexture2D_UUID, &backbuffer_raw)
	if d3d11_failed(hr) {
		d3d11_set_error_hr(ctx, state, "gfx.d3d11: failed to get swapchain backbuffer", hr)
		return false
	}

	backbuffer := cast(^d3d11.ITexture2D)backbuffer_raw
	hr = state.device.CreateRenderTargetView(
		state.device,
		cast(^d3d11.IResource)backbuffer,
		nil,
		&state.backbuffer_rtv,
	)
	backbuffer.Release(backbuffer)

	if d3d11_failed(hr) {
		d3d11_set_error_hr(ctx, state, "gfx.d3d11: failed to create backbuffer render target view", hr)
		return false
	}
	d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)state.backbuffer_rtv, ctx.desc.label, "backbuffer rtv")

	return true
}

d3d11_create_default_depth_view :: proc(ctx: ^Context, state: ^D3D11_State) -> bool {
	texture_desc := d3d11.TEXTURE2D_DESC {
		Width = state.width,
		Height = state.height,
		MipLevels = 1,
		ArraySize = 1,
		Format = .D32_FLOAT,
		SampleDesc = dxgi.SAMPLE_DESC{Count = 1, Quality = 0},
		Usage = .DEFAULT,
		BindFlags = d3d11.BIND_FLAGS{.DEPTH_STENCIL},
		CPUAccessFlags = {},
		MiscFlags = {},
	}

	hr := state.device.CreateTexture2D(state.device, &texture_desc, nil, &state.default_depth_texture)
	if d3d11_failed(hr) {
		d3d11_set_error_hr(ctx, state, "gfx.d3d11: failed to create default depth texture", hr)
		return false
	}
	d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)state.default_depth_texture, ctx.desc.label, "default depth texture")

	hr = state.device.CreateDepthStencilView(
		state.device,
		cast(^d3d11.IResource)state.default_depth_texture,
		nil,
		&state.default_depth_dsv,
	)
	if d3d11_failed(hr) {
		d3d11_set_error_hr(ctx, state, "gfx.d3d11: failed to create default depth view", hr)
		return false
	}
	d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)state.default_depth_dsv, ctx.desc.label, "default depth dsv")

	return true
}

d3d11_release_default_views :: proc(state: ^D3D11_State) {
	if state == nil {
		return
	}

	if state.backbuffer_rtv != nil {
		state.backbuffer_rtv.Release(state.backbuffer_rtv)
		state.backbuffer_rtv = nil
	}
	if state.default_depth_dsv != nil {
		state.default_depth_dsv.Release(state.default_depth_dsv)
		state.default_depth_dsv = nil
	}
	if state.default_depth_texture != nil {
		state.default_depth_texture.Release(state.default_depth_texture)
		state.default_depth_texture = nil
	}
}

d3d11_clear_graphics_resource_bindings :: proc(state: ^D3D11_State) {
	if state == nil || state.immediate == nil {
		return
	}

	null_srvs: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	state.immediate.VSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	state.immediate.PSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
}

d3d11_clear_compute_resource_bindings :: proc(state: ^D3D11_State) {
	if state == nil || state.immediate == nil {
		return
	}

	null_srvs: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	null_uavs: [D3D11_MAX_UAV_SLOTS]^d3d11.IUnorderedAccessView
	state.immediate.CSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	state.immediate.CSSetUnorderedAccessViews(state.immediate, 0, D3D11_MAX_UAV_SLOTS, &null_uavs[0], nil)
}

d3d11_create_pipeline_states :: proc(ctx: ^Context, state: ^D3D11_State, pipeline_info: ^D3D11_Pipeline, desc: Pipeline_Desc) -> bool {
	raster_desc := d3d11.RASTERIZER_DESC {
		FillMode = d3d11_fill_mode(desc.raster.fill_mode),
		CullMode = d3d11_cull_mode(desc.raster.cull_mode),
		FrontCounterClockwise = d3d11_bool(desc.raster.winding == .Counter_Clockwise),
		DepthBias = 0,
		DepthBiasClamp = 0,
		SlopeScaledDepthBias = 0,
		DepthClipEnable = win32.TRUE,
		ScissorEnable = win32.FALSE,
		MultisampleEnable = win32.FALSE,
		AntialiasedLineEnable = win32.FALSE,
	}
	hr := state.device.CreateRasterizerState(state.device, &raster_desc, &pipeline_info.raster_state)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: CreateRasterizerState failed")
		return false
	}

	depth_desc := d3d11.DEPTH_STENCIL_DESC {
		DepthEnable = d3d11_bool(desc.depth.enabled),
		DepthWriteMask = d3d11_depth_write_mask(desc.depth.write_enabled),
		DepthFunc = d3d11_compare_func(desc.depth.compare),
		StencilEnable = win32.FALSE,
		StencilReadMask = 0xff,
		StencilWriteMask = 0xff,
		FrontFace = d3d11_default_stencil_op_desc(),
		BackFace = d3d11_default_stencil_op_desc(),
	}
	hr = state.device.CreateDepthStencilState(state.device, &depth_desc, &pipeline_info.depth_stencil_state)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: CreateDepthStencilState failed")
		return false
	}

	blend_desc: d3d11.BLEND_DESC
	blend_desc.AlphaToCoverageEnable = win32.FALSE
	blend_desc.IndependentBlendEnable = win32.FALSE
	for i in 0..<8 {
		blend_desc.RenderTarget[i] = d3d11_render_target_blend_desc(desc.colors[i])
	}

	hr = state.device.CreateBlendState(state.device, &blend_desc, &pipeline_info.blend_state)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: CreateBlendState failed")
		return false
	}

	return true
}

d3d11_release_state :: proc(state: ^D3D11_State) {
	if state == nil {
		return
	}

	if state.immediate != nil {
		state.immediate.ClearState(state.immediate)
	}

	if state.compute_pipelines != nil {
		delete(state.compute_pipelines)
	}
	if state.pipelines != nil {
		for _, &pipeline_info in state.pipelines {
			d3d11_release_pipeline(&pipeline_info)
		}
		delete(state.pipelines)
	}
	if state.shaders != nil {
		for _, &shader_info in state.shaders {
			d3d11_release_shader(&shader_info)
		}
		delete(state.shaders)
	}
	if state.buffers != nil {
		for _, buffer_info in state.buffers {
			if buffer_info.buffer != nil {
				buffer_info.buffer.Release(buffer_info.buffer)
			}
		}
		delete(state.buffers)
	}
	if state.views != nil {
		for _, view_info in state.views {
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
		}
		delete(state.views)
	}
	if state.images != nil {
		for _, image_info in state.images {
			if image_info.texture2d != nil {
				image_info.texture2d.Release(image_info.texture2d)
			}
		}
		delete(state.images)
	}
	if state.samplers != nil {
		for _, sampler_info in state.samplers {
			if sampler_info.sampler != nil {
				sampler_info.sampler.Release(sampler_info.sampler)
			}
		}
		delete(state.samplers)
	}
	for slot in 0..<MAX_UNIFORM_BLOCKS {
		if state.uniform_buffers[slot] != nil {
			state.uniform_buffers[slot].Release(state.uniform_buffers[slot])
			state.uniform_buffers[slot] = nil
			state.uniform_buffer_sizes[slot] = 0
		}
	}

	d3d11_release_default_views(state)
	if state.swapchain != nil {
		state.swapchain.SetFullscreenState(state.swapchain, win32.FALSE, nil)
		state.swapchain.Release(state.swapchain)
		state.swapchain = nil
	}
	if state.info_queue != nil {
		state.info_queue.Release(state.info_queue)
		state.info_queue = nil
	}
	if state.immediate != nil {
		state.immediate.Release(state.immediate)
		state.immediate = nil
	}
	if state.device != nil {
		state.device.Release(state.device)
		state.device = nil
	}
}

d3d11_ensure_uniform_buffer :: proc(ctx: ^Context, state: ^D3D11_State, slot: int, size: u32) -> bool {
	if state.uniform_buffers[slot] != nil && state.uniform_buffer_sizes[slot] >= size {
		return true
	}

	if state.uniform_buffers[slot] != nil {
		state.uniform_buffers[slot].Release(state.uniform_buffers[slot])
		state.uniform_buffers[slot] = nil
		state.uniform_buffer_sizes[slot] = 0
	}

	desc := d3d11.BUFFER_DESC {
		ByteWidth = size,
		Usage = .DYNAMIC,
		BindFlags = d3d11.BIND_FLAGS{.CONSTANT_BUFFER},
		CPUAccessFlags = d3d11.CPU_ACCESS_FLAGS{.WRITE},
		MiscFlags = {},
		StructureByteStride = 0,
	}

	hr := state.device.CreateBuffer(state.device, &desc, nil, &state.uniform_buffers[slot])
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to create uniform buffer")
		return false
	}
	label_storage: [64]u8
	label := fmt.bprintf(label_storage[:], "uniform buffer %d", slot)
	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)state.uniform_buffers[slot], label)

	state.uniform_buffer_sizes[slot] = size
	return true
}

d3d11_uniform_buffer_size :: proc(size: int) -> u32 {
	if size <= 0 {
		return 0
	}

	aligned := ((size + 15) / 16) * 16
	return u32(aligned)
}

d3d11_release_shader :: proc(shader_info: ^D3D11_Shader) {
	if shader_info == nil {
		return
	}

	if shader_info.vertex != nil {
		shader_info.vertex.Release(shader_info.vertex)
		shader_info.vertex = nil
	}
	if shader_info.pixel != nil {
		shader_info.pixel.Release(shader_info.pixel)
		shader_info.pixel = nil
	}
	if shader_info.compute != nil {
		shader_info.compute.Release(shader_info.compute)
		shader_info.compute = nil
	}
	if shader_info.vertex_bytecode != nil {
		delete(shader_info.vertex_bytecode)
		shader_info.vertex_bytecode = nil
	}
}

d3d11_release_pipeline :: proc(pipeline_info: ^D3D11_Pipeline) {
	if pipeline_info == nil {
		return
	}

	if pipeline_info.input_layout != nil {
		pipeline_info.input_layout.Release(pipeline_info.input_layout)
		pipeline_info.input_layout = nil
	}
	if pipeline_info.raster_state != nil {
		pipeline_info.raster_state.Release(pipeline_info.raster_state)
		pipeline_info.raster_state = nil
	}
	if pipeline_info.depth_stencil_state != nil {
		pipeline_info.depth_stencil_state.Release(pipeline_info.depth_stencil_state)
		pipeline_info.depth_stencil_state = nil
	}
	if pipeline_info.blend_state != nil {
		pipeline_info.blend_state.Release(pipeline_info.blend_state)
		pipeline_info.blend_state = nil
	}
}

d3d11_copy_range :: proc(data: Range) -> []u8 {
	if data.ptr == nil || data.size <= 0 {
		return nil
	}

	result := make([]u8, data.size)
	mem.copy(raw_data(result), data.ptr, data.size)
	return result
}

d3d11_validate_buffer_usage :: proc(ctx: ^Context, usage: Buffer_Usage) -> bool {
	role_count := 0
	if .Vertex in usage {
		role_count += 1
	}
	if .Index in usage {
		role_count += 1
	}
	if .Uniform in usage {
		role_count += 1
	}
	if .Storage in usage {
		role_count += 1
	}
	if role_count == 0 {
		set_validation_error(ctx, "gfx.d3d11: buffer usage must include at least one role flag")
		return false
	}

	update_count := 0
	if .Immutable in usage {
		update_count += 1
	}
	if .Dynamic_Update in usage {
		update_count += 1
	}
	if .Stream_Update in usage {
		update_count += 1
	}
	if update_count == 0 && !(.Storage in usage) {
		set_validation_error(ctx, "gfx.d3d11: buffer usage must include an update/lifetime flag")
		return false
	}
	if update_count > 1 {
		set_validation_error(ctx, "gfx.d3d11: buffer usage has conflicting update/lifetime flags")
		return false
	}
	if .Storage in usage && (.Immutable in usage || .Dynamic_Update in usage || .Stream_Update in usage) {
		set_validation_error(ctx, "gfx.d3d11: storage buffers are GPU-only for now and must not use update/lifetime flags")
		return false
	}

	return true
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

d3d11_buffer_usage :: proc(usage: Buffer_Usage) -> d3d11.USAGE {
	if .Storage in usage {
		return .DEFAULT
	}
	if .Immutable in usage {
		return .IMMUTABLE
	}
	if .Dynamic_Update in usage || .Stream_Update in usage {
		return .DYNAMIC
	}

	return .IMMUTABLE
}

d3d11_buffer_cpu_access :: proc(usage: Buffer_Usage) -> d3d11.CPU_ACCESS_FLAGS {
	if .Dynamic_Update in usage || .Stream_Update in usage {
		return d3d11.CPU_ACCESS_FLAGS{.WRITE}
	}

	return {}
}

d3d11_buffer_misc_flags :: proc(usage: Buffer_Usage, storage_stride: int) -> d3d11.RESOURCE_MISC_FLAGS {
	if .Storage in usage {
		if storage_stride > 0 {
			return {.BUFFER_STRUCTURED}
		}
		return {.BUFFER_ALLOW_RAW_VIEWS}
	}

	return {}
}

d3d11_buffer_bind_flags :: proc(usage: Buffer_Usage) -> d3d11.BIND_FLAGS {
	flags: d3d11.BIND_FLAGS
	if .Vertex in usage {
		flags += {.VERTEX_BUFFER}
	}
	if .Index in usage {
		flags += {.INDEX_BUFFER}
	}
	if .Uniform in usage {
		flags += {.CONSTANT_BUFFER}
	}
	if .Storage in usage {
		flags += {.SHADER_RESOURCE, .UNORDERED_ACCESS}
	}

	return flags
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

d3d11_buffer_has_cpu_update :: proc(usage: Buffer_Usage) -> bool {
	return .Dynamic_Update in usage || .Stream_Update in usage
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

d3d11_validate_pipeline_vertex_inputs :: proc(ctx: ^Context, shader_info: D3D11_Shader, layout: Layout_Desc) -> bool {
	if !shader_info.has_vertex_input_metadata {
		return true
	}

	for input in shader_info.vertex_inputs {
		if !input.active {
			continue
		}

		attr, attr_ok := d3d11_find_layout_attr(layout, input.semantic, input.semantic_index)
		if !attr_ok {
			set_validation_errorf(ctx, "gfx.d3d11: pipeline layout is missing shader vertex input %s%d", input.semantic, input.semantic_index)
			return false
		}
		if attr.format != input.format {
			set_validation_errorf(ctx, "gfx.d3d11: pipeline vertex input %s%d format does not match shader reflection", input.semantic, input.semantic_index)
			return false
		}
	}

	for attr in layout.attrs {
		if !vertex_attr_desc_active(attr) {
			continue
		}
		if !d3d11_shader_has_vertex_input(shader_info, string(attr.semantic), attr.semantic_index) {
			set_validation_errorf(ctx, "gfx.d3d11: pipeline layout declares unused shader vertex input %s%d", string(attr.semantic), attr.semantic_index)
			return false
		}
	}

	return true
}

d3d11_find_layout_attr :: proc(layout: Layout_Desc, semantic: string, semantic_index: u32) -> (Vertex_Attribute_Desc, bool) {
	for attr in layout.attrs {
		if !vertex_attr_desc_active(attr) || attr.semantic == nil {
			continue
		}
		if string(attr.semantic) == semantic && attr.semantic_index == semantic_index {
			return attr, true
		}
	}

	return {}, false
}

d3d11_shader_has_vertex_input :: proc(shader_info: D3D11_Shader, semantic: string, semantic_index: u32) -> bool {
	for input in shader_info.vertex_inputs {
		if input.active && input.semantic == semantic && input.semantic_index == semantic_index {
			return true
		}
	}

	return false
}

d3d11_validate_pipeline_pass_compatibility :: proc(ctx: ^Context, state: ^D3D11_State, pipeline_info: ^D3D11_Pipeline) -> bool {
	if pipeline_info.depth_only && state.current_pass_has_color {
		set_validation_error(ctx, "gfx.d3d11: depth-only pipeline cannot be applied to a pass with color attachments")
		return false
	}

	for slot in 0..<MAX_COLOR_ATTACHMENTS {
		pipeline_format := pipeline_info.color_formats[slot]
		pass_format := state.current_pass_color_formats[slot]

		if pass_format != .Invalid && pipeline_format == .Invalid {
			set_validation_errorf(ctx, "gfx.d3d11: active pass color attachment slot %d has no matching pipeline color format", slot)
			return false
		}
		if pipeline_format == .Invalid {
			continue
		}

		if pass_format == .Invalid {
			set_validation_errorf(ctx, "gfx.d3d11: pipeline requires color attachment slot %d", slot)
			return false
		}
		if pipeline_format != pass_format {
			set_validation_errorf(ctx, "gfx.d3d11: pipeline color format mismatch at slot %d", slot)
			return false
		}
	}

	if pipeline_info.depth_enabled {
		if !state.current_pass_has_depth {
			set_validation_error(ctx, "gfx.d3d11: depth-enabled pipeline requires a depth attachment")
			return false
		}
		if pipeline_info.depth_format != state.current_pass_depth_format {
			set_validation_error(ctx, "gfx.d3d11: pipeline depth format does not match the active pass")
			return false
		}
	}

	return true
}

d3d11_validate_draw_bindings :: proc(ctx: ^Context, state: ^D3D11_State, pipeline_info: ^D3D11_Pipeline) -> bool {
	missing_vertex_buffers := pipeline_info.required_vertex_buffers & ~state.current_vertex_buffers
	if missing_vertex_buffers != 0 {
		set_validation_errorf(ctx, "gfx.d3d11: missing required vertex buffer slot %d", d3d11_first_binding_slot(missing_vertex_buffers))
		return false
	}

	if pipeline_info.has_index_buffer && !state.current_index_buffer {
		set_validation_error(ctx, "gfx.d3d11: indexed pipeline requires an index buffer")
		return false
	}

	if !pipeline_info.has_binding_metadata {
		return true
	}

	for stage in 0..<2 {
		required := pipeline_info.required[stage]
		current := state.current_bindings[stage]

		missing_uniforms := required.uniforms & ~current.uniforms
		if missing_uniforms != 0 {
			set_validation_errorf(
				ctx,
				"gfx.d3d11: missing required %s uniform slot %d",
				d3d11_stage_name(stage),
				d3d11_first_binding_slot(missing_uniforms),
			)
			return false
		}

		missing_views := required.views & ~current.views
		if missing_views != 0 {
			set_validation_errorf(
				ctx,
				"gfx.d3d11: missing required %s resource view slot %d",
				d3d11_stage_name(stage),
				d3d11_first_binding_slot(missing_views),
			)
			return false
		}

		missing_samplers := required.samplers & ~current.samplers
		if missing_samplers != 0 {
			set_validation_errorf(
				ctx,
				"gfx.d3d11: missing required %s sampler slot %d",
				d3d11_stage_name(stage),
				d3d11_first_binding_slot(missing_samplers),
			)
			return false
		}
	}

	return true
}

d3d11_validate_resource_view_binding :: proc(
	ctx: ^Context,
	view_info: ^D3D11_View,
	binding_slot: D3D11_Binding_Slot,
	logical_slot: u32,
	allow_storage: bool,
) -> bool {
	expected_kind := binding_slot.view_kind
	if !d3d11_resource_view_kind_supported(expected_kind) {
		set_unsupported_errorf(ctx, "gfx.d3d11: resource view slot %d has unsupported reflected view kind", logical_slot)
		return false
	}

	if view_info.kind != expected_kind {
		set_validation_errorf(
			ctx,
			"gfx.d3d11: resource view slot %d expects %s view, got %s view",
			logical_slot,
			d3d11_view_kind_name(expected_kind),
			d3d11_view_kind_name(view_info.kind),
		)
		return false
	}

	switch expected_kind {
	case .Sampled:
		if view_info.srv == nil {
			set_validation_errorf(ctx, "gfx.d3d11: sampled resource view slot %d has no shader resource view", logical_slot)
			return false
		}
		return true
	case .Storage_Image, .Storage_Buffer:
		if view_info.uav == nil {
			set_validation_errorf(ctx, "gfx.d3d11: storage resource view slot %d has no unordered access view", logical_slot)
			return false
		}
		if !allow_storage {
			set_unsupported_errorf(ctx, "gfx.d3d11: storage resource view slot %d is reflected but storage bindings are not implemented for graphics passes yet", logical_slot)
			return false
		}
		if expected_kind == .Storage_Image &&
		   binding_slot.storage_image_format != .Invalid &&
		   view_info.format != binding_slot.storage_image_format {
			set_validation_errorf(
				ctx,
				"gfx.d3d11: storage image resource view slot %d expects format %s, got %s",
				logical_slot,
				d3d11_pixel_format_name(binding_slot.storage_image_format),
				d3d11_pixel_format_name(view_info.format),
			)
			return false
		}
		if expected_kind == .Storage_Buffer {
			if binding_slot.storage_buffer_stride > 0 && view_info.storage_stride != binding_slot.storage_buffer_stride {
				set_validation_errorf(
					ctx,
					"gfx.d3d11: storage buffer resource view slot %d expects stride %d, got %d",
					logical_slot,
					binding_slot.storage_buffer_stride,
					view_info.storage_stride,
				)
				return false
			}
			if binding_slot.access == .Read && view_info.srv == nil {
				set_validation_errorf(ctx, "gfx.d3d11: storage buffer resource view slot %d has no shader resource view", logical_slot)
				return false
			}
			if binding_slot.access != .Read && view_info.uav == nil {
				set_validation_errorf(ctx, "gfx.d3d11: storage buffer resource view slot %d has no unordered access view", logical_slot)
				return false
			}
		}
		return true
	case .Color_Attachment, .Depth_Stencil_Attachment:
	}

	return false
}

d3d11_resource_view_kind_supported :: proc(kind: View_Kind) -> bool {
	switch kind {
	case .Sampled, .Storage_Image, .Storage_Buffer:
		return true
	case .Color_Attachment, .Depth_Stencil_Attachment:
		return false
	}

	return false
}

d3d11_validate_uniform_upload :: proc(ctx: ^Context, pipeline_info: ^D3D11_Pipeline, slot: int, size: int) -> bool {
	if !pipeline_info.has_binding_metadata {
		return true
	}

	slot_mask := d3d11_slot_mask(u32(slot))
	used := false
	expected_size: u32
	for stage in 0..<2 {
		if pipeline_info.required[stage].uniforms & slot_mask == 0 {
			continue
		}

		used = true
		reflected_size := pipeline_info.uniform_slots[stage][slot].size
		if reflected_size == 0 {
			continue
		}
		if expected_size != 0 && expected_size != reflected_size {
			set_validation_errorf(ctx, "gfx.d3d11: uniform slot %d has conflicting reflected sizes across stages", slot)
			return false
		}
		expected_size = reflected_size
	}

	if !used {
		set_validation_errorf(ctx, "gfx.d3d11: uniform slot %d is not used by the current pipeline", slot)
		return false
	}
	if expected_size != 0 && u32(size) != expected_size {
		set_validation_errorf(ctx, "gfx.d3d11: uniform slot %d data size %d does not match reflected size %d", slot, size, expected_size)
		return false
	}

	return true
}

d3d11_validate_compute_uniform_upload :: proc(ctx: ^Context, pipeline_info: ^D3D11_Compute_Pipeline, slot: int, size: int) -> bool {
	if !pipeline_info.has_binding_metadata {
		return true
	}

	compute_stage := int(Shader_Stage.Compute)
	binding_slot := pipeline_info.uniform_slots[compute_stage][slot]
	if !binding_slot.active {
		set_validation_errorf(ctx, "gfx.d3d11: uniform slot %d is not used by the current compute pipeline", slot)
		return false
	}
	if binding_slot.size != 0 && u32(size) != binding_slot.size {
		set_validation_errorf(ctx, "gfx.d3d11: uniform slot %d data size %d does not match reflected size %d", slot, size, binding_slot.size)
		return false
	}

	return true
}

d3d11_validate_dispatch_bindings :: proc(ctx: ^Context, state: ^D3D11_State, pipeline_info: ^D3D11_Compute_Pipeline) -> bool {
	if !pipeline_info.has_binding_metadata {
		return true
	}

	stage := int(Shader_Stage.Compute)
	required := pipeline_info.required[stage]
	current := state.current_bindings[stage]

	missing_uniforms := required.uniforms & ~current.uniforms
	if missing_uniforms != 0 {
		set_validation_errorf(
			ctx,
			"gfx.d3d11: missing required compute uniform slot %d",
			d3d11_first_binding_slot(missing_uniforms),
		)
		return false
	}

	missing_views := required.views & ~current.views
	if missing_views != 0 {
		set_validation_errorf(
			ctx,
			"gfx.d3d11: missing required compute resource view slot %d",
			d3d11_first_binding_slot(missing_views),
		)
		return false
	}

	missing_samplers := required.samplers & ~current.samplers
	if missing_samplers != 0 {
		set_validation_errorf(
			ctx,
			"gfx.d3d11: missing required compute sampler slot %d",
			d3d11_first_binding_slot(missing_samplers),
		)
		return false
	}

	return true
}

d3d11_slot_mask :: proc(slot: u32) -> u32 {
	return u32(1) << slot
}

d3d11_binding_count :: proc(mask: u32) -> u32 {
	count: u32
	remaining := mask
	for remaining != 0 {
		count += 1
		remaining >>= 1
	}
	return count
}

d3d11_binding_span :: proc(mask: u32) -> u32 {
	span: u32
	for slot in 0..<32 {
		slot_u32 := u32(slot)
		if mask & d3d11_slot_mask(slot_u32) != 0 {
			span = slot_u32 + 1
		}
	}
	return span
}

d3d11_first_binding_slot :: proc(mask: u32) -> u32 {
	for slot in 0..<32 {
		slot_u32 := u32(slot)
		if mask & d3d11_slot_mask(slot_u32) != 0 {
			return slot_u32
		}
	}
	return 0
}

d3d11_stage_name :: proc(stage: int) -> string {
	switch Shader_Stage(stage) {
	case .Vertex:
		return "vertex"
	case .Fragment:
		return "fragment"
	case .Compute:
		return "compute"
	}

	return "unknown"
}

d3d11_view_kind_name :: proc(kind: View_Kind) -> string {
	switch kind {
	case .Sampled:
		return "sampled"
	case .Storage_Image:
		return "storage image"
	case .Storage_Buffer:
		return "storage buffer"
	case .Color_Attachment:
		return "color attachment"
	case .Depth_Stencil_Attachment:
		return "depth-stencil attachment"
	}

	return "unknown"
}

d3d11_pixel_format_name :: proc(format: Pixel_Format) -> string {
	switch format {
	case .Invalid:
		return "Invalid"
	case .RGBA8:
		return "RGBA8"
	case .BGRA8:
		return "BGRA8"
	case .RGBA16F:
		return "RGBA16F"
	case .RGBA32F:
		return "RGBA32F"
	case .R32F:
		return "R32F"
	case .D24S8:
		return "D24S8"
	case .D32F:
		return "D32F"
	}

	return "Unknown"
}

d3d11_mip_dimension :: proc(value, mip_level: u32) -> u32 {
	result := value >> mip_level
	if result == 0 {
		return 1
	}
	return result
}

d3d11_pixel_size :: proc(format: Pixel_Format) -> u32 {
	switch format {
	case .RGBA8, .BGRA8:
		return 4
	case .RGBA16F:
		return 8
	case .RGBA32F:
		return 16
	case .R32F, .D32F:
		return 4
	case .D24S8:
		return 4
	case .Invalid:
		return 0
	}

	return 0
}

d3d11_is_color_format :: proc(format: Pixel_Format) -> bool {
	switch format {
	case .RGBA8, .BGRA8, .RGBA16F, .RGBA32F, .R32F:
		return true
	case .Invalid, .D24S8, .D32F:
		return false
	}

	return false
}

d3d11_is_depth_format :: proc(format: Pixel_Format) -> bool {
	switch format {
	case .D24S8, .D32F:
		return true
	case .Invalid, .RGBA8, .BGRA8, .RGBA16F, .RGBA32F, .R32F:
		return false
	}

	return false
}

d3d11_filter :: proc(min_filter, mag_filter, mip_filter: Filter) -> d3d11.FILTER {
	min_linear := min_filter == .Linear
	mag_linear := mag_filter == .Linear
	mip_linear := mip_filter == .Linear

	if min_linear {
		if mag_linear {
			if mip_linear {
				return .MIN_MAG_MIP_LINEAR
			}
			return .MIN_MAG_LINEAR_MIP_POINT
		}
		if mip_linear {
			return .MIN_LINEAR_MAG_POINT_MIP_LINEAR
		}
		return .MIN_LINEAR_MAG_MIP_POINT
	}

	if mag_linear {
		if mip_linear {
			return .MIN_POINT_MAG_MIP_LINEAR
		}
		return .MIN_POINT_MAG_LINEAR_MIP_POINT
	}
	if mip_linear {
		return .MIN_MAG_POINT_MIP_LINEAR
	}
	return .MIN_MAG_MIP_POINT
}

d3d11_wrap :: proc(wrap: Wrap) -> d3d11.TEXTURE_ADDRESS_MODE {
	switch wrap {
	case .Repeat:
		return .WRAP
	case .Clamp_To_Edge:
		return .CLAMP
	case .Mirrored_Repeat:
		return .MIRROR
	}

	return .WRAP
}

d3d11_bool :: proc(value: bool) -> d3d11.BOOL {
	if value {
		return win32.TRUE
	}

	return win32.FALSE
}

d3d11_fill_mode :: proc(fill_mode: Fill_Mode) -> d3d11.FILL_MODE {
	switch fill_mode {
	case .Solid:
		return .SOLID
	case .Wireframe:
		return .WIREFRAME
	}

	return .SOLID
}

d3d11_cull_mode :: proc(cull_mode: Cull_Mode) -> d3d11.CULL_MODE {
	switch cull_mode {
	case .None:
		return .NONE
	case .Front:
		return .FRONT
	case .Back:
		return .BACK
	}

	return .NONE
}

d3d11_compare_func :: proc(compare: Compare_Func) -> d3d11.COMPARISON_FUNC {
	switch compare {
	case .Always:
		return .ALWAYS
	case .Never:
		return .NEVER
	case .Less:
		return .LESS
	case .Less_Equal:
		return .LESS_EQUAL
	case .Equal:
		return .EQUAL
	case .Greater_Equal:
		return .GREATER_EQUAL
	case .Greater:
		return .GREATER
	case .Not_Equal:
		return .NOT_EQUAL
	}

	return .ALWAYS
}

d3d11_depth_write_mask :: proc(write_enabled: bool) -> d3d11.DEPTH_WRITE_MASK {
	if write_enabled {
		return .ALL
	}

	return .ZERO
}

d3d11_default_stencil_op_desc :: proc() -> d3d11.DEPTH_STENCILOP_DESC {
	return d3d11.DEPTH_STENCILOP_DESC {
		StencilFailOp = .KEEP,
		StencilDepthFailOp = .KEEP,
		StencilPassOp = .KEEP,
		StencilFunc = .ALWAYS,
	}
}

d3d11_render_target_blend_desc :: proc(color: Color_State) -> d3d11.RENDER_TARGET_BLEND_DESC {
	blend := color.blend
	return d3d11.RENDER_TARGET_BLEND_DESC {
		BlendEnable = d3d11_bool(blend.enabled),
		SrcBlend = d3d11_blend_factor(blend.src_factor, .ONE),
		DestBlend = d3d11_blend_factor(blend.dst_factor, .ZERO),
		BlendOp = d3d11_blend_op(blend.op),
		SrcBlendAlpha = d3d11_blend_factor(blend.src_alpha_factor, .ONE),
		DestBlendAlpha = d3d11_blend_factor(blend.dst_alpha_factor, .ZERO),
		BlendOpAlpha = d3d11_blend_op(blend.alpha_op),
		RenderTargetWriteMask = d3d11_color_write_mask(color.write_mask),
	}
}

d3d11_blend_factor :: proc(factor: Blend_Factor, fallback: d3d11.BLEND) -> d3d11.BLEND {
	switch factor {
	case .Default:
		return fallback
	case .Zero:
		return .ZERO
	case .One:
		return .ONE
	case .Src_Color:
		return .SRC_COLOR
	case .One_Minus_Src_Color:
		return .INV_SRC_COLOR
	case .Src_Alpha:
		return .SRC_ALPHA
	case .One_Minus_Src_Alpha:
		return .INV_SRC_ALPHA
	case .Dst_Color:
		return .DEST_COLOR
	case .One_Minus_Dst_Color:
		return .INV_DEST_COLOR
	case .Dst_Alpha:
		return .DEST_ALPHA
	case .One_Minus_Dst_Alpha:
		return .INV_DEST_ALPHA
	case .Blend_Color:
		return .BLEND_FACTOR
	case .One_Minus_Blend_Color:
		return .INV_BLEND_FACTOR
	case .Src_Alpha_Saturated:
		return .SRC_ALPHA_SAT
	}

	return fallback
}

d3d11_blend_op :: proc(op: Blend_Op) -> d3d11.BLEND_OP {
	switch op {
	case .Default, .Add:
		return .ADD
	case .Subtract:
		return .SUBTRACT
	case .Reverse_Subtract:
		return .REV_SUBTRACT
	case .Min:
		return .MIN
	case .Max:
		return .MAX
	}

	return .ADD
}

d3d11_color_write_mask :: proc(mask: u8) -> u8 {
	if mask == 0 {
		return COLOR_MASK_RGBA
	}

	return mask & COLOR_MASK_RGBA
}

d3d11_primitive_topology :: proc(primitive: Primitive_Type) -> d3d11.PRIMITIVE_TOPOLOGY {
	switch primitive {
	case .Triangles:
		return .TRIANGLELIST
	case .Lines:
		return .LINELIST
	case .Points:
		return .POINTLIST
	}

	return .TRIANGLELIST
}

d3d11_index_format :: proc(index_type: Index_Type) -> dxgi.FORMAT {
	switch index_type {
	case .Uint16:
		return .R16_UINT
	case .Uint32:
		return .R32_UINT
	case .None:
		return .UNKNOWN
	}

	return .UNKNOWN
}

d3d11_vertex_format :: proc(format: Vertex_Format) -> dxgi.FORMAT {
	switch format {
	case .Float32:
		return .R32_FLOAT
	case .Float32x2:
		return .R32G32_FLOAT
	case .Float32x3:
		return .R32G32B32_FLOAT
	case .Float32x4:
		return .R32G32B32A32_FLOAT
	case .Uint8x4_Norm:
		return .R8G8B8A8_UNORM
	case .Invalid:
		return .UNKNOWN
	}

	return .UNKNOWN
}

d3d11_input_class :: proc(step_func: Vertex_Step_Function) -> d3d11.INPUT_CLASSIFICATION {
	switch step_func {
	case .Per_Vertex:
		return .VERTEX_DATA
	case .Per_Instance:
		return .INSTANCE_DATA
	}

	return .VERTEX_DATA
}

d3d11_dxgi_format :: proc(format: Pixel_Format) -> dxgi.FORMAT {
	switch format {
	case .RGBA8:
		return .R8G8B8A8_UNORM
	case .BGRA8, .Invalid:
		return .B8G8R8A8_UNORM
	case .RGBA16F:
		return .R16G16B16A16_FLOAT
	case .RGBA32F:
		return .R32G32B32A32_FLOAT
	case .R32F:
		return .R32_FLOAT
	case .D24S8:
		return .D24_UNORM_S8_UINT
	case .D32F:
		return .D32_FLOAT
	}

	return .B8G8R8A8_UNORM
}

d3d11_texture_format :: proc(format: Pixel_Format, usage: Image_Usage) -> dxgi.FORMAT {
	if .Depth_Stencil_Attachment in usage && .Texture in usage {
		switch format {
		case .D32F:
			return .R32_TYPELESS
		case .D24S8:
			return .R24G8_TYPELESS
		case .Invalid, .RGBA8, .BGRA8, .RGBA16F, .RGBA32F, .R32F:
		}
	}

	return d3d11_dxgi_format(format)
}

d3d11_srv_format :: proc(format: Pixel_Format) -> dxgi.FORMAT {
	switch format {
	case .D32F:
		return .R32_FLOAT
	case .D24S8:
		return .R24_UNORM_X8_TYPELESS
	case .Invalid, .RGBA8, .BGRA8, .RGBA16F, .RGBA32F, .R32F:
		return d3d11_dxgi_format(format)
	}

	return d3d11_dxgi_format(format)
}

d3d11_dsv_format :: proc(format: Pixel_Format) -> dxgi.FORMAT {
	switch format {
	case .D32F:
		return .D32_FLOAT
	case .D24S8:
		return .D24_UNORM_S8_UINT
	case .Invalid, .RGBA8, .BGRA8, .RGBA16F, .RGBA32F, .R32F:
		return d3d11_dxgi_format(format)
	}

	return d3d11_dxgi_format(format)
}

d3d11_texture2d_dimension_limit :: proc(feature_level: d3d11.FEATURE_LEVEL) -> int {
	switch feature_level {
	case ._10_0, ._10_1:
		return D3D11_FL10_TEXTURE2D_DIMENSION
	case ._11_0, ._11_1, ._12_0, ._12_1:
		return d3d11.REQ_TEXTURE2D_U_OR_V_DIMENSION
	case ._1_0_CORE, ._9_1, ._9_2, ._9_3:
		return d3d11.FL9_3_REQ_TEXTURE2D_U_OR_V_DIMENSION
	}

	return d3d11.REQ_TEXTURE2D_U_OR_V_DIMENSION
}

d3d11_set_error_hr :: proc(ctx: ^Context, state: ^D3D11_State, message: string, hr: d3d11.HRESULT) {
	reason, has_reason := d3d11_device_removed_reason(state)
	if has_reason {
		set_errorf_code(
			ctx,
			.Device_Lost,
			"%s: %s (0x%08X); device removed reason: %s (0x%08X)",
			message,
			d3d11_hresult_name(hr),
			d3d11_hresult_code(hr),
			d3d11_hresult_name(reason),
			d3d11_hresult_code(reason),
		)
		return
	}

	set_errorf_code(ctx, d3d11_error_code_for_hr(hr), "%s: %s (0x%08X)", message, d3d11_hresult_name(hr), d3d11_hresult_code(hr))
}

d3d11_error_code_for_hr :: proc(hr: d3d11.HRESULT) -> Error_Code {
	switch hr {
	case dxgi.ERROR_DEVICE_HUNG,
	     dxgi.ERROR_DEVICE_REMOVED,
	     dxgi.ERROR_DEVICE_RESET,
	     dxgi.ERROR_DRIVER_INTERNAL_ERROR:
		return .Device_Lost
	case dxgi.ERROR_UNSUPPORTED:
		return .Unsupported
	}

	return .Backend
}

d3d11_device_removed_reason :: proc(state: ^D3D11_State) -> (d3d11.HRESULT, bool) {
	if state == nil || state.device == nil {
		return {}, false
	}

	reason := state.device.GetDeviceRemovedReason(state.device)
	return reason, d3d11_failed(reason)
}

d3d11_hresult_name :: proc(hr: d3d11.HRESULT) -> string {
	switch hr {
	case dxgi.ERROR_DEVICE_HUNG:
		return "DXGI_ERROR_DEVICE_HUNG"
	case dxgi.ERROR_DEVICE_REMOVED:
		return "DXGI_ERROR_DEVICE_REMOVED"
	case dxgi.ERROR_DEVICE_RESET:
		return "DXGI_ERROR_DEVICE_RESET"
	case dxgi.ERROR_DRIVER_INTERNAL_ERROR:
		return "DXGI_ERROR_DRIVER_INTERNAL_ERROR"
	case dxgi.ERROR_INVALID_CALL:
		return "DXGI_ERROR_INVALID_CALL"
	case dxgi.ERROR_NOT_CURRENTLY_AVAILABLE:
		return "DXGI_ERROR_NOT_CURRENTLY_AVAILABLE"
	case dxgi.ERROR_UNSUPPORTED:
		return "DXGI_ERROR_UNSUPPORTED"
	case D3D11_E_INVALIDARG:
		return "E_INVALIDARG"
	case D3D11_E_OUTOFMEMORY:
		return "E_OUTOFMEMORY"
	case D3D11_E_FAIL:
		return "E_FAIL"
	}

	return "HRESULT"
}

d3d11_hresult_code :: proc(hr: d3d11.HRESULT) -> u32 {
	return u32(cast(i32)hr)
}

d3d11_failed :: proc(hr: d3d11.HRESULT) -> bool {
	return cast(i32)hr < 0
}

positive_u32_or_default :: proc(value: i32, default_value: u32) -> u32 {
	if value <= 0 {
		return default_value
	}

	return u32(value)
}
