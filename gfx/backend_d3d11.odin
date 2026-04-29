#+private
package gfx

import "core:fmt"
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
	uniforms: [MAX_BINDING_GROUPS]u32,
	views: [MAX_BINDING_GROUPS]u32,
	samplers: [MAX_BINDING_GROUPS]u32,
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

D3D11_Uniform_Slots :: [MAX_BINDING_GROUPS][MAX_UNIFORM_BLOCKS]D3D11_Binding_Slot
D3D11_View_Slots :: [MAX_BINDING_GROUPS][MAX_RESOURCE_VIEWS]D3D11_Binding_Slot
D3D11_Sampler_Slots :: [MAX_BINDING_GROUPS][MAX_SAMPLERS]D3D11_Binding_Slot

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
	uniform_buffers: [MAX_BINDING_GROUPS][MAX_UNIFORM_BLOCKS]^d3d11.IBuffer,
	uniform_buffer_sizes: [MAX_BINDING_GROUPS][MAX_UNIFORM_BLOCKS]u32,
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
	for group in 0..<MAX_BINDING_GROUPS {
		for slot in 0..<MAX_UNIFORM_BLOCKS {
			if state.uniform_buffers[group][slot] != nil {
				state.uniform_buffers[group][slot].Release(state.uniform_buffers[group][slot])
				state.uniform_buffers[group][slot] = nil
				state.uniform_buffer_sizes[group][slot] = 0
			}
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
