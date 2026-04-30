#+private
package gfx

import "core:fmt"
import "core:mem"
import d3d12 "vendor:directx/d3d12"
import dxgi "vendor:directx/dxgi"
import win32 "core:sys/windows"

D3D12_FRAME_COUNT :: 2
D3D12_CBV_SRV_UAV_CPU_CAPACITY :: 8192
D3D12_SAMPLER_CPU_CAPACITY :: 1024
D3D12_CBV_SRV_UAV_GPU_CAPACITY :: 8192
D3D12_SAMPLER_GPU_CAPACITY :: 1024
D3D12_RTV_CAPACITY :: 512
D3D12_DSV_CAPACITY :: 256
D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES :: 0xffffffff
D3D12_DESCRIPTOR_OFFSET_APPEND :: 0xffffffff
D3D12_TEXTURE_DATA_PITCH_ALIGNMENT :: 256
D3D12_CONSTANT_BUFFER_ALIGNMENT :: 256
D3D12_DEFAULT_2D_IMAGE_LIMIT :: 16384
D3D12_MAX_SAMPLE_COUNT :: 8
D3D12_DEBUG_NAME_MAX_UTF16 :: 256

D3D12_Descriptor_Allocator :: struct {
	heap:           ^d3d12.IDescriptorHeap,
	capacity:       u32,
	increment:      u32,
	next:           u32,
	cpu_start:      d3d12.CPU_DESCRIPTOR_HANDLE,
	gpu_start:      d3d12.GPU_DESCRIPTOR_HANDLE,
	shader_visible: bool,
	heap_type:      d3d12.DESCRIPTOR_HEAP_TYPE,
}

D3D12_Buffer :: struct {
	resource:       ^d3d12.IResource,
	upload:         ^d3d12.IResource,
	mapped:         rawptr,
	usage:          Buffer_Usage,
	size:           u64,
	storage_stride: u32,
	state:          d3d12.RESOURCE_STATES,
}

D3D12_Image :: struct {
	resource:     ^d3d12.IResource,
	upload:       ^d3d12.IResource,
	kind:         Image_Kind,
	usage:        Image_Usage,
	width:        u32,
	height:       u32,
	mip_count:    u32,
	array_count:  u32,
	sample_count: u32,
	format:       Pixel_Format,
	state:        d3d12.RESOURCE_STATES,
}

D3D12_View :: struct {
	image:          Image,
	buffer:         Buffer,
	kind:           View_Kind,
	cpu_handle:     d3d12.CPU_DESCRIPTOR_HANDLE,
	has_descriptor: bool,
	width:          u32,
	height:         u32,
	offset:         int,
	size:           int,
	storage_stride: u32,
	mip_level:      u32,
	base_layer:     u32,
	layer_count:    u32,
	format:         Pixel_Format,
	sample_count:   u32,
}

D3D12_Sampler :: struct {
	cpu_handle: d3d12.CPU_DESCRIPTOR_HANDLE,
}

D3D12_Binding_Masks :: struct {
	uniforms: [MAX_BINDING_GROUPS]u32,
	views:    [MAX_BINDING_GROUPS]u32,
	samplers: [MAX_BINDING_GROUPS]u32,
}

D3D12_Binding_Slot :: struct {
	active:                bool,
	native_slot:           u32,
	native_space:          u32,
	array_count:           u32,
	size:                  u32,
	view_kind:             View_Kind,
	access:                Shader_Resource_Access,
	storage_image_format:  Pixel_Format,
	storage_buffer_stride: u32,
}

D3D12_Uniform_Slots :: [MAX_BINDING_GROUPS][MAX_UNIFORM_BLOCKS]D3D12_Binding_Slot
D3D12_View_Slots :: [MAX_BINDING_GROUPS][MAX_RESOURCE_VIEWS]D3D12_Binding_Slot
D3D12_Sampler_Slots :: [MAX_BINDING_GROUPS][MAX_SAMPLERS]D3D12_Binding_Slot

D3D12_Shader :: struct {
	vertex_bytecode: []u8,
	pixel_bytecode:  []u8,
	compute_bytecode: []u8,
	required:        [3]D3D12_Binding_Masks,
	uniform_slots:   [3]D3D12_Uniform_Slots,
	view_slots:      [3]D3D12_View_Slots,
	sampler_slots:   [3]D3D12_Sampler_Slots,
	has_binding_metadata:      bool,
	has_vertex_input_metadata: bool,
	vertex_inputs:             [MAX_VERTEX_ATTRIBUTES]Shader_Vertex_Input_Desc,
}

D3D12_Root_Entry_Kind :: enum {
	Uniform,
	View,
	Sampler,
}

D3D12_Root_Entry :: struct {
	active:          bool,
	kind:            D3D12_Root_Entry_Kind,
	stage:           Shader_Stage,
	group:           u32,
	logical_slot:    u32,
	array_count:     u32,
	table_offset:    u32,
	root_index:      u32,
	native_slot:     u32,
	native_space:    u32,
	descriptor_type: d3d12.DESCRIPTOR_RANGE_TYPE,
	size:            u32,
	view_kind:       View_Kind,
	access:          Shader_Resource_Access,
}

D3D12_Root_Info :: struct {
	root_signature:       ^d3d12.IRootSignature,
	resource_ranges:      [MAX_SHADER_BINDINGS]d3d12.DESCRIPTOR_RANGE,
	sampler_ranges:       [MAX_SHADER_BINDINGS]d3d12.DESCRIPTOR_RANGE,
	resource_entries:     [MAX_SHADER_BINDINGS]D3D12_Root_Entry,
	sampler_entries:      [MAX_SHADER_BINDINGS]D3D12_Root_Entry,
	resource_count:       u32,
	sampler_count:        u32,
	resource_table_count: u32,
	sampler_table_count:  u32,
	resource_root_index:  u32,
	sampler_root_index:   u32,
	has_resource_table:   bool,
	has_sampler_table:    bool,
}

D3D12_Pipeline :: struct {
	shader:                  Shader,
	pso:                     ^d3d12.IPipelineState,
	root:                    D3D12_Root_Info,
	topology:                d3d12.PRIMITIVE_TOPOLOGY,
	topology_type:           d3d12.PRIMITIVE_TOPOLOGY_TYPE,
	index_format:            dxgi.FORMAT,
	vertex_strides:          [MAX_VERTEX_BUFFERS]u32,
	has_index_buffer:        bool,
	required_vertex_buffers: u32,
	required:                [3]D3D12_Binding_Masks,
	uniform_slots:           [3]D3D12_Uniform_Slots,
	view_slots:              [3]D3D12_View_Slots,
	sampler_slots:           [3]D3D12_Sampler_Slots,
	has_binding_metadata:    bool,
	color_formats:           [MAX_COLOR_ATTACHMENTS]Pixel_Format,
	depth_format:            Pixel_Format,
	depth_enabled:           bool,
	depth_only:              bool,
}

D3D12_Compute_Pipeline :: struct {
	shader:               Shader,
	pso:                  ^d3d12.IPipelineState,
	root:                 D3D12_Root_Info,
	required:             [3]D3D12_Binding_Masks,
	uniform_slots:        [3]D3D12_Uniform_Slots,
	view_slots:           [3]D3D12_View_Slots,
	sampler_slots:        [3]D3D12_Sampler_Slots,
	has_binding_metadata: bool,
}

D3D12_Uniform_Binding :: struct {
	resource: ^d3d12.IResource,
	gpu_va:   d3d12.GPU_VIRTUAL_ADDRESS,
	size:     u32,
}

D3D12_Frame_State :: struct {
	backbuffer: ^d3d12.IResource,
	rtv:        d3d12.CPU_DESCRIPTOR_HANDLE,
	state:      d3d12.RESOURCE_STATES,
}

D3D12_State :: struct {
	factory:          ^dxgi.IFactory2,
	device:           ^d3d12.IDevice,
	queue:            ^d3d12.ICommandQueue,
	allocator:        ^d3d12.ICommandAllocator,
	cmd:              ^d3d12.IGraphicsCommandList,
	fence:            ^d3d12.IFence,
	fence_event:      win32.HANDLE,
	fence_value:      u64,
	swapchain:        ^dxgi.ISwapChain3,
	frame_index:      u32,
	width:            u32,
	height:           u32,
	format:           dxgi.FORMAT,
	sync_interval:    u32,
	command_open:     bool,
	backbuffers:      [D3D12_FRAME_COUNT]D3D12_Frame_State,
	default_depth:    ^d3d12.IResource,
	default_depth_dsv: d3d12.CPU_DESCRIPTOR_HANDLE,
	default_depth_state: d3d12.RESOURCE_STATES,
	rtv_heap:         D3D12_Descriptor_Allocator,
	dsv_heap:         D3D12_Descriptor_Allocator,
	cpu_cbv_srv_uav:  D3D12_Descriptor_Allocator,
	cpu_samplers:     D3D12_Descriptor_Allocator,
	gpu_cbv_srv_uav:  D3D12_Descriptor_Allocator,
	gpu_samplers:     D3D12_Descriptor_Allocator,
	buffers:          map[Buffer]D3D12_Buffer,
	images:           map[Image]D3D12_Image,
	views:            map[View]D3D12_View,
	samplers:         map[Sampler]D3D12_Sampler,
	shaders:          map[Shader]D3D12_Shader,
	pipelines:        map[Pipeline]D3D12_Pipeline,
	compute_pipelines: map[Compute_Pipeline]D3D12_Compute_Pipeline,
	uniform_uploads:  [MAX_BINDING_GROUPS][MAX_UNIFORM_BLOCKS]D3D12_Buffer,
	uniform_bindings: [MAX_BINDING_GROUPS][MAX_UNIFORM_BLOCKS]D3D12_Uniform_Binding,
	current_pipeline:         Pipeline,
	current_compute_pipeline: Compute_Pipeline,
	current_user_bindings:    Bindings,
	current_vertex_buffers:   u32,
	current_index_buffer:     bool,
	current_bindings:         [3]D3D12_Binding_Masks,
	current_pass_color_formats: [MAX_COLOR_ATTACHMENTS]Pixel_Format,
	current_pass_has_color:   bool,
	current_pass_depth_format: Pixel_Format,
	current_pass_has_depth:   bool,
	draw_signature:           ^d3d12.ICommandSignature,
	draw_indexed_signature:   ^d3d12.ICommandSignature,
	dispatch_signature:       ^d3d12.ICommandSignature,
	pending_uploads:          [dynamic]^d3d12.IResource,
}

d3d12_init :: proc(ctx: ^Context) -> bool {
	when ODIN_OS != .Windows {
		set_unsupported_error(ctx, "gfx.d3d12: D3D12 backend is Windows-only")
		return false
	}

	if ctx.desc.native_window == nil {
		set_validation_error(ctx, "gfx.d3d12: native_window is required")
		return false
	}

	state := new(D3D12_State)
	ctx.backend_data = state
	state.buffers = make(map[Buffer]D3D12_Buffer)
	state.images = make(map[Image]D3D12_Image)
	state.views = make(map[View]D3D12_View)
	state.samplers = make(map[Sampler]D3D12_Sampler)
	state.shaders = make(map[Shader]D3D12_Shader)
	state.pipelines = make(map[Pipeline]D3D12_Pipeline)
	state.compute_pipelines = make(map[Compute_Pipeline]D3D12_Compute_Pipeline)
	state.pending_uploads = make([dynamic]^d3d12.IResource)
	state.width = positive_u32_or_default(ctx.desc.width, 1280)
	state.height = positive_u32_or_default(ctx.desc.height, 720)
	state.format = d3d12_dxgi_format(ctx.desc.swapchain_format)
	state.sync_interval = 1 if ctx.desc.vsync else 0

	if !d3d12_create_device(ctx, state) ||
	   !d3d12_create_descriptor_heaps(ctx, state) ||
	   !d3d12_create_swapchain(ctx, state) ||
	   !d3d12_create_backbuffers(ctx, state) ||
	   !d3d12_create_default_depth(ctx, state) ||
	   !d3d12_create_command_signatures(ctx, state) {
		d3d12_release_state(state)
		free(state)
		ctx.backend_data = nil
		return false
	}

	return true
}

d3d12_shutdown :: proc(ctx: ^Context) {
	state := d3d12_state(ctx)
	if state == nil {
		return
	}

	d3d12_wait_idle(state)
	d3d12_release_state(state)
	free(state)
	ctx.backend_data = nil
}

d3d12_query_features :: proc(ctx: ^Context) -> Features {
	return {
		backend = .D3D12,
		render_to_texture = true,
		multiple_render_targets = true,
		msaa_render_targets = true,
		depth_attachment = true,
		depth_only_pass = true,
		sampled_depth = true,
		storage_images = true,
		storage_buffers = true,
		compute = true,
		dynamic_textures = true,
		mipmapped_textures = true,
		buffer_updates = true,
		buffer_readback = true,
	}
}

d3d12_query_limits :: proc(ctx: ^Context) -> Limits {
	limits := api_limits()
	limits.max_image_dimension_2d = D3D12_DEFAULT_2D_IMAGE_LIMIT
	limits.max_image_array_layers = 2048
	limits.max_image_sample_count = D3D12_MAX_SAMPLE_COUNT
	limits.max_compute_thread_groups_per_dimension = 65535
	return limits
}

d3d12_create_buffer :: proc(ctx: ^Context, handle: Buffer, desc: Buffer_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d12: device is not initialized")
		return false
	}

	if u64(desc.size) > 0xffffffff {
		set_validation_error(ctx, "gfx.d3d12: buffer size exceeds u32 binding limit")
		return false
	}

	buffer_info: D3D12_Buffer
	buffer_info.usage = desc.usage
	buffer_info.size = u64(desc.size)
	buffer_info.storage_stride = u32(desc.storage_stride)

	heap_type := d3d12_heap_type_for_buffer(desc.usage)
	initial_state := d3d12_initial_buffer_state(desc.usage, heap_type)
	buffer_desc := d3d12_buffer_resource_desc(u64(desc.size), desc.usage)
	heap_props := d3d12_heap_properties(heap_type)

	resource_raw: rawptr
	hr := state.device.CreateCommittedResource(
		state.device,
		&heap_props,
		d3d12.HEAP_FLAG_ALLOW_ALL_BUFFERS_AND_TEXTURES,
		&buffer_desc,
		initial_state,
		nil,
		d3d12.IResource_UUID,
		&resource_raw,
	)
	if d3d12_failed(hr) || resource_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommittedResource(buffer) failed", hr)
		return false
	}
	buffer_info.resource = cast(^d3d12.IResource)resource_raw
	buffer_info.state = initial_state
	d3d12_set_debug_name(cast(^d3d12.IObject)buffer_info.resource, desc.label)

	if heap_type == .UPLOAD {
		read_range := d3d12.RANGE{}
		hr = buffer_info.resource.Map(buffer_info.resource, 0, &read_range, &buffer_info.mapped)
		if d3d12_failed(hr) || buffer_info.mapped == nil {
			buffer_info.resource.Release(buffer_info.resource)
			d3d12_set_error_hr(ctx, "gfx.d3d12: Map(upload buffer) failed", hr)
			return false
		}
		if range_has_data(desc.data) {
			mem.copy(buffer_info.mapped, desc.data.ptr, desc.data.size)
		}
	} else if range_has_data(desc.data) {
		if !d3d12_upload_to_default_buffer(ctx, state, &buffer_info, desc.data) {
			buffer_info.resource.Release(buffer_info.resource)
			return false
		}
	}

	state.buffers[handle] = buffer_info
	return true
}

d3d12_destroy_buffer :: proc(ctx: ^Context, handle: Buffer) {
	state := d3d12_state(ctx)
	if state == nil {
		return
	}
	if buffer_info, ok := state.buffers[handle]; ok {
		d3d12_release_buffer(&buffer_info)
		delete_key(&state.buffers, handle)
	}
}

d3d12_update_buffer :: proc(ctx: ^Context, desc: Buffer_Update_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	buffer_info, ok := &state.buffers[desc.buffer]
	if !ok || buffer_info.resource == nil {
		set_invalid_handle_error(ctx, "gfx.d3d12: buffer handle is unknown")
		return false
	}
	if buffer_info.mapped == nil {
		set_validation_error(ctx, "gfx.d3d12: update_buffer requires an upload-backed dynamic/stream buffer")
		return false
	}
	dst := rawptr(uintptr(buffer_info.mapped) + uintptr(desc.offset))
	mem.copy(dst, desc.data.ptr, desc.data.size)
	return true
}

d3d12_read_buffer :: proc(ctx: ^Context, desc: Buffer_Read_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	buffer_info, ok := &state.buffers[desc.buffer]
	if !ok || buffer_info.resource == nil {
		set_invalid_handle_error(ctx, "gfx.d3d12: buffer handle is unknown")
		return false
	}

	readback_desc := d3d12_buffer_resource_desc(u64(desc.data.size), {})
	heap_props := d3d12_heap_properties(.READBACK)
	readback_raw: rawptr
	hr := state.device.CreateCommittedResource(
		state.device,
		&heap_props,
		d3d12.HEAP_FLAG_ALLOW_ALL_BUFFERS_AND_TEXTURES,
		&readback_desc,
		{.COPY_DEST},
		nil,
		d3d12.IResource_UUID,
		&readback_raw,
	)
	if d3d12_failed(hr) || readback_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommittedResource(readback buffer) failed", hr)
		return false
	}
	readback := cast(^d3d12.IResource)readback_raw
	defer readback.Release(readback)

	if !d3d12_begin_commands(ctx, state) {
		return false
	}
	d3d12_transition_buffer(state, buffer_info, {.COPY_SOURCE})
	state.cmd.CopyBufferRegion(state.cmd, readback, 0, buffer_info.resource, u64(desc.offset), u64(desc.data.size))
	if !d3d12_submit_and_wait(ctx, state) {
		return false
	}

	mapped: rawptr
	read_range := d3d12.RANGE{Begin = 0, End = d3d12.SIZE_T(desc.data.size)}
	hr = readback.Map(readback, 0, &read_range, &mapped)
	if d3d12_failed(hr) || mapped == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: Map(readback buffer) failed", hr)
		return false
	}
	mem.copy(desc.data.ptr, mapped, desc.data.size)
	write_range := d3d12.RANGE{}
	readback.Unmap(readback, 0, &write_range)
	return true
}

d3d12_query_buffer_state :: proc(ctx: ^Context, handle: Buffer) -> Buffer_State {
	state := d3d12_state(ctx)
	if state == nil {
		return {}
	}
	if buffer_info, ok := state.buffers[handle]; ok {
		return {
			valid = buffer_info.resource != nil,
			usage = buffer_info.usage,
			size = int(buffer_info.size),
			storage_stride = int(buffer_info.storage_stride),
		}
	}
	return {}
}

d3d12_create_image :: proc(ctx: ^Context, handle: Image, desc: Image_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d12: device is not initialized")
		return false
	}

	image_info := D3D12_Image {
		kind = desc.kind,
		usage = desc.usage,
		width = u32(desc.width),
		height = u32(desc.height),
		mip_count = u32(image_desc_mip_count(desc)),
		array_count = u32(image_desc_array_count(desc)),
		sample_count = u32(image_desc_sample_count(desc)),
		format = desc.format,
	}

	image_desc := d3d12_image_resource_desc(image_info)
	heap_props := d3d12_heap_properties(.DEFAULT)
	initial_state := d3d12_initial_image_state(image_info.usage)
	clear_value: d3d12.CLEAR_VALUE
	clear_value_ptr: ^d3d12.CLEAR_VALUE
	if d3d12_image_needs_clear_value(image_info.usage) {
		clear_value = d3d12_clear_value_for_image(image_info.format, image_info.usage)
		clear_value_ptr = &clear_value
	}
	resource_raw: rawptr
	hr := state.device.CreateCommittedResource(
		state.device,
		&heap_props,
		d3d12.HEAP_FLAG_ALLOW_ALL_BUFFERS_AND_TEXTURES,
		&image_desc,
		initial_state,
		clear_value_ptr,
		d3d12.IResource_UUID,
		&resource_raw,
	)
	if d3d12_failed(hr) || resource_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommittedResource(image) failed", hr)
		return false
	}
	image_info.resource = cast(^d3d12.IResource)resource_raw
	image_info.state = initial_state
	d3d12_set_debug_name(cast(^d3d12.IObject)image_info.resource, desc.label)

	if .Immutable in desc.usage {
		if !d3d12_upload_initial_image_data(ctx, state, &image_info, desc) {
			image_info.resource.Release(image_info.resource)
			return false
		}
	} else if image_usage_has_dynamic_update(desc.usage) && range_has_data(desc.data) {
		update := Image_Update_Desc {
			image = handle,
			data = desc.data,
			row_pitch = desc.mips[0].row_pitch,
		}
		state.images[handle] = image_info
		if !d3d12_update_image(ctx, update) {
			d3d12_destroy_image(ctx, handle)
			return false
		}
		return true
	}

	state.images[handle] = image_info
	return true
}

d3d12_destroy_image :: proc(ctx: ^Context, handle: Image) {
	state := d3d12_state(ctx)
	if state == nil {
		return
	}
	if image_info, ok := state.images[handle]; ok {
		d3d12_release_image(&image_info)
		delete_key(&state.images, handle)
	}
}

d3d12_update_image :: proc(ctx: ^Context, desc: Image_Update_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	image_info, ok := &state.images[desc.image]
	if !ok || image_info.resource == nil {
		set_invalid_handle_error(ctx, "gfx.d3d12: image handle is unknown")
		return false
	}
	update_width := u32(desc.width)
	update_height := u32(desc.height)
	if update_width == 0 {
		update_width = mip_dimension(image_info.width, u32(desc.mip_level))
	}
	if update_height == 0 {
		update_height = mip_dimension(image_info.height, u32(desc.mip_level))
	}
	row_pitch := u32(desc.row_pitch)
	if row_pitch == 0 {
		row_pitch = update_width * u32(pixel_format_size(image_info.format))
	}
	return d3d12_upload_image_region(ctx, state, image_info, u32(desc.mip_level), u32(desc.array_layer), u32(desc.x), u32(desc.y), update_width, update_height, desc.data, row_pitch)
}

d3d12_resolve_image :: proc(ctx: ^Context, desc: Image_Resolve_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	source, source_ok := &state.images[desc.source]
	dest, dest_ok := &state.images[desc.destination]
	if !source_ok || !dest_ok || source.resource == nil || dest.resource == nil {
		set_invalid_handle_error(ctx, "gfx.d3d12: resolve image handle is unknown")
		return false
	}
	if !d3d12_begin_commands(ctx, state) {
		return false
	}
	d3d12_transition_image(state, source, {.RESOLVE_SOURCE})
	d3d12_transition_image(state, dest, {.RESOLVE_DEST})
	state.cmd.ResolveSubresource(state.cmd, dest.resource, 0, source.resource, 0, d3d12_dxgi_format(source.format))
	d3d12_transition_image(state, dest, d3d12_post_write_image_state(dest.usage))
	return d3d12_submit_and_wait(ctx, state)
}

d3d12_query_image_state :: proc(ctx: ^Context, handle: Image) -> Image_State {
	state := d3d12_state(ctx)
	if state == nil {
		return {}
	}
	if image_info, ok := state.images[handle]; ok {
		return {
			valid = image_info.resource != nil,
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

d3d12_create_view :: proc(ctx: ^Context, handle: View, desc: View_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d12: device is not initialized")
		return false
	}

	kind := view_desc_kind(desc)
	view_info := D3D12_View {kind = kind}
	switch kind {
	case .Storage_Buffer:
		buffer_info, buffer_ok := state.buffers[desc.storage_buffer.buffer]
		if !buffer_ok || buffer_info.resource == nil {
			set_invalid_handle_error(ctx, "gfx.d3d12: storage buffer view handle is unknown")
			return false
		}
		size := desc.storage_buffer.size
		if size == 0 {
			size = int(buffer_info.size) - desc.storage_buffer.offset
		}
		view_info.buffer = desc.storage_buffer.buffer
		view_info.offset = desc.storage_buffer.offset
		view_info.size = size
		view_info.storage_stride = buffer_info.storage_stride
		view_info.cpu_handle = d3d12_alloc_descriptor(&state.cpu_cbv_srv_uav)
		view_info.has_descriptor = true
		d3d12_create_storage_buffer_descriptor(state, buffer_info, view_info)
	case .Sampled, .Storage_Image, .Color_Attachment, .Depth_Stencil_Attachment:
		image := view_desc_image(desc)
		image_info, image_ok := state.images[image]
		if !image_ok || image_info.resource == nil {
			set_invalid_handle_error(ctx, "gfx.d3d12: image view handle is unknown")
			return false
		}
		format := view_desc_format(desc)
		if format == .Invalid {
			format = image_info.format
		}
		view_info.image = image
		view_info.width = image_info.width
		view_info.height = image_info.height
		view_info.format = format
		view_info.sample_count = image_info.sample_count
		switch kind {
		case .Sampled:
			view_info.mip_level = u32(desc.texture.base_mip)
			view_info.layer_count = u32(desc.texture.layer_count)
			if view_info.layer_count == 0 {
				view_info.layer_count = image_info.array_count - u32(desc.texture.base_layer)
			}
			view_info.base_layer = u32(desc.texture.base_layer)
			view_info.cpu_handle = d3d12_alloc_descriptor(&state.cpu_cbv_srv_uav)
			view_info.has_descriptor = true
			d3d12_create_sampled_image_descriptor(state, image_info, view_info, desc.texture.mip_count)
		case .Storage_Image:
			view_info.mip_level = u32(desc.storage_image.mip_level)
			view_info.base_layer = u32(desc.storage_image.base_layer)
			view_info.layer_count = u32(desc.storage_image.layer_count)
			if view_info.layer_count == 0 {
				view_info.layer_count = image_info.array_count - view_info.base_layer
			}
			view_info.cpu_handle = d3d12_alloc_descriptor(&state.cpu_cbv_srv_uav)
			view_info.has_descriptor = true
			d3d12_create_storage_image_descriptor(state, image_info, view_info)
		case .Color_Attachment:
			view_info.mip_level = u32(desc.color_attachment.mip_level)
			view_info.base_layer = u32(desc.color_attachment.layer)
			view_info.layer_count = 1
			view_info.cpu_handle = d3d12_alloc_descriptor(&state.rtv_heap)
			view_info.has_descriptor = true
			d3d12_create_rtv_descriptor(state, image_info, view_info)
		case .Depth_Stencil_Attachment:
			view_info.mip_level = u32(desc.depth_stencil_attachment.mip_level)
			view_info.base_layer = u32(desc.depth_stencil_attachment.layer)
			view_info.layer_count = 1
			view_info.cpu_handle = d3d12_alloc_descriptor(&state.dsv_heap)
			view_info.has_descriptor = true
			d3d12_create_dsv_descriptor(state, image_info, view_info)
		case .Storage_Buffer:
		}
	}

	state.views[handle] = view_info
	return true
}

d3d12_destroy_view :: proc(ctx: ^Context, handle: View) {
	state := d3d12_state(ctx)
	if state == nil {
		return
	}
	delete_key(&state.views, handle)
}

d3d12_query_view_state :: proc(ctx: ^Context, handle: View) -> View_State {
	state := d3d12_state(ctx)
	if state == nil {
		return {}
	}
	if view_info, ok := state.views[handle]; ok {
		return {
			valid = view_info.has_descriptor || view_info.kind == .Storage_Buffer,
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

d3d12_create_sampler :: proc(ctx: ^Context, handle: Sampler, desc: Sampler_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d12: device is not initialized")
		return false
	}
	sampler_info := D3D12_Sampler {
		cpu_handle = d3d12_alloc_descriptor(&state.cpu_samplers),
	}
	sampler_desc := d3d12.SAMPLER_DESC {
		Filter = d3d12_filter(desc.min_filter, desc.mag_filter, desc.mip_filter),
		AddressU = d3d12_wrap(desc.wrap_u),
		AddressV = d3d12_wrap(desc.wrap_v),
		AddressW = d3d12_wrap(desc.wrap_w),
		ComparisonFunc = .ALWAYS,
		MinLOD = 0,
		MaxLOD = 3.402823466e38,
	}
	state.device.CreateSampler(state.device, &sampler_desc, sampler_info.cpu_handle)
	state.samplers[handle] = sampler_info
	return true
}

d3d12_destroy_sampler :: proc(ctx: ^Context, handle: Sampler) {
	state := d3d12_state(ctx)
	if state == nil {
		return
	}
	delete_key(&state.samplers, handle)
}

d3d12_create_shader :: proc(ctx: ^Context, handle: Shader, desc: Shader_Desc) -> bool {
	shader_info := D3D12_Shader {
		has_binding_metadata = desc.has_binding_metadata,
		has_vertex_input_metadata = desc.has_vertex_input_metadata,
		vertex_inputs = desc.vertex_inputs,
	}

	for stage_desc in desc.stages {
		if !range_has_data(stage_desc.bytecode) {
			continue
		}
		bytes := make([]u8, stage_desc.bytecode.size)
		mem.copy(raw_data(bytes), stage_desc.bytecode.ptr, stage_desc.bytecode.size)
		switch stage_desc.stage {
		case .Vertex:
			shader_info.vertex_bytecode = bytes
		case .Fragment:
			shader_info.pixel_bytecode = bytes
		case .Compute:
			shader_info.compute_bytecode = bytes
		}
	}

	for binding in desc.bindings {
		if !binding.active {
			continue
		}
		stage := int(binding.stage)
		slot_count := shader_binding_array_count(binding)
		switch binding.kind {
		case .Uniform_Block:
			info := D3D12_Binding_Slot {
				active = true,
				native_slot = binding.native_slot,
				native_space = binding.native_space,
				array_count = slot_count,
				size = binding.size,
			}
			shader_info.uniform_slots[stage][binding.group][binding.slot] = info
			shader_info.required[stage].uniforms[binding.group] |= d3d12_slot_mask(binding.slot)
		case .Resource_View:
			info := D3D12_Binding_Slot {
				active = true,
				native_slot = binding.native_slot,
				native_space = binding.native_space,
				array_count = slot_count,
				view_kind = binding.view_kind,
				access = binding.access,
				storage_image_format = binding.storage_image_format,
				storage_buffer_stride = binding.storage_buffer_stride,
			}
			for i: u32 = 0; i < slot_count; i += 1 {
				shader_info.view_slots[stage][binding.group][binding.slot + i] = info
				shader_info.required[stage].views[binding.group] |= d3d12_slot_mask(binding.slot + i)
			}
		case .Sampler:
			info := D3D12_Binding_Slot {
				active = true,
				native_slot = binding.native_slot,
				native_space = binding.native_space,
				array_count = slot_count,
			}
			for i: u32 = 0; i < slot_count; i += 1 {
				shader_info.sampler_slots[stage][binding.group][binding.slot + i] = info
				shader_info.required[stage].samplers[binding.group] |= d3d12_slot_mask(binding.slot + i)
			}
		}
	}

	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	state.shaders[handle] = shader_info
	return true
}

d3d12_destroy_shader :: proc(ctx: ^Context, handle: Shader) {
	state := d3d12_state(ctx)
	if state == nil {
		return
	}
	if shader_info, ok := state.shaders[handle]; ok {
		delete(shader_info.vertex_bytecode)
		delete(shader_info.pixel_bytecode)
		delete(shader_info.compute_bytecode)
		delete_key(&state.shaders, handle)
	}
}

d3d12_create_pipeline :: proc(ctx: ^Context, handle: Pipeline, desc: Pipeline_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d12: device is not initialized")
		return false
	}
	shader_info, shader_ok := state.shaders[desc.shader]
	if !shader_ok || len(shader_info.vertex_bytecode) == 0 || len(shader_info.pixel_bytecode) == 0 {
		set_invalid_handle_error(ctx, "gfx.d3d12: graphics pipeline shader is invalid")
		return false
	}

	pipeline_info := D3D12_Pipeline {
		shader = desc.shader,
		topology = d3d12_primitive_topology(desc.primitive_type),
		topology_type = d3d12_primitive_topology_type(desc.primitive_type),
		index_format = d3d12_index_format(desc.index_type),
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
	for i in 0..<MAX_VERTEX_BUFFERS {
		pipeline_info.vertex_strides[i] = desc.layout.buffers[i].stride
	}
	if !pipeline_info.depth_only && pipeline_info.color_formats[0] == .Invalid {
		pipeline_info.color_formats[0] = ctx.desc.swapchain_format
	}

	if !d3d12_build_root_signature(ctx, state, shader_info, &pipeline_info.root, false) {
		d3d12_release_pipeline(&pipeline_info)
		return false
	}

	input_elements: [MAX_VERTEX_ATTRIBUTES]d3d12.INPUT_ELEMENT_DESC
	input_count: u32
	for attr in desc.layout.attrs {
		if !vertex_attr_desc_active(attr) {
			continue
		}
		input_elements[input_count] = d3d12.INPUT_ELEMENT_DESC {
			SemanticName = attr.semantic,
			SemanticIndex = attr.semantic_index,
			Format = d3d12_vertex_format(attr.format),
			InputSlot = attr.buffer_slot,
			AlignedByteOffset = attr.offset,
			InputSlotClass = d3d12_input_class(desc.layout.buffers[int(attr.buffer_slot)].step_func),
			InstanceDataStepRate = desc.layout.buffers[int(attr.buffer_slot)].step_rate,
		}
		pipeline_info.required_vertex_buffers |= d3d12_slot_mask(attr.buffer_slot)
		input_count += 1
	}

	pso_desc := d3d12.GRAPHICS_PIPELINE_STATE_DESC {
		pRootSignature = pipeline_info.root.root_signature,
		VS = d3d12.SHADER_BYTECODE{pShaderBytecode = raw_data(shader_info.vertex_bytecode), BytecodeLength = d3d12.SIZE_T(len(shader_info.vertex_bytecode))},
		PS = d3d12.SHADER_BYTECODE{pShaderBytecode = raw_data(shader_info.pixel_bytecode), BytecodeLength = d3d12.SIZE_T(len(shader_info.pixel_bytecode))},
		BlendState = d3d12_blend_desc(desc),
		SampleMask = 0xffffffff,
		RasterizerState = d3d12_rasterizer_desc(desc.raster),
		DepthStencilState = d3d12_depth_stencil_desc(desc.depth),
		InputLayout = d3d12.INPUT_LAYOUT_DESC{pInputElementDescs = raw_data(input_elements[:]), NumElements = input_count},
		IBStripCutValue = .DISABLED,
		PrimitiveTopologyType = pipeline_info.topology_type,
		SampleDesc = dxgi.SAMPLE_DESC{Count = 1, Quality = 0},
	}
	if pipeline_info.depth_enabled {
		pso_desc.DSVFormat = d3d12_dxgi_format(pipeline_info.depth_format)
	}
	if !pipeline_info.depth_only {
		for format, slot in pipeline_info.color_formats {
			if format == .Invalid {
				continue
			}
			pso_desc.RTVFormats[slot] = d3d12_dxgi_format(format)
			pso_desc.NumRenderTargets = u32(slot + 1)
		}
	}

	pso_raw: rawptr
	hr := state.device.CreateGraphicsPipelineState(state.device, &pso_desc, d3d12.IPipelineState_UUID, &pso_raw)
	if d3d12_failed(hr) || pso_raw == nil {
		d3d12_release_pipeline(&pipeline_info)
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateGraphicsPipelineState failed", hr)
		return false
	}
	pipeline_info.pso = cast(^d3d12.IPipelineState)pso_raw
	d3d12_set_debug_name(cast(^d3d12.IObject)pipeline_info.pso, desc.label)
	state.pipelines[handle] = pipeline_info
	return true
}

d3d12_destroy_pipeline :: proc(ctx: ^Context, handle: Pipeline) {
	state := d3d12_state(ctx)
	if state == nil {
		return
	}
	if pipeline_info, ok := state.pipelines[handle]; ok {
		d3d12_release_pipeline(&pipeline_info)
		delete_key(&state.pipelines, handle)
		if state.current_pipeline == handle {
			state.current_pipeline = Pipeline_Invalid
		}
	}
}

d3d12_create_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline, desc: Compute_Pipeline_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d12: device is not initialized")
		return false
	}
	shader_info, shader_ok := state.shaders[desc.shader]
	if !shader_ok || len(shader_info.compute_bytecode) == 0 {
		set_invalid_handle_error(ctx, "gfx.d3d12: compute pipeline shader is invalid")
		return false
	}
	pipeline_info := D3D12_Compute_Pipeline {
		shader = desc.shader,
		required = shader_info.required,
		uniform_slots = shader_info.uniform_slots,
		view_slots = shader_info.view_slots,
		sampler_slots = shader_info.sampler_slots,
		has_binding_metadata = shader_info.has_binding_metadata,
	}
	if !d3d12_build_root_signature(ctx, state, shader_info, &pipeline_info.root, true) {
		return false
	}
	pso_desc := d3d12.COMPUTE_PIPELINE_STATE_DESC {
		pRootSignature = pipeline_info.root.root_signature,
		CS = d3d12.SHADER_BYTECODE{pShaderBytecode = raw_data(shader_info.compute_bytecode), BytecodeLength = d3d12.SIZE_T(len(shader_info.compute_bytecode))},
	}
	pso_raw: rawptr
	hr := state.device.CreateComputePipelineState(state.device, &pso_desc, d3d12.IPipelineState_UUID, &pso_raw)
	if d3d12_failed(hr) || pso_raw == nil {
		d3d12_release_root_info(&pipeline_info.root)
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateComputePipelineState failed", hr)
		return false
	}
	pipeline_info.pso = cast(^d3d12.IPipelineState)pso_raw
	d3d12_set_debug_name(cast(^d3d12.IObject)pipeline_info.pso, desc.label)
	state.compute_pipelines[handle] = pipeline_info
	return true
}

d3d12_destroy_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline) {
	state := d3d12_state(ctx)
	if state == nil {
		return
	}
	if pipeline_info, ok := state.compute_pipelines[handle]; ok {
		d3d12_release_compute_pipeline(&pipeline_info)
		delete_key(&state.compute_pipelines, handle)
		if state.current_compute_pipeline == handle {
			state.current_compute_pipeline = Compute_Pipeline_Invalid
		}
	}
}

d3d12_resize :: proc(ctx: ^Context, width, height: i32) -> bool {
	state := d3d12_state(ctx)
	if state == nil || state.swapchain == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	d3d12_wait_idle(state)
	d3d12_release_swapchain_views(state)
	state.width = u32(width)
	state.height = u32(height)
	hr := state.swapchain.ResizeBuffers(state.swapchain, D3D12_FRAME_COUNT, state.width, state.height, state.format, {})
	if d3d12_failed(hr) {
		d3d12_set_error_hr(ctx, "gfx.d3d12: ResizeBuffers failed", hr)
		return false
	}
	state.frame_index = state.swapchain.GetCurrentBackBufferIndex(state.swapchain)
	return d3d12_create_backbuffers(ctx, state) && d3d12_create_default_depth(ctx, state)
}

d3d12_begin_pass :: proc(ctx: ^Context, desc: Pass_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil || state.cmd == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	if !d3d12_begin_commands(ctx, state) {
		return false
	}

	state.current_pipeline = Pipeline_Invalid
	state.current_compute_pipeline = Compute_Pipeline_Invalid
	state.current_user_bindings = {}
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	state.current_pass_color_formats = {}
	state.current_pass_has_color = false
	state.current_pass_depth_format = .Invalid
	state.current_pass_has_depth = false

	rtvs: [MAX_COLOR_ATTACHMENTS]d3d12.CPU_DESCRIPTOR_HANDLE
	color_count: u32
	pass_width := state.width
	pass_height := state.height
	has_custom_color := false

	for attachment, slot in desc.color_attachments {
		if !view_valid(attachment) {
			continue
		}
		view_info, view_ok := state.views[attachment]
		if !view_ok || view_info.kind != .Color_Attachment {
			set_invalid_handle_error(ctx, "gfx.d3d12: color attachment view handle is unknown")
			return false
		}
		image_info, image_ok := &state.images[view_info.image]
		if !image_ok || image_info.resource == nil {
			set_invalid_handle_error(ctx, "gfx.d3d12: color attachment image handle is unknown")
			return false
		}
		d3d12_transition_image(state, image_info, {.RENDER_TARGET})
		rtvs[slot] = view_info.cpu_handle
		state.current_pass_color_formats[slot] = view_info.format
		state.current_pass_has_color = true
		color_count = u32(slot + 1)
		pass_width = view_info.width
		pass_height = view_info.height
		has_custom_color = true
	}

	dsv: d3d12.CPU_DESCRIPTOR_HANDLE
	dsv_ptr: ^d3d12.CPU_DESCRIPTOR_HANDLE
	if view_valid(desc.depth_stencil_attachment) {
		view_info, view_ok := state.views[desc.depth_stencil_attachment]
		if !view_ok || view_info.kind != .Depth_Stencil_Attachment {
			set_invalid_handle_error(ctx, "gfx.d3d12: depth-stencil attachment view handle is unknown")
			return false
		}
		image_info, image_ok := &state.images[view_info.image]
		if !image_ok || image_info.resource == nil {
			set_invalid_handle_error(ctx, "gfx.d3d12: depth-stencil attachment image handle is unknown")
			return false
		}
		d3d12_transition_image(state, image_info, {.DEPTH_WRITE})
		dsv = view_info.cpu_handle
		dsv_ptr = &dsv
		state.current_pass_depth_format = view_info.format
		state.current_pass_has_depth = true
		if !has_custom_color {
			pass_width = view_info.width
			pass_height = view_info.height
		}
	} else if has_custom_color {
		dsv_ptr = nil
	} else {
		frame := &state.backbuffers[state.frame_index]
		d3d12_transition_resource(state, frame.backbuffer, &frame.state, {.RENDER_TARGET})
		rtvs[0] = frame.rtv
		color_count = 1
		state.current_pass_color_formats[0] = ctx.desc.swapchain_format
		state.current_pass_has_color = true
		dsv = state.default_depth_dsv
		dsv_ptr = &dsv
		d3d12_transition_resource(state, state.default_depth, &state.default_depth_state, {.DEPTH_WRITE})
		state.current_pass_depth_format = .D32F
		state.current_pass_has_depth = state.default_depth != nil
	}

	viewport := d3d12.VIEWPORT{TopLeftX = 0, TopLeftY = 0, Width = f32(pass_width), Height = f32(pass_height), MinDepth = 0, MaxDepth = 1}
	scissor := dxgi.RECT{left = 0, top = 0, right = i32(pass_width), bottom = i32(pass_height)}
	state.cmd.RSSetViewports(state.cmd, 1, &viewport)
	state.cmd.RSSetScissorRects(state.cmd, 1, &scissor)
	if color_count > 0 {
		state.cmd.OMSetRenderTargets(state.cmd, color_count, &rtvs[0], win32.FALSE, dsv_ptr)
	} else {
		state.cmd.OMSetRenderTargets(state.cmd, 0, nil, win32.FALSE, dsv_ptr)
	}

	for slot in 0..<int(color_count) {
		color_action := desc.action.colors[slot]
		if color_action.load_action != .Clear {
			continue
		}
		clear_color := [4]f32{color_action.clear_value.r, color_action.clear_value.g, color_action.clear_value.b, color_action.clear_value.a}
		state.cmd.ClearRenderTargetView(state.cmd, rtvs[slot], &clear_color, 0, nil)
	}
	if dsv_ptr != nil {
		clear_flags: d3d12.CLEAR_FLAGS
		if desc.action.depth.load_action == .Clear {
			clear_flags += {.DEPTH}
		}
		if state.current_pass_depth_format == .D24S8 && desc.action.stencil.load_action == .Clear {
			clear_flags += {.STENCIL}
		}
		if clear_flags != {} {
			state.cmd.ClearDepthStencilView(state.cmd, dsv, clear_flags, desc.action.depth.clear_value, desc.action.stencil.clear_value, 0, nil)
		}
	}

	return true
}

d3d12_begin_compute_pass :: proc(ctx: ^Context, desc: Compute_Pass_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	if !d3d12_begin_commands(ctx, state) {
		return false
	}
	state.current_pipeline = Pipeline_Invalid
	state.current_compute_pipeline = Compute_Pipeline_Invalid
	state.current_user_bindings = {}
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	state.current_pass_color_formats = {}
	state.current_pass_has_color = false
	state.current_pass_depth_format = .Invalid
	state.current_pass_has_depth = false
	return true
}

d3d12_apply_pipeline :: proc(ctx: ^Context, pipeline: Pipeline) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	pipeline_info, ok := state.pipelines[pipeline]
	if !ok || pipeline_info.pso == nil {
		set_invalid_handle_error(ctx, "gfx.d3d12: pipeline handle is unknown")
		return false
	}
	if !d3d12_validate_pipeline_pass_compatibility(ctx, state, &pipeline_info) {
		return false
	}
	state.cmd.SetPipelineState(state.cmd, pipeline_info.pso)
	state.cmd.SetGraphicsRootSignature(state.cmd, pipeline_info.root.root_signature)
	state.cmd.IASetPrimitiveTopology(state.cmd, pipeline_info.topology)
	d3d12_set_descriptor_heaps(state)
	state.current_pipeline = pipeline
	state.current_compute_pipeline = Compute_Pipeline_Invalid
	state.current_user_bindings = {}
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	return true
}

d3d12_apply_compute_pipeline :: proc(ctx: ^Context, pipeline: Compute_Pipeline) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	pipeline_info, ok := state.compute_pipelines[pipeline]
	if !ok || pipeline_info.pso == nil {
		set_invalid_handle_error(ctx, "gfx.d3d12: compute pipeline handle is unknown")
		return false
	}
	state.cmd.SetPipelineState(state.cmd, pipeline_info.pso)
	state.cmd.SetComputeRootSignature(state.cmd, pipeline_info.root.root_signature)
	d3d12_set_descriptor_heaps(state)
	state.current_pipeline = Pipeline_Invalid
	state.current_compute_pipeline = pipeline
	state.current_user_bindings = {}
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	return true
}

d3d12_apply_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	if ctx.pass_kind == .Compute {
		return d3d12_apply_compute_bindings(ctx, state, bindings)
	}
	pipeline_info, ok := state.pipelines[state.current_pipeline]
	if !ok {
		set_validation_error(ctx, "gfx.d3d12: apply_bindings requires an applied pipeline")
		return false
	}

	vertex_views: [MAX_VERTEX_BUFFERS]d3d12.VERTEX_BUFFER_VIEW
	vertex_count: u32
	vertex_mask: u32
	for binding, slot in bindings.vertex_buffers {
		if !buffer_valid(binding.buffer) {
			continue
		}
		buffer_info, buffer_ok := &state.buffers[binding.buffer]
		if !buffer_ok || buffer_info.resource == nil {
			set_invalid_handle_error(ctx, "gfx.d3d12: vertex buffer handle is unknown")
			return false
		}
		gpu_va := buffer_info.resource.GetGPUVirtualAddress(buffer_info.resource) + u64(binding.offset)
		vertex_views[slot] = d3d12.VERTEX_BUFFER_VIEW {
			BufferLocation = gpu_va,
			SizeInBytes = u32(buffer_info.size - u64(binding.offset)),
			StrideInBytes = pipeline_info.vertex_strides[slot],
		}
		vertex_mask |= d3d12_slot_mask(u32(slot))
		vertex_count = u32(slot + 1)
	}
	if vertex_count > 0 {
		state.cmd.IASetVertexBuffers(state.cmd, 0, vertex_count, raw_data(vertex_views[:]))
	}
	state.current_vertex_buffers = vertex_mask

	if buffer_valid(bindings.index_buffer.buffer) {
		buffer_info, buffer_ok := &state.buffers[bindings.index_buffer.buffer]
		if !buffer_ok || buffer_info.resource == nil {
			set_invalid_handle_error(ctx, "gfx.d3d12: index buffer handle is unknown")
			return false
		}
		gpu_va := buffer_info.resource.GetGPUVirtualAddress(buffer_info.resource) + u64(bindings.index_buffer.offset)
		index_view := d3d12.INDEX_BUFFER_VIEW {
			BufferLocation = gpu_va,
			SizeInBytes = u32(buffer_info.size - u64(bindings.index_buffer.offset)),
			Format = pipeline_info.index_format,
		}
		state.cmd.IASetIndexBuffer(state.cmd, &index_view)
		state.current_index_buffer = true
	} else {
		state.current_index_buffer = false
	}

	state.current_user_bindings = bindings
	d3d12_record_bound_resources_from_bindings(state, bindings)
	return true
}

d3d12_apply_compute_bindings :: proc(ctx: ^Context, state: ^D3D12_State, bindings: Bindings) -> bool {
	pipeline_info, ok := state.compute_pipelines[state.current_compute_pipeline]
	if !ok {
		set_validation_error(ctx, "gfx.d3d12: apply_bindings requires an applied compute pipeline")
		return false
	}
	state.current_user_bindings = bindings
	d3d12_record_bound_resources_from_bindings(state, bindings)
	return true
}

d3d12_apply_uniforms :: proc(ctx: ^Context, group: u32, slot: int, data: Range) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	if !d3d12_validate_uniform_binding(ctx, state, group, slot, u32(data.size)) {
		return false
	}
	aligned_size := align_up(data.size, D3D12_CONSTANT_BUFFER_ALIGNMENT)
	upload := &state.uniform_uploads[group][slot]
	if upload.resource == nil || upload.size < u64(aligned_size) {
		d3d12_release_buffer(upload)
		if !d3d12_create_upload_buffer(ctx, state, upload, aligned_size, fmt.tprintf("uniform g%d s%d", group, slot)) {
			return false
		}
	}
	mem.copy(upload.mapped, data.ptr, data.size)
	gpu_va := upload.resource.GetGPUVirtualAddress(upload.resource)
	state.uniform_bindings[group][slot] = {resource = upload.resource, gpu_va = gpu_va, size = u32(aligned_size)}
	d3d12_mark_uniform_bound(state, group, u32(slot))
	return true
}

d3d12_apply_uniform_at :: proc(ctx: ^Context, group: u32, slot: int, slice: Transient_Slice, byte_size: int) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	if !d3d12_validate_uniform_binding(ctx, state, group, slot, u32(byte_size)) {
		return false
	}
	buffer_info, ok := state.buffers[slice.buffer]
	if !ok || buffer_info.resource == nil {
		set_invalid_handle_error(ctx, "gfx.d3d12: transient uniform buffer is unknown")
		return false
	}
	gpu_va := buffer_info.resource.GetGPUVirtualAddress(buffer_info.resource) + u64(slice.offset)
	state.uniform_bindings[group][slot] = {resource = buffer_info.resource, gpu_va = gpu_va, size = u32(align_up(byte_size, D3D12_CONSTANT_BUFFER_ALIGNMENT))}
	d3d12_mark_uniform_bound(state, group, u32(slot))
	return true
}

d3d12_draw :: proc(ctx: ^Context, base_element: i32, num_elements: i32, num_instances: i32) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	pipeline_info, ok := state.pipelines[state.current_pipeline]
	if !ok {
		set_validation_error(ctx, "gfx.d3d12: draw requires an applied pipeline")
		return false
	}
	if !d3d12_validate_draw_bindings(ctx, state, &pipeline_info) {
		return false
	}
	if !d3d12_sync_graphics_root(ctx, state, &pipeline_info) {
		return false
	}
	if pipeline_info.has_index_buffer {
		if !state.current_index_buffer {
			set_validation_error(ctx, "gfx.d3d12: indexed draw requires an index buffer")
			return false
		}
		state.cmd.DrawIndexedInstanced(state.cmd, u32(num_elements), u32(num_instances), u32(base_element), 0, 0)
	} else {
		state.cmd.DrawInstanced(state.cmd, u32(num_elements), u32(num_instances), u32(base_element), 0)
	}
	return true
}

d3d12_dispatch :: proc(ctx: ^Context, group_count_x, group_count_y, group_count_z: u32) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	pipeline_info, ok := state.compute_pipelines[state.current_compute_pipeline]
	if !ok {
		set_validation_error(ctx, "gfx.d3d12: dispatch requires an applied compute pipeline")
		return false
	}
	if !d3d12_validate_compute_bindings(ctx, state, &pipeline_info) {
		return false
	}
	if !d3d12_sync_compute_root(ctx, state, &pipeline_info) {
		return false
	}
	state.cmd.Dispatch(state.cmd, group_count_x, group_count_y, group_count_z)
	return true
}

d3d12_draw_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: u32) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	pipeline_info, ok := state.pipelines[state.current_pipeline]
	if !ok {
		set_validation_error(ctx, "gfx.d3d12: draw_indirect requires an applied pipeline")
		return false
	}
	if !d3d12_validate_draw_bindings(ctx, state, &pipeline_info) || !d3d12_sync_graphics_root(ctx, state, &pipeline_info) {
		return false
	}
	buffer_info, buffer_ok := &state.buffers[indirect_buffer]
	if !buffer_ok || buffer_info.resource == nil {
		set_invalid_handle_error(ctx, "gfx.d3d12: indirect buffer handle is unknown")
		return false
	}
	d3d12_transition_buffer(state, buffer_info, {.INDIRECT_ARGUMENT})
	state.cmd.ExecuteIndirect(state.cmd, state.draw_signature, draw_count, buffer_info.resource, u64(offset), nil, 0)
	return true
}

d3d12_draw_indexed_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: u32) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	pipeline_info, ok := state.pipelines[state.current_pipeline]
	if !ok {
		set_validation_error(ctx, "gfx.d3d12: draw_indexed_indirect requires an applied pipeline")
		return false
	}
	if !pipeline_info.has_index_buffer || !state.current_index_buffer {
		set_validation_error(ctx, "gfx.d3d12: draw_indexed_indirect requires indexed pipeline and index buffer")
		return false
	}
	if !d3d12_validate_draw_bindings(ctx, state, &pipeline_info) || !d3d12_sync_graphics_root(ctx, state, &pipeline_info) {
		return false
	}
	buffer_info, buffer_ok := &state.buffers[indirect_buffer]
	if !buffer_ok || buffer_info.resource == nil {
		set_invalid_handle_error(ctx, "gfx.d3d12: indirect buffer handle is unknown")
		return false
	}
	d3d12_transition_buffer(state, buffer_info, {.INDIRECT_ARGUMENT})
	state.cmd.ExecuteIndirect(state.cmd, state.draw_indexed_signature, draw_count, buffer_info.resource, u64(offset), nil, 0)
	return true
}

d3d12_dispatch_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	pipeline_info, ok := state.compute_pipelines[state.current_compute_pipeline]
	if !ok {
		set_validation_error(ctx, "gfx.d3d12: dispatch_indirect requires an applied compute pipeline")
		return false
	}
	if !d3d12_validate_compute_bindings(ctx, state, &pipeline_info) || !d3d12_sync_compute_root(ctx, state, &pipeline_info) {
		return false
	}
	buffer_info, buffer_ok := &state.buffers[indirect_buffer]
	if !buffer_ok || buffer_info.resource == nil {
		set_invalid_handle_error(ctx, "gfx.d3d12: indirect buffer handle is unknown")
		return false
	}
	d3d12_transition_buffer(state, buffer_info, {.INDIRECT_ARGUMENT})
	state.cmd.ExecuteIndirect(state.cmd, state.dispatch_signature, 1, buffer_info.resource, u64(offset), nil, 0)
	return true
}

d3d12_end_pass :: proc(ctx: ^Context) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		return false
	}
	for view in ctx.pass_color_attachments {
		if !view_valid(view) {
			continue
		}
		view_info, ok := state.views[view]
		if ok && image_valid(view_info.image) {
			if image_info, image_ok := &state.images[view_info.image]; image_ok {
				d3d12_transition_image(state, image_info, d3d12_post_write_image_state(image_info.usage))
			}
		}
	}
	if view_valid(ctx.pass_depth_stencil_attachment) {
		view_info, ok := state.views[ctx.pass_depth_stencil_attachment]
		if ok && image_valid(view_info.image) {
			if image_info, image_ok := &state.images[view_info.image]; image_ok {
				d3d12_transition_image(state, image_info, d3d12_post_write_image_state(image_info.usage))
			}
		}
	}
	return true
}

d3d12_end_compute_pass :: proc(ctx: ^Context) -> bool {
	return true
}

d3d12_barrier :: proc(ctx: ^Context, desc: Barrier_Desc) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	if !d3d12_begin_commands(ctx, state) {
		return false
	}
	for transition in desc.image_transitions {
		if image_info, ok := &state.images[transition.image]; ok {
			d3d12_transition_image(state, image_info, d3d12_resource_state(transition.to))
		}
	}
	for transition in desc.buffer_transitions {
		if buffer_info, ok := &state.buffers[transition.buffer]; ok {
			d3d12_transition_buffer(state, buffer_info, d3d12_resource_state(transition.to))
		}
	}
	return true
}

d3d12_commit :: proc(ctx: ^Context) -> bool {
	state := d3d12_state(ctx)
	if state == nil {
		set_backend_error(ctx, "gfx.d3d12: backend state is not initialized")
		return false
	}
	if !state.command_open {
		return true
	}
	frame := &state.backbuffers[state.frame_index]
	if frame.backbuffer != nil {
		d3d12_transition_resource(state, frame.backbuffer, &frame.state, d3d12.RESOURCE_STATE_PRESENT)
	}
	if !d3d12_submit_commands(ctx, state) {
		return false
	}
	hr := state.swapchain.Present(state.swapchain, state.sync_interval, {})
	if d3d12_failed(hr) {
		d3d12_set_error_hr(ctx, "gfx.d3d12: Present failed", hr)
		return false
	}
	d3d12_wait_idle(state)
	d3d12_release_pending_uploads(state)
	state.frame_index = state.swapchain.GetCurrentBackBufferIndex(state.swapchain)
	return true
}

d3d12_create_transient_chunk :: proc(ctx: ^Context, role: Transient_Usage, capacity: int, label: string) -> (Buffer, rawptr, bool) {
	usage: Buffer_Usage
	switch role {
	case .Uniform:
		usage = {.Uniform, .Stream_Update}
	case .Storage:
		usage = {.Storage}
	case .Vertex:
		usage = {.Vertex, .Stream_Update}
	case .Index:
		usage = {.Index, .Stream_Update}
	case .Indirect:
		usage = {.Indirect, .Immutable}
	}
	buffer, ok := create_buffer(ctx, {label = label, usage = usage, size = capacity, data = {} })
	if !ok {
		return Buffer_Invalid, nil, false
	}
	state := d3d12_state(ctx)
	info, info_ok := state.buffers[buffer]
	if !info_ok {
		return Buffer_Invalid, nil, false
	}
	return buffer, info.mapped, true
}

d3d12_destroy_transient_chunk :: proc(ctx: ^Context, buffer: Buffer) {
	if buffer_valid(buffer) && resource_id_alive(ctx, &ctx.buffer_pool, u64(buffer)) {
		destroy_buffer(ctx, buffer)
	}
}

d3d12_reset_transient_chunk :: proc(ctx: ^Context, buffer: Buffer) -> (rawptr, bool) {
	return d3d12_transient_chunk_ensure_mapped(ctx, buffer)
}

d3d12_transient_chunk_ensure_mapped :: proc(ctx: ^Context, buffer: Buffer) -> (rawptr, bool) {
	state := d3d12_state(ctx)
	if state == nil {
		return nil, false
	}
	if info, ok := state.buffers[buffer]; ok {
		return info.mapped, info.mapped != nil
	}
	return nil, false
}

// Implementation helpers.

d3d12_state :: proc(ctx: ^Context) -> ^D3D12_State {
	if ctx == nil || ctx.backend_data == nil {
		return nil
	}
	return cast(^D3D12_State)ctx.backend_data
}

d3d12_failed :: proc(hr: dxgi.HRESULT) -> bool {
	return i32(hr) < 0
}

d3d12_set_error_hr :: proc(ctx: ^Context, message: string, hr: dxgi.HRESULT) {
	set_backend_errorf(ctx, "%s (hr=0x%08x)", message, u32(hr))
}

positive_u32_or_default :: proc(value: i32, fallback: u32) -> u32 {
	if value > 0 {
		return u32(value)
	}
	return fallback
}

d3d12_slot_mask :: proc(slot: u32) -> u32 {
	return u32(1) << slot
}

d3d12_create_device :: proc(ctx: ^Context, state: ^D3D12_State) -> bool {
	factory_raw: rawptr
	factory_flags: dxgi.CREATE_FACTORY
	hr := dxgi.CreateDXGIFactory2(factory_flags, dxgi.IFactory2_UUID, &factory_raw)
	if d3d12_failed(hr) || factory_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateDXGIFactory2 failed", hr)
		return false
	}
	state.factory = cast(^dxgi.IFactory2)factory_raw

	device_raw: rawptr
	hr = d3d12.CreateDevice(nil, ._11_0, d3d12.IDevice_UUID, &device_raw)
	if d3d12_failed(hr) || device_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: D3D12CreateDevice failed", hr)
		return false
	}
	state.device = cast(^d3d12.IDevice)device_raw
	d3d12_set_debug_name(cast(^d3d12.IObject)state.device, ctx.desc.label)

	queue_desc := d3d12.COMMAND_QUEUE_DESC{Type = .DIRECT, Priority = i32(d3d12.COMMAND_QUEUE_PRIORITY.NORMAL)}
	queue_raw: rawptr
	hr = state.device.CreateCommandQueue(state.device, &queue_desc, d3d12.ICommandQueue_UUID, &queue_raw)
	if d3d12_failed(hr) || queue_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommandQueue failed", hr)
		return false
	}
	state.queue = cast(^d3d12.ICommandQueue)queue_raw

	allocator_raw: rawptr
	hr = state.device.CreateCommandAllocator(state.device, .DIRECT, d3d12.ICommandAllocator_UUID, &allocator_raw)
	if d3d12_failed(hr) || allocator_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommandAllocator failed", hr)
		return false
	}
	state.allocator = cast(^d3d12.ICommandAllocator)allocator_raw

	cmd_raw: rawptr
	hr = state.device.CreateCommandList(state.device, 0, .DIRECT, state.allocator, nil, d3d12.IGraphicsCommandList_UUID, &cmd_raw)
	if d3d12_failed(hr) || cmd_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommandList failed", hr)
		return false
	}
	state.cmd = cast(^d3d12.IGraphicsCommandList)cmd_raw
	state.cmd.Close(state.cmd)
	state.command_open = false

	fence_raw: rawptr
	hr = state.device.CreateFence(state.device, 0, {}, d3d12.IFence_UUID, &fence_raw)
	if d3d12_failed(hr) || fence_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateFence failed", hr)
		return false
	}
	state.fence = cast(^d3d12.IFence)fence_raw
	state.fence_event = win32.CreateEventW(nil, win32.FALSE, win32.FALSE, nil)
	if state.fence_event == nil {
		set_backend_error(ctx, "gfx.d3d12: CreateEventW failed")
		return false
	}
	return true
}

d3d12_create_descriptor_heaps :: proc(ctx: ^Context, state: ^D3D12_State) -> bool {
	return d3d12_create_descriptor_heap(ctx, state, &state.rtv_heap, .RTV, D3D12_RTV_CAPACITY, false) &&
	       d3d12_create_descriptor_heap(ctx, state, &state.dsv_heap, .DSV, D3D12_DSV_CAPACITY, false) &&
	       d3d12_create_descriptor_heap(ctx, state, &state.cpu_cbv_srv_uav, .CBV_SRV_UAV, D3D12_CBV_SRV_UAV_CPU_CAPACITY, false) &&
	       d3d12_create_descriptor_heap(ctx, state, &state.cpu_samplers, .SAMPLER, D3D12_SAMPLER_CPU_CAPACITY, false) &&
	       d3d12_create_descriptor_heap(ctx, state, &state.gpu_cbv_srv_uav, .CBV_SRV_UAV, D3D12_CBV_SRV_UAV_GPU_CAPACITY, true) &&
	       d3d12_create_descriptor_heap(ctx, state, &state.gpu_samplers, .SAMPLER, D3D12_SAMPLER_GPU_CAPACITY, true)
}

d3d12_create_descriptor_heap :: proc(ctx: ^Context, state: ^D3D12_State, allocator: ^D3D12_Descriptor_Allocator, heap_type: d3d12.DESCRIPTOR_HEAP_TYPE, capacity: u32, shader_visible: bool) -> bool {
	flags: d3d12.DESCRIPTOR_HEAP_FLAGS
	if shader_visible {
		flags += {.SHADER_VISIBLE}
	}
	desc := d3d12.DESCRIPTOR_HEAP_DESC{Type = heap_type, NumDescriptors = capacity, Flags = flags}
	heap_raw: rawptr
	hr := state.device.CreateDescriptorHeap(state.device, &desc, d3d12.IDescriptorHeap_UUID, &heap_raw)
	if d3d12_failed(hr) || heap_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateDescriptorHeap failed", hr)
		return false
	}
	allocator.heap = cast(^d3d12.IDescriptorHeap)heap_raw
	allocator.capacity = capacity
	allocator.increment = state.device.GetDescriptorHandleIncrementSize(state.device, heap_type)
	allocator.next = 0
	allocator.shader_visible = shader_visible
	allocator.heap_type = heap_type
	allocator.heap.GetCPUDescriptorHandleForHeapStart(allocator.heap, &allocator.cpu_start)
	if shader_visible {
		allocator.heap.GetGPUDescriptorHandleForHeapStart(allocator.heap, &allocator.gpu_start)
	}
	return true
}

d3d12_create_swapchain :: proc(ctx: ^Context, state: ^D3D12_State) -> bool {
	desc := dxgi.SWAP_CHAIN_DESC1 {
		Width = state.width,
		Height = state.height,
		Format = state.format,
		SampleDesc = dxgi.SAMPLE_DESC{Count = 1, Quality = 0},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = D3D12_FRAME_COUNT,
		SwapEffect = .FLIP_DISCARD,
	}
	swapchain1: ^dxgi.ISwapChain1
	hr := state.factory.CreateSwapChainForHwnd(
		state.factory,
		cast(^dxgi.IUnknown)state.queue,
		cast(dxgi.HWND)ctx.desc.native_window,
		&desc,
		nil,
		nil,
		&swapchain1,
	)
	if d3d12_failed(hr) || swapchain1 == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateSwapChainForHwnd failed", hr)
		return false
	}
	swapchain3_raw: rawptr
	hr = swapchain1.QueryInterface(cast(^dxgi.IUnknown)swapchain1, dxgi.ISwapChain3_UUID, &swapchain3_raw)
	swapchain1.Release(swapchain1)
	if d3d12_failed(hr) || swapchain3_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: QueryInterface(ISwapChain3) failed", hr)
		return false
	}
	state.swapchain = cast(^dxgi.ISwapChain3)swapchain3_raw
	state.frame_index = state.swapchain.GetCurrentBackBufferIndex(state.swapchain)
	return true
}

d3d12_create_backbuffers :: proc(ctx: ^Context, state: ^D3D12_State) -> bool {
	for i: u32 = 0; i < D3D12_FRAME_COUNT; i += 1 {
		buffer_raw: rawptr
		hr := state.swapchain.GetBuffer(state.swapchain, i, d3d12.IResource_UUID, &buffer_raw)
		if d3d12_failed(hr) || buffer_raw == nil {
			d3d12_set_error_hr(ctx, "gfx.d3d12: swapchain GetBuffer failed", hr)
			return false
		}
		state.backbuffers[i].backbuffer = cast(^d3d12.IResource)buffer_raw
		state.backbuffers[i].rtv = d3d12_alloc_descriptor(&state.rtv_heap)
		state.backbuffers[i].state = d3d12.RESOURCE_STATE_PRESENT
		state.device.CreateRenderTargetView(state.device, state.backbuffers[i].backbuffer, nil, state.backbuffers[i].rtv)
	}
	return true
}

d3d12_create_default_depth :: proc(ctx: ^Context, state: ^D3D12_State) -> bool {
	if state.default_depth != nil {
		state.default_depth.Release(state.default_depth)
		state.default_depth = nil
	}
	resource_desc := d3d12.RESOURCE_DESC {
		Dimension = .TEXTURE2D,
		Width = u64(state.width),
		Height = state.height,
		DepthOrArraySize = 1,
		MipLevels = 1,
		Format = .D32_FLOAT,
		SampleDesc = dxgi.SAMPLE_DESC{Count = 1, Quality = 0},
		Layout = .UNKNOWN,
		Flags = {.ALLOW_DEPTH_STENCIL},
	}
	clear_value := d3d12.CLEAR_VALUE{Format = .D32_FLOAT}
	clear_value.DepthStencil = {Depth = 1, Stencil = 0}
	heap_props := d3d12_heap_properties(.DEFAULT)
	resource_raw: rawptr
	hr := state.device.CreateCommittedResource(state.device, &heap_props, d3d12.HEAP_FLAG_ALLOW_ALL_BUFFERS_AND_TEXTURES, &resource_desc, {.DEPTH_WRITE}, &clear_value, d3d12.IResource_UUID, &resource_raw)
	if d3d12_failed(hr) || resource_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommittedResource(default depth) failed", hr)
		return false
	}
	state.default_depth = cast(^d3d12.IResource)resource_raw
	state.default_depth_state = {.DEPTH_WRITE}
	state.default_depth_dsv = d3d12_alloc_descriptor(&state.dsv_heap)
	state.device.CreateDepthStencilView(state.device, state.default_depth, nil, state.default_depth_dsv)
	return true
}

d3d12_create_command_signatures :: proc(ctx: ^Context, state: ^D3D12_State) -> bool {
	draw_arg := d3d12.INDIRECT_ARGUMENT_DESC{Type = .DRAW}
	draw_desc := d3d12.COMMAND_SIGNATURE_DESC{ByteStride = DRAW_INDIRECT_ARGS_STRIDE, NumArgumentDescs = 1, pArgumentDescs = &draw_arg}
	raw: rawptr
	hr := state.device.CreateCommandSignature(state.device, &draw_desc, nil, d3d12.ICommandSignature_UUID, &raw)
	if d3d12_failed(hr) || raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommandSignature(draw) failed", hr)
		return false
	}
	state.draw_signature = cast(^d3d12.ICommandSignature)raw

	indexed_arg := d3d12.INDIRECT_ARGUMENT_DESC{Type = .DRAW_INDEXED}
	indexed_desc := d3d12.COMMAND_SIGNATURE_DESC{ByteStride = DRAW_INDEXED_INDIRECT_ARGS_STRIDE, NumArgumentDescs = 1, pArgumentDescs = &indexed_arg}
	raw = nil
	hr = state.device.CreateCommandSignature(state.device, &indexed_desc, nil, d3d12.ICommandSignature_UUID, &raw)
	if d3d12_failed(hr) || raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommandSignature(draw indexed) failed", hr)
		return false
	}
	state.draw_indexed_signature = cast(^d3d12.ICommandSignature)raw

	dispatch_arg := d3d12.INDIRECT_ARGUMENT_DESC{Type = .DISPATCH}
	dispatch_desc := d3d12.COMMAND_SIGNATURE_DESC{ByteStride = DISPATCH_INDIRECT_ARGS_STRIDE, NumArgumentDescs = 1, pArgumentDescs = &dispatch_arg}
	raw = nil
	hr = state.device.CreateCommandSignature(state.device, &dispatch_desc, nil, d3d12.ICommandSignature_UUID, &raw)
	if d3d12_failed(hr) || raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommandSignature(dispatch) failed", hr)
		return false
	}
	state.dispatch_signature = cast(^d3d12.ICommandSignature)raw
	return true
}

d3d12_begin_commands :: proc(ctx: ^Context, state: ^D3D12_State) -> bool {
	if state.command_open {
		return true
	}
	hr := state.allocator.Reset(state.allocator)
	if d3d12_failed(hr) {
		d3d12_set_error_hr(ctx, "gfx.d3d12: command allocator Reset failed", hr)
		return false
	}
	hr = state.cmd.Reset(state.cmd, state.allocator, nil)
	if d3d12_failed(hr) {
		d3d12_set_error_hr(ctx, "gfx.d3d12: command list Reset failed", hr)
		return false
	}
	state.command_open = true
	state.gpu_cbv_srv_uav.next = 0
	state.gpu_samplers.next = 0
	return true
}

d3d12_submit_commands :: proc(ctx: ^Context, state: ^D3D12_State) -> bool {
	if !state.command_open {
		return true
	}
	hr := state.cmd.Close(state.cmd)
	if d3d12_failed(hr) {
		d3d12_set_error_hr(ctx, "gfx.d3d12: command list Close failed", hr)
		return false
	}
	list := cast(^d3d12.ICommandList)state.cmd
	state.queue.ExecuteCommandLists(state.queue, 1, &list)
	state.command_open = false
	return true
}

d3d12_submit_and_wait :: proc(ctx: ^Context, state: ^D3D12_State) -> bool {
	if !d3d12_submit_commands(ctx, state) {
		return false
	}
	d3d12_wait_idle(state)
	d3d12_release_pending_uploads(state)
	return true
}

d3d12_wait_idle :: proc(state: ^D3D12_State) {
	if state == nil || state.queue == nil || state.fence == nil {
		return
	}
	state.fence_value += 1
	value := state.fence_value
	hr := state.queue.Signal(state.queue, state.fence, value)
	if d3d12_failed(hr) {
		return
	}
	if state.fence.GetCompletedValue(state.fence) < value {
		_ = state.fence.SetEventOnCompletion(state.fence, value, state.fence_event)
		_ = win32.WaitForSingleObject(state.fence_event, win32.INFINITE)
	}
}

d3d12_set_descriptor_heaps :: proc(state: ^D3D12_State) {
	heaps := [2]^d3d12.IDescriptorHeap{state.gpu_cbv_srv_uav.heap, state.gpu_samplers.heap}
	state.cmd.SetDescriptorHeaps(state.cmd, 2, &heaps[0])
}

d3d12_alloc_descriptor :: proc(allocator: ^D3D12_Descriptor_Allocator) -> d3d12.CPU_DESCRIPTOR_HANDLE {
	if allocator == nil || allocator.next >= allocator.capacity {
		return {}
	}
	index := allocator.next
	allocator.next += 1
	return d3d12_descriptor_cpu(allocator^, index)
}

d3d12_descriptor_cpu :: proc(allocator: D3D12_Descriptor_Allocator, index: u32) -> d3d12.CPU_DESCRIPTOR_HANDLE {
	return {ptr = allocator.cpu_start.ptr + d3d12.SIZE_T(index * allocator.increment)}
}

d3d12_descriptor_gpu :: proc(allocator: D3D12_Descriptor_Allocator, index: u32) -> d3d12.GPU_DESCRIPTOR_HANDLE {
	return {ptr = allocator.gpu_start.ptr + u64(index * allocator.increment)}
}

d3d12_transition_resource :: proc(state: ^D3D12_State, resource: ^d3d12.IResource, current: ^d3d12.RESOURCE_STATES, next: d3d12.RESOURCE_STATES) {
	if resource == nil || current == nil || current^ == next {
		return
	}
	barrier := d3d12.RESOURCE_BARRIER {
		Type = .TRANSITION,
		Transition = {
			pResource = resource,
			Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
			StateBefore = current^,
			StateAfter = next,
		},
	}
	state.cmd.ResourceBarrier(state.cmd, 1, &barrier)
	current^ = next
}

d3d12_uav_barrier :: proc(state: ^D3D12_State, resource: ^d3d12.IResource) {
	if resource == nil {
		return
	}
	barrier := d3d12.RESOURCE_BARRIER {
		Type = .UAV,
		UAV = {pResource = resource},
	}
	state.cmd.ResourceBarrier(state.cmd, 1, &barrier)
}

d3d12_transition_buffer :: proc(state: ^D3D12_State, buffer: ^D3D12_Buffer, next: d3d12.RESOURCE_STATES) {
	if buffer == nil || buffer.resource == nil || buffer.mapped != nil {
		return
	}
	d3d12_transition_resource(state, buffer.resource, &buffer.state, next)
}

d3d12_transition_image :: proc(state: ^D3D12_State, image: ^D3D12_Image, next: d3d12.RESOURCE_STATES) {
	if image == nil || image.resource == nil {
		return
	}
	d3d12_transition_resource(state, image.resource, &image.state, next)
}

d3d12_resource_state :: proc(usage: Resource_Usage) -> d3d12.RESOURCE_STATES {
	switch usage {
	case .None, .Present:
		return d3d12.RESOURCE_STATE_COMMON
	case .Sampled, .Storage_Read:
		return d3d12.RESOURCE_STATE_ALL_SHADER_RESOURCE
	case .Storage_Write, .Storage_Read_Write:
		return {.UNORDERED_ACCESS}
	case .Color_Target:
		return {.RENDER_TARGET}
	case .Depth_Target_Read:
		return {.DEPTH_READ}
	case .Depth_Target_Write:
		return {.DEPTH_WRITE}
	case .Copy_Source:
		return {.COPY_SOURCE}
	case .Copy_Dest:
		return {.COPY_DEST}
	case .Indirect_Argument:
		return {.INDIRECT_ARGUMENT}
	}
	return d3d12.RESOURCE_STATE_COMMON
}

d3d12_post_write_image_state :: proc(usage: Image_Usage) -> d3d12.RESOURCE_STATES {
	if .Texture in usage {
		return d3d12.RESOURCE_STATE_ALL_SHADER_RESOURCE
	}
	if .Storage_Image in usage {
		return {.UNORDERED_ACCESS}
	}
	return d3d12.RESOURCE_STATE_COMMON
}

d3d12_heap_properties :: proc(heap_type: d3d12.HEAP_TYPE) -> d3d12.HEAP_PROPERTIES {
	return {
		Type = heap_type,
		CPUPageProperty = .UNKNOWN,
		MemoryPoolPreference = .UNKNOWN,
		CreationNodeMask = 1,
		VisibleNodeMask = 1,
	}
}

d3d12_heap_type_for_buffer :: proc(usage: Buffer_Usage) -> d3d12.HEAP_TYPE {
	if .Storage in usage {
		return .DEFAULT
	}
	if .Indirect in usage && !(.Vertex in usage) && !(.Index in usage) && !(.Uniform in usage) {
		return .DEFAULT
	}
	return .UPLOAD
}

d3d12_initial_buffer_state :: proc(usage: Buffer_Usage, heap_type: d3d12.HEAP_TYPE) -> d3d12.RESOURCE_STATES {
	if heap_type == .UPLOAD {
		return d3d12.RESOURCE_STATE_GENERIC_READ
	}
	if .Storage in usage {
		return {.UNORDERED_ACCESS}
	}
	if .Indirect in usage {
		return {.INDIRECT_ARGUMENT}
	}
	return d3d12.RESOURCE_STATE_COMMON
}

d3d12_buffer_resource_desc :: proc(size: u64, usage: Buffer_Usage) -> d3d12.RESOURCE_DESC {
	flags: d3d12.RESOURCE_FLAGS
	if .Storage in usage {
		flags += {.ALLOW_UNORDERED_ACCESS}
	}
	return {
		Dimension = .BUFFER,
		Width = size,
		Height = 1,
		DepthOrArraySize = 1,
		MipLevels = 1,
		Format = .UNKNOWN,
		SampleDesc = dxgi.SAMPLE_DESC{Count = 1, Quality = 0},
		Layout = .ROW_MAJOR,
		Flags = flags,
	}
}

d3d12_image_resource_desc :: proc(info: D3D12_Image) -> d3d12.RESOURCE_DESC {
	flags: d3d12.RESOURCE_FLAGS
	if .Color_Attachment in info.usage {
		flags += {.ALLOW_RENDER_TARGET}
	}
	if .Depth_Stencil_Attachment in info.usage {
		flags += {.ALLOW_DEPTH_STENCIL}
	}
	if .Storage_Image in info.usage {
		flags += {.ALLOW_UNORDERED_ACCESS}
	}
	return {
		Dimension = .TEXTURE2D,
		Width = u64(info.width),
		Height = info.height,
		DepthOrArraySize = u16(info.array_count),
		MipLevels = u16(info.mip_count),
		Format = d3d12_resource_format(info.format, info.usage),
		SampleDesc = dxgi.SAMPLE_DESC{Count = info.sample_count, Quality = 0},
		Layout = .UNKNOWN,
		Flags = flags,
	}
}

d3d12_initial_image_state :: proc(usage: Image_Usage) -> d3d12.RESOURCE_STATES {
	if .Immutable in usage {
		return {.COPY_DEST}
	}
	if .Texture in usage && !(.Color_Attachment in usage) && !(.Depth_Stencil_Attachment in usage) && !(.Storage_Image in usage) {
		return d3d12.RESOURCE_STATE_ALL_SHADER_RESOURCE
	}
	if .Storage_Image in usage {
		return {.UNORDERED_ACCESS}
	}
	if .Color_Attachment in usage {
		return {.RENDER_TARGET}
	}
	if .Depth_Stencil_Attachment in usage {
		return {.DEPTH_WRITE}
	}
	return d3d12.RESOURCE_STATE_COMMON
}

d3d12_image_needs_clear_value :: proc(usage: Image_Usage) -> bool {
	return .Color_Attachment in usage || .Depth_Stencil_Attachment in usage
}

d3d12_clear_value_for_image :: proc(format: Pixel_Format, usage: Image_Usage) -> d3d12.CLEAR_VALUE {
	clear_value: d3d12.CLEAR_VALUE
	if .Color_Attachment in usage {
		clear_value.Format = d3d12_dxgi_format(format)
		clear_value.Color = {0, 0, 0, 1}
		return clear_value
	}
	if .Depth_Stencil_Attachment in usage {
		clear_value.Format = d3d12_dxgi_format(format)
		clear_value.DepthStencil = {Depth = 1, Stencil = 0}
		return clear_value
	}
	return clear_value
}

d3d12_create_upload_buffer :: proc(ctx: ^Context, state: ^D3D12_State, out: ^D3D12_Buffer, size: int, label: string) -> bool {
	desc := d3d12_buffer_resource_desc(u64(size), {})
	heap_props := d3d12_heap_properties(.UPLOAD)
	raw: rawptr
	hr := state.device.CreateCommittedResource(state.device, &heap_props, d3d12.HEAP_FLAG_ALLOW_ALL_BUFFERS_AND_TEXTURES, &desc, d3d12.RESOURCE_STATE_GENERIC_READ, nil, d3d12.IResource_UUID, &raw)
	if d3d12_failed(hr) || raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateCommittedResource(upload buffer) failed", hr)
		return false
	}
	out.resource = cast(^d3d12.IResource)raw
	out.size = u64(size)
	out.state = d3d12.RESOURCE_STATE_GENERIC_READ
	read_range := d3d12.RANGE{}
	hr = out.resource.Map(out.resource, 0, &read_range, &out.mapped)
	if d3d12_failed(hr) || out.mapped == nil {
		out.resource.Release(out.resource)
		out^ = {}
		d3d12_set_error_hr(ctx, "gfx.d3d12: Map(upload buffer) failed", hr)
		return false
	}
	d3d12_set_debug_name(cast(^d3d12.IObject)out.resource, label)
	return true
}

d3d12_upload_to_default_buffer :: proc(ctx: ^Context, state: ^D3D12_State, dest: ^D3D12_Buffer, data: Range) -> bool {
	upload: D3D12_Buffer
	if !d3d12_create_upload_buffer(ctx, state, &upload, data.size, "buffer upload") {
		return false
	}
	mem.copy(upload.mapped, data.ptr, data.size)
	if !d3d12_begin_commands(ctx, state) {
		d3d12_release_buffer(&upload)
		return false
	}
	d3d12_transition_buffer(state, dest, {.COPY_DEST})
	state.cmd.CopyBufferRegion(state.cmd, dest.resource, 0, upload.resource, 0, u64(data.size))
	d3d12_transition_buffer(state, dest, d3d12_initial_buffer_state(dest.usage, .DEFAULT))
	append(&state.pending_uploads, upload.resource)
	upload.resource = nil
	d3d12_release_buffer(&upload)
	return d3d12_submit_and_wait(ctx, state)
}

d3d12_upload_initial_image_data :: proc(ctx: ^Context, state: ^D3D12_State, image: ^D3D12_Image, desc: Image_Desc) -> bool {
	for mip in 0..<int(image.mip_count) {
		mip_data := image_mip_data(desc, mip)
		width := mip_dimension(image.width, u32(mip))
		height := mip_dimension(image.height, u32(mip))
		row_pitch := image_mip_row_pitch(mip_data, width, pixel_format_size(image.format))
		if !d3d12_upload_image_region(ctx, state, image, u32(mip), 0, 0, 0, width, height, mip_data.data, row_pitch) {
			return false
		}
	}
	return true
}

d3d12_upload_image_region :: proc(ctx: ^Context, state: ^D3D12_State, image: ^D3D12_Image, mip_level, array_layer, x, y, width, height: u32, data: Range, row_pitch: u32) -> bool {
	if !d3d12_begin_commands(ctx, state) {
		return false
	}
	aligned_row_pitch := u32(align_up(int(row_pitch), D3D12_TEXTURE_DATA_PITCH_ALIGNMENT))
	upload_size := int(aligned_row_pitch) * int(height)
	upload: D3D12_Buffer
	if !d3d12_create_upload_buffer(ctx, state, &upload, upload_size, "image upload") {
		return false
	}
	dst := cast([^]u8)upload.mapped
	src := cast([^]u8)data.ptr
	for row: u32 = 0; row < height; row += 1 {
		mem.copy(rawptr(&dst[row * aligned_row_pitch]), rawptr(&src[row * row_pitch]), int(row_pitch))
	}

	footprint := d3d12.PLACED_SUBRESOURCE_FOOTPRINT {
		Offset = 0,
		Footprint = {
			Format = d3d12_dxgi_format(image.format),
			Width = width,
			Height = height,
			Depth = 1,
			RowPitch = aligned_row_pitch,
		},
	}
	src_loc := d3d12.TEXTURE_COPY_LOCATION {
		pResource = upload.resource,
		Type = .PLACED_FOOTPRINT,
		PlacedFootprint = footprint,
	}
	subresource := mip_level + array_layer * image.mip_count
	dst_loc := d3d12.TEXTURE_COPY_LOCATION {
		pResource = image.resource,
		Type = .SUBRESOURCE_INDEX,
		SubresourceIndex = subresource,
	}
	d3d12_transition_image(state, image, {.COPY_DEST})
	state.cmd.CopyTextureRegion(state.cmd, &dst_loc, x, y, 0, &src_loc, nil)
	d3d12_transition_image(state, image, d3d12_post_write_image_state(image.usage))
	append(&state.pending_uploads, upload.resource)
	upload.resource = nil
	d3d12_release_buffer(&upload)
	return d3d12_submit_and_wait(ctx, state)
}

d3d12_release_pending_uploads :: proc(state: ^D3D12_State) {
	for resource in state.pending_uploads {
		if resource != nil {
			resource.Release(resource)
		}
	}
	clear(&state.pending_uploads)
}

d3d12_release_buffer :: proc(buffer: ^D3D12_Buffer) {
	if buffer == nil {
		return
	}
	if buffer.resource != nil && buffer.mapped != nil {
		write_range := d3d12.RANGE{}
		buffer.resource.Unmap(buffer.resource, 0, &write_range)
		buffer.mapped = nil
	}
	if buffer.resource != nil {
		buffer.resource.Release(buffer.resource)
		buffer.resource = nil
	}
	if buffer.upload != nil {
		buffer.upload.Release(buffer.upload)
		buffer.upload = nil
	}
	buffer^ = {}
}

d3d12_release_image :: proc(image: ^D3D12_Image) {
	if image == nil {
		return
	}
	if image.resource != nil {
		image.resource.Release(image.resource)
		image.resource = nil
	}
	if image.upload != nil {
		image.upload.Release(image.upload)
		image.upload = nil
	}
	image^ = {}
}

d3d12_release_root_info :: proc(root: ^D3D12_Root_Info) {
	if root == nil {
		return
	}
	if root.root_signature != nil {
		root.root_signature.Release(root.root_signature)
		root.root_signature = nil
	}
	root^ = {}
}

d3d12_release_pipeline :: proc(pipeline: ^D3D12_Pipeline) {
	if pipeline == nil {
		return
	}
	if pipeline.pso != nil {
		pipeline.pso.Release(pipeline.pso)
		pipeline.pso = nil
	}
	d3d12_release_root_info(&pipeline.root)
	pipeline^ = {}
}

d3d12_release_compute_pipeline :: proc(pipeline: ^D3D12_Compute_Pipeline) {
	if pipeline == nil {
		return
	}
	if pipeline.pso != nil {
		pipeline.pso.Release(pipeline.pso)
		pipeline.pso = nil
	}
	d3d12_release_root_info(&pipeline.root)
	pipeline^ = {}
}

d3d12_release_swapchain_views :: proc(state: ^D3D12_State) {
	for i in 0..<D3D12_FRAME_COUNT {
		if state.backbuffers[i].backbuffer != nil {
			state.backbuffers[i].backbuffer.Release(state.backbuffers[i].backbuffer)
			state.backbuffers[i] = {}
		}
	}
	if state.default_depth != nil {
		state.default_depth.Release(state.default_depth)
		state.default_depth = nil
	}
}

d3d12_release_state :: proc(state: ^D3D12_State) {
	if state == nil {
		return
	}
	d3d12_release_pending_uploads(state)
	for _, &pipeline in state.pipelines {
		d3d12_release_pipeline(&pipeline)
	}
	for _, &pipeline in state.compute_pipelines {
		d3d12_release_compute_pipeline(&pipeline)
	}
	for _, &shader in state.shaders {
		delete(shader.vertex_bytecode)
		delete(shader.pixel_bytecode)
		delete(shader.compute_bytecode)
	}
	for _, &buffer in state.buffers {
		d3d12_release_buffer(&buffer)
	}
	for _, &image in state.images {
		d3d12_release_image(&image)
	}
	for group in 0..<MAX_BINDING_GROUPS {
		for slot in 0..<MAX_UNIFORM_BLOCKS {
			d3d12_release_buffer(&state.uniform_uploads[group][slot])
		}
	}
	delete(state.pipelines)
	delete(state.compute_pipelines)
	delete(state.shaders)
	delete(state.samplers)
	delete(state.views)
	delete(state.images)
	delete(state.buffers)
	delete(state.pending_uploads)
	d3d12_release_swapchain_views(state)
	if state.draw_signature != nil { state.draw_signature.Release(state.draw_signature) }
	if state.draw_indexed_signature != nil { state.draw_indexed_signature.Release(state.draw_indexed_signature) }
	if state.dispatch_signature != nil { state.dispatch_signature.Release(state.dispatch_signature) }
	if state.gpu_samplers.heap != nil { state.gpu_samplers.heap.Release(state.gpu_samplers.heap) }
	if state.gpu_cbv_srv_uav.heap != nil { state.gpu_cbv_srv_uav.heap.Release(state.gpu_cbv_srv_uav.heap) }
	if state.cpu_samplers.heap != nil { state.cpu_samplers.heap.Release(state.cpu_samplers.heap) }
	if state.cpu_cbv_srv_uav.heap != nil { state.cpu_cbv_srv_uav.heap.Release(state.cpu_cbv_srv_uav.heap) }
	if state.dsv_heap.heap != nil { state.dsv_heap.heap.Release(state.dsv_heap.heap) }
	if state.rtv_heap.heap != nil { state.rtv_heap.heap.Release(state.rtv_heap.heap) }
	if state.swapchain != nil { state.swapchain.Release(state.swapchain) }
	if state.fence_event != nil { _ = win32.CloseHandle(state.fence_event) }
	if state.fence != nil { state.fence.Release(state.fence) }
	if state.cmd != nil { state.cmd.Release(state.cmd) }
	if state.allocator != nil { state.allocator.Release(state.allocator) }
	if state.queue != nil { state.queue.Release(state.queue) }
	if state.device != nil { state.device.Release(state.device) }
	if state.factory != nil { state.factory.Release(state.factory) }
}

d3d12_dxgi_format :: proc(format: Pixel_Format) -> dxgi.FORMAT {
	switch format {
	case .RGBA8:
		return .R8G8B8A8_UNORM
	case .BGRA8:
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
	case .Invalid:
		return .UNKNOWN
	}
	return .UNKNOWN
}

d3d12_resource_format :: proc(format: Pixel_Format, usage: Image_Usage) -> dxgi.FORMAT {
	if .Depth_Stencil_Attachment in usage && .Texture in usage {
		#partial switch format {
		case .D32F:
			return .R32_TYPELESS
		case .D24S8:
			return .R24G8_TYPELESS
		}
	}
	return d3d12_dxgi_format(format)
}

d3d12_srv_format :: proc(format: Pixel_Format) -> dxgi.FORMAT {
	#partial switch format {
	case .D32F:
		return .R32_FLOAT
	case .D24S8:
		return .R24_UNORM_X8_TYPELESS
	}
	return d3d12_dxgi_format(format)
}

d3d12_vertex_format :: proc(format: Vertex_Format) -> dxgi.FORMAT {
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

d3d12_index_format :: proc(index_type: Index_Type) -> dxgi.FORMAT {
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

d3d12_primitive_topology :: proc(value: Primitive_Type) -> d3d12.PRIMITIVE_TOPOLOGY {
	switch value {
	case .Triangles:
		return .TRIANGLELIST
	case .Lines:
		return .LINELIST
	case .Points:
		return .POINTLIST
	}
	return .TRIANGLELIST
}

d3d12_primitive_topology_type :: proc(value: Primitive_Type) -> d3d12.PRIMITIVE_TOPOLOGY_TYPE {
	switch value {
	case .Triangles:
		return .TRIANGLE
	case .Lines:
		return .LINE
	case .Points:
		return .POINT
	}
	return .TRIANGLE
}

d3d12_input_class :: proc(value: Vertex_Step_Function) -> d3d12.INPUT_CLASSIFICATION {
	switch value {
	case .Per_Instance:
		return .PER_INSTANCE_DATA
	case .Per_Vertex:
		return .PER_VERTEX_DATA
	}
	return .PER_VERTEX_DATA
}

d3d12_compare_func :: proc(compare: Compare_Func) -> d3d12.COMPARISON_FUNC {
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

d3d12_rasterizer_desc :: proc(raster: Raster_State) -> d3d12.RASTERIZER_DESC {
	return {
		FillMode = .SOLID if raster.fill_mode == .Solid else .WIREFRAME,
		CullMode = d3d12_cull_mode(raster.cull_mode),
		FrontCounterClockwise = win32.TRUE if raster.winding == .Counter_Clockwise else win32.FALSE,
		DepthClipEnable = win32.TRUE,
		MultisampleEnable = win32.FALSE,
		AntialiasedLineEnable = win32.FALSE,
		ConservativeRaster = .OFF,
	}
}

d3d12_cull_mode :: proc(value: Cull_Mode) -> d3d12.CULL_MODE {
	switch value {
	case .None:
		return .NONE
	case .Front:
		return .FRONT
	case .Back:
		return .BACK
	}
	return .NONE
}

d3d12_depth_stencil_desc :: proc(depth: Depth_State) -> d3d12.DEPTH_STENCIL_DESC {
	return {
		DepthEnable = win32.TRUE if depth.enabled else win32.FALSE,
		DepthWriteMask = .ALL if depth.write_enabled else .ZERO,
		DepthFunc = d3d12_compare_func(depth.compare),
		StencilEnable = win32.FALSE,
		StencilReadMask = 0xff,
		StencilWriteMask = 0xff,
		FrontFace = d3d12_default_stencil_op_desc(),
		BackFace = d3d12_default_stencil_op_desc(),
	}
}

d3d12_default_stencil_op_desc :: proc() -> d3d12.DEPTH_STENCILOP_DESC {
	return {
		StencilFailOp = .KEEP,
		StencilDepthFailOp = .KEEP,
		StencilPassOp = .KEEP,
		StencilFunc = .ALWAYS,
	}
}

d3d12_blend_desc :: proc(desc: Pipeline_Desc) -> d3d12.BLEND_DESC {
	blend: d3d12.BLEND_DESC
	blend.AlphaToCoverageEnable = win32.FALSE
	blend.IndependentBlendEnable = win32.FALSE
	for i in 0..<8 {
		blend.RenderTarget[i] = d3d12_render_target_blend_desc(desc.colors[i])
	}
	return blend
}

d3d12_render_target_blend_desc :: proc(color: Color_State) -> d3d12.RENDER_TARGET_BLEND_DESC {
	blend := color.blend
	return {
		BlendEnable = win32.TRUE if blend.enabled else win32.FALSE,
		LogicOpEnable = win32.FALSE,
		SrcBlend = d3d12_blend_factor(blend.src_factor, .ONE),
		DestBlend = d3d12_blend_factor(blend.dst_factor, .ZERO),
		BlendOp = d3d12_blend_op(blend.op),
		SrcBlendAlpha = d3d12_blend_factor(blend.src_alpha_factor, .ONE),
		DestBlendAlpha = d3d12_blend_factor(blend.dst_alpha_factor, .ZERO),
		BlendOpAlpha = d3d12_blend_op(blend.alpha_op),
		LogicOp = .NOOP,
		RenderTargetWriteMask = d3d12_color_write_mask(color.write_mask),
	}
}

d3d12_blend_factor :: proc(factor: Blend_Factor, fallback: d3d12.BLEND) -> d3d12.BLEND {
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

d3d12_blend_op :: proc(op: Blend_Op) -> d3d12.BLEND_OP {
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

d3d12_color_write_mask :: proc(mask: u8) -> u8 {
	if mask == 0 {
		return COLOR_MASK_RGBA
	}
	result: u8
	if mask & COLOR_MASK_R != 0 { result |= COLOR_MASK_R }
	if mask & COLOR_MASK_G != 0 { result |= COLOR_MASK_G }
	if mask & COLOR_MASK_B != 0 { result |= COLOR_MASK_B }
	if mask & COLOR_MASK_A != 0 { result |= COLOR_MASK_A }
	return result
}

d3d12_filter :: proc(min_filter, mag_filter, mip_filter: Filter) -> d3d12.FILTER {
	if min_filter == .Linear && mag_filter == .Linear && mip_filter == .Linear {
		return .MIN_MAG_MIP_LINEAR
	}
	if min_filter == .Linear && mag_filter == .Linear {
		return .MIN_MAG_LINEAR_MIP_POINT
	}
	if min_filter == .Linear {
		return .MIN_LINEAR_MAG_MIP_POINT
	}
	if mag_filter == .Linear {
		return .MIN_POINT_MAG_LINEAR_MIP_POINT
	}
	if mip_filter == .Linear {
		return .MIN_MAG_POINT_MIP_LINEAR
	}
	return .MIN_MAG_MIP_POINT
}

d3d12_wrap :: proc(wrap: Wrap) -> d3d12.TEXTURE_ADDRESS_MODE {
	switch wrap {
	case .Repeat:
		return .WRAP
	case .Clamp_To_Edge:
		return .CLAMP
	case .Mirrored_Repeat:
		return .MIRROR
	}
	return .CLAMP
}

d3d12_default_component_mapping :: proc() -> u32 {
	return d3d12.ENCODE_SHADER_4_COMPONENT_MAPPING(
		u32(d3d12.SHADER_COMPONENT_MAPPING.FROM_MEMORY_COMPONENT_0),
		u32(d3d12.SHADER_COMPONENT_MAPPING.FROM_MEMORY_COMPONENT_1),
		u32(d3d12.SHADER_COMPONENT_MAPPING.FROM_MEMORY_COMPONENT_2),
		u32(d3d12.SHADER_COMPONENT_MAPPING.FROM_MEMORY_COMPONENT_3),
	)
}

d3d12_set_debug_name :: proc(object: ^d3d12.IObject, label: string) {
	if object == nil || label == "" {
		return
	}
	name_utf16: [D3D12_DEBUG_NAME_MAX_UTF16]u16
	name := win32.utf8_to_utf16(name_utf16[:], label)
	if len(name) == 0 {
		return
	}
	object.SetName(object, cstring16(raw_data(name)))
}

d3d12_create_sampled_image_descriptor :: proc(state: ^D3D12_State, image: D3D12_Image, view: D3D12_View, requested_mip_count: i32) {
	d3d12_write_sampled_image_descriptor(state, image, view, requested_mip_count, view.cpu_handle)
}

d3d12_write_sampled_image_descriptor :: proc(state: ^D3D12_State, image: D3D12_Image, view: D3D12_View, requested_mip_count: i32, dest: d3d12.CPU_DESCRIPTOR_HANDLE) {
	mip_count := u32(requested_mip_count)
	if mip_count == 0 {
		mip_count = image.mip_count - view.mip_level
	}
	desc := d3d12.SHADER_RESOURCE_VIEW_DESC {
		Format = d3d12_srv_format(view.format),
		Shader4ComponentMapping = d3d12_default_component_mapping(),
	}
	if image.sample_count > 1 {
		desc.ViewDimension = .TEXTURE2DMS
	} else if image.array_count > 1 {
		desc.ViewDimension = .TEXTURE2DARRAY
		desc.Texture2DArray = {
			MostDetailedMip = view.mip_level,
			MipLevels = mip_count,
			FirstArraySlice = view.base_layer,
			ArraySize = view.layer_count,
			ResourceMinLODClamp = 0,
		}
	} else {
		desc.ViewDimension = .TEXTURE2D
		desc.Texture2D = {
			MostDetailedMip = view.mip_level,
			MipLevels = mip_count,
			PlaneSlice = 0,
			ResourceMinLODClamp = 0,
		}
	}
	state.device.CreateShaderResourceView(state.device, image.resource, &desc, dest)
}

d3d12_create_storage_image_descriptor :: proc(state: ^D3D12_State, image: D3D12_Image, view: D3D12_View) {
	d3d12_write_storage_image_descriptor(state, image, view, view.cpu_handle)
}

d3d12_write_storage_image_descriptor :: proc(state: ^D3D12_State, image: D3D12_Image, view: D3D12_View, dest: d3d12.CPU_DESCRIPTOR_HANDLE) {
	desc := d3d12.UNORDERED_ACCESS_VIEW_DESC {
		Format = d3d12_dxgi_format(view.format),
	}
	if image.array_count > 1 {
		desc.ViewDimension = .TEXTURE2DARRAY
		desc.Texture2DArray = {
			MipSlice = view.mip_level,
			FirstArraySlice = view.base_layer,
			ArraySize = view.layer_count,
			PlaneSlice = 0,
		}
	} else {
		desc.ViewDimension = .TEXTURE2D
		desc.Texture2D = {
			MipSlice = view.mip_level,
			PlaneSlice = 0,
		}
	}
	state.device.CreateUnorderedAccessView(state.device, image.resource, nil, &desc, dest)
}

d3d12_create_storage_buffer_descriptor :: proc(state: ^D3D12_State, buffer: D3D12_Buffer, view: D3D12_View) {
	d3d12_write_storage_buffer_descriptor(state, buffer, view, view.cpu_handle)
}

d3d12_write_storage_buffer_descriptor :: proc(state: ^D3D12_State, buffer: D3D12_Buffer, view: D3D12_View, dest: d3d12.CPU_DESCRIPTOR_HANDLE) {
	desc := d3d12.UNORDERED_ACCESS_VIEW_DESC {
		Format = .UNKNOWN,
		ViewDimension = .BUFFER,
	}
	if buffer.storage_stride > 0 {
		desc.Buffer = {
			FirstElement = u64(view.offset / int(buffer.storage_stride)),
			NumElements = u32(view.size / int(buffer.storage_stride)),
			StructureByteStride = buffer.storage_stride,
		}
	} else {
		desc.Format = .R32_TYPELESS
		desc.Buffer = {
			FirstElement = u64(view.offset / 4),
			NumElements = u32(view.size / 4),
			StructureByteStride = 0,
			Flags = {.RAW},
		}
	}
	state.device.CreateUnorderedAccessView(state.device, buffer.resource, nil, &desc, dest)
}

d3d12_write_storage_buffer_srv_descriptor :: proc(state: ^D3D12_State, buffer: D3D12_Buffer, view: D3D12_View, dest: d3d12.CPU_DESCRIPTOR_HANDLE) {
	desc := d3d12.SHADER_RESOURCE_VIEW_DESC {
		Format = .UNKNOWN,
		ViewDimension = .BUFFER,
		Shader4ComponentMapping = d3d12_default_component_mapping(),
	}
	if buffer.storage_stride > 0 {
		desc.Buffer = {
			FirstElement = u64(view.offset / int(buffer.storage_stride)),
			NumElements = u32(view.size / int(buffer.storage_stride)),
			StructureByteStride = buffer.storage_stride,
		}
	} else {
		desc.Format = .R32_TYPELESS
		desc.Buffer = {
			FirstElement = u64(view.offset / 4),
			NumElements = u32(view.size / 4),
			StructureByteStride = 0,
			Flags = {.RAW},
		}
	}
	state.device.CreateShaderResourceView(state.device, buffer.resource, &desc, dest)
}

d3d12_create_rtv_descriptor :: proc(state: ^D3D12_State, image: D3D12_Image, view: D3D12_View) {
	desc := d3d12.RENDER_TARGET_VIEW_DESC {
		Format = d3d12_dxgi_format(view.format),
	}
	if image.sample_count > 1 {
		desc.ViewDimension = .TEXTURE2DMS
	} else if image.array_count > 1 {
		desc.ViewDimension = .TEXTURE2DARRAY
		desc.Texture2DArray = {
			MipSlice = view.mip_level,
			FirstArraySlice = view.base_layer,
			ArraySize = view.layer_count,
			PlaneSlice = 0,
		}
	} else {
		desc.ViewDimension = .TEXTURE2D
		desc.Texture2D = {MipSlice = view.mip_level, PlaneSlice = 0}
	}
	state.device.CreateRenderTargetView(state.device, image.resource, &desc, view.cpu_handle)
}

d3d12_create_dsv_descriptor :: proc(state: ^D3D12_State, image: D3D12_Image, view: D3D12_View) {
	desc := d3d12.DEPTH_STENCIL_VIEW_DESC {
		Format = d3d12_dxgi_format(view.format),
	}
	if image.sample_count > 1 {
		desc.ViewDimension = .TEXTURE2DMS
	} else if image.array_count > 1 {
		desc.ViewDimension = .TEXTURE2DARRAY
		desc.Texture2DArray = {
			MipSlice = view.mip_level,
			FirstArraySlice = view.base_layer,
			ArraySize = view.layer_count,
		}
	} else {
		desc.ViewDimension = .TEXTURE2D
		desc.Texture2D = {MipSlice = view.mip_level}
	}
	state.device.CreateDepthStencilView(state.device, image.resource, &desc, view.cpu_handle)
}

d3d12_build_root_signature :: proc(ctx: ^Context, state: ^D3D12_State, shader: D3D12_Shader, root: ^D3D12_Root_Info, compute: bool) -> bool {
	root^ = {}
	for stage in Shader_Stage {
		if compute && stage != .Compute {
			continue
		}
		if !compute && stage == .Compute {
			continue
		}
		stage_index := int(stage)
		for group in 0..<MAX_BINDING_GROUPS {
			for slot in 0..<MAX_UNIFORM_BLOCKS {
				binding := shader.uniform_slots[stage_index][group][slot]
				if !binding.active {
					continue
				}
				d3d12_add_resource_root_entry(root, .Uniform, stage, u32(group), u32(slot), binding)
			}
			for slot in 0..<MAX_RESOURCE_VIEWS {
				binding := shader.view_slots[stage_index][group][slot]
				if !binding.active {
					continue
				}
				d3d12_add_resource_root_entry(root, .View, stage, u32(group), u32(slot), binding)
			}
			for slot in 0..<MAX_SAMPLERS {
				binding := shader.sampler_slots[stage_index][group][slot]
				if !binding.active {
					continue
				}
				d3d12_add_sampler_root_entry(root, stage, u32(group), u32(slot), binding)
			}
		}
	}

	parameters: [2]d3d12.ROOT_PARAMETER
	param_count: u32
	if root.resource_count > 0 {
		root.has_resource_table = true
		root.resource_root_index = param_count
		parameters[param_count] = {
			ParameterType = .DESCRIPTOR_TABLE,
			DescriptorTable = {
				NumDescriptorRanges = root.resource_count,
				pDescriptorRanges = &root.resource_ranges[0],
			},
			ShaderVisibility = .ALL,
		}
		for i in 0..<int(root.resource_count) {
			root.resource_entries[i].root_index = param_count
		}
		param_count += 1
	}
	if root.sampler_count > 0 {
		root.has_sampler_table = true
		root.sampler_root_index = param_count
		parameters[param_count] = {
			ParameterType = .DESCRIPTOR_TABLE,
			DescriptorTable = {
				NumDescriptorRanges = root.sampler_count,
				pDescriptorRanges = &root.sampler_ranges[0],
			},
			ShaderVisibility = .ALL,
		}
		for i in 0..<int(root.sampler_count) {
			root.sampler_entries[i].root_index = param_count
		}
		param_count += 1
	}

	flags := d3d12.ROOT_SIGNATURE_FLAGS{.ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT}
	if compute {
		flags = {}
	}
	root_desc := d3d12.ROOT_SIGNATURE_DESC {
		NumParameters = param_count,
		pParameters = &parameters[0],
		Flags = flags,
	}
	if param_count == 0 {
		root_desc.pParameters = nil
	}
	blob: ^d3d12.IBlob
	error_blob: ^d3d12.IBlob
	hr := d3d12.SerializeRootSignature(&root_desc, ._1_0, &blob, &error_blob)
	if d3d12_failed(hr) || blob == nil {
		if error_blob != nil {
			message := string(cast(cstring)error_blob.GetBufferPointer(error_blob))
			set_backend_errorf(ctx, "gfx.d3d12: SerializeRootSignature failed: %s", message)
			error_blob.Release(error_blob)
		} else {
			d3d12_set_error_hr(ctx, "gfx.d3d12: SerializeRootSignature failed", hr)
		}
		return false
	}
	defer blob.Release(blob)
	if error_blob != nil {
		error_blob.Release(error_blob)
	}
	root_raw: rawptr
	hr = state.device.CreateRootSignature(state.device, 0, blob.GetBufferPointer(blob), blob.GetBufferSize(blob), d3d12.IRootSignature_UUID, &root_raw)
	if d3d12_failed(hr) || root_raw == nil {
		d3d12_set_error_hr(ctx, "gfx.d3d12: CreateRootSignature failed", hr)
		return false
	}
	root.root_signature = cast(^d3d12.IRootSignature)root_raw
	return true
}

d3d12_add_resource_root_entry :: proc(root: ^D3D12_Root_Info, kind: D3D12_Root_Entry_Kind, stage: Shader_Stage, group, slot: u32, binding: D3D12_Binding_Slot) {
	range_type := d3d12.DESCRIPTOR_RANGE_TYPE.CBV
	if kind == .View {
		if binding.view_kind == .Sampled || binding.access == .Read {
			range_type = .SRV
		} else {
			range_type = .UAV
		}
	}
	if d3d12_root_resource_exists(root, range_type, binding.native_slot, binding.native_space) {
		return
	}
	index := root.resource_count
	if index >= MAX_SHADER_BINDINGS {
		return
	}
	count := binding.array_count
	if count == 0 {
		count = 1
	}
	root.resource_ranges[index] = {
		RangeType = range_type,
		NumDescriptors = count,
		BaseShaderRegister = binding.native_slot,
		RegisterSpace = binding.native_space,
		OffsetInDescriptorsFromTableStart = root.resource_table_count,
	}
	root.resource_entries[index] = {
		active = true,
		kind = kind,
		stage = stage,
		group = group,
		logical_slot = slot,
		array_count = count,
		table_offset = root.resource_table_count,
		native_slot = binding.native_slot,
		native_space = binding.native_space,
		descriptor_type = range_type,
		size = binding.size,
		view_kind = binding.view_kind,
		access = binding.access,
	}
	root.resource_count += 1
	root.resource_table_count += count
}

d3d12_add_sampler_root_entry :: proc(root: ^D3D12_Root_Info, stage: Shader_Stage, group, slot: u32, binding: D3D12_Binding_Slot) {
	if d3d12_root_sampler_exists(root, binding.native_slot, binding.native_space) {
		return
	}
	index := root.sampler_count
	if index >= MAX_SHADER_BINDINGS {
		return
	}
	count := binding.array_count
	if count == 0 {
		count = 1
	}
	root.sampler_ranges[index] = {
		RangeType = .SAMPLER,
		NumDescriptors = count,
		BaseShaderRegister = binding.native_slot,
		RegisterSpace = binding.native_space,
		OffsetInDescriptorsFromTableStart = root.sampler_table_count,
	}
	root.sampler_entries[index] = {
		active = true,
		kind = .Sampler,
		stage = stage,
		group = group,
		logical_slot = slot,
		array_count = count,
		table_offset = root.sampler_table_count,
		native_slot = binding.native_slot,
		native_space = binding.native_space,
		descriptor_type = .SAMPLER,
	}
	root.sampler_count += 1
	root.sampler_table_count += count
}

d3d12_root_resource_exists :: proc(root: ^D3D12_Root_Info, range_type: d3d12.DESCRIPTOR_RANGE_TYPE, native_slot, native_space: u32) -> bool {
	for i in 0..<int(root.resource_count) {
		entry := root.resource_entries[i]
		if entry.active && entry.descriptor_type == range_type && entry.native_slot == native_slot && entry.native_space == native_space {
			return true
		}
	}
	return false
}

d3d12_root_sampler_exists :: proc(root: ^D3D12_Root_Info, native_slot, native_space: u32) -> bool {
	for i in 0..<int(root.sampler_count) {
		entry := root.sampler_entries[i]
		if entry.active && entry.native_slot == native_slot && entry.native_space == native_space {
			return true
		}
	}
	return false
}

d3d12_bind_graphics_resource_tables :: proc(ctx: ^Context, state: ^D3D12_State, pipeline: ^D3D12_Pipeline, bindings: Bindings) -> bool {
	root := &pipeline.root
	resource_start: u32
	if root.has_resource_table {
		resource_start = state.gpu_cbv_srv_uav.next
		if !d3d12_copy_resource_descriptors(ctx, state, root, bindings, resource_start) {
			return false
		}
	}
	sampler_start: u32
	if root.has_sampler_table {
		sampler_start = state.gpu_samplers.next
		if !d3d12_copy_sampler_descriptors(ctx, state, root, bindings, sampler_start) {
			return false
		}
	}
	if root.has_resource_table {
		state.cmd.SetGraphicsRootDescriptorTable(state.cmd, root.resource_root_index, d3d12_descriptor_gpu(state.gpu_cbv_srv_uav, resource_start))
	}
	if root.has_sampler_table {
		state.cmd.SetGraphicsRootDescriptorTable(state.cmd, root.sampler_root_index, d3d12_descriptor_gpu(state.gpu_samplers, sampler_start))
	}
	d3d12_record_bound_masks(state, pipeline.required)
	return true
}

d3d12_bind_compute_resource_tables :: proc(ctx: ^Context, state: ^D3D12_State, pipeline: ^D3D12_Compute_Pipeline, bindings: Bindings) -> bool {
	root := &pipeline.root
	resource_start: u32
	if root.has_resource_table {
		resource_start = state.gpu_cbv_srv_uav.next
		if !d3d12_copy_resource_descriptors(ctx, state, root, bindings, resource_start) {
			return false
		}
	}
	sampler_start: u32
	if root.has_sampler_table {
		sampler_start = state.gpu_samplers.next
		if !d3d12_copy_sampler_descriptors(ctx, state, root, bindings, sampler_start) {
			return false
		}
	}
	if root.has_resource_table {
		state.cmd.SetComputeRootDescriptorTable(state.cmd, root.resource_root_index, d3d12_descriptor_gpu(state.gpu_cbv_srv_uav, resource_start))
	}
	if root.has_sampler_table {
		state.cmd.SetComputeRootDescriptorTable(state.cmd, root.sampler_root_index, d3d12_descriptor_gpu(state.gpu_samplers, sampler_start))
	}
	d3d12_record_bound_masks(state, pipeline.required)
	return true
}

d3d12_copy_resource_descriptors :: proc(ctx: ^Context, state: ^D3D12_State, root: ^D3D12_Root_Info, bindings: Bindings, table_start: u32) -> bool {
	if state.gpu_cbv_srv_uav.next + root.resource_table_count > state.gpu_cbv_srv_uav.capacity {
		set_backend_error(ctx, "gfx.d3d12: shader-visible resource descriptor heap exhausted")
		return false
	}
	for i in 0..<int(root.resource_count) {
		entry := root.resource_entries[i]
		if !entry.active {
			continue
		}
		for array_index: u32 = 0; array_index < entry.array_count; array_index += 1 {
			dest_index := table_start + entry.table_offset + array_index
			dest := d3d12_descriptor_cpu(state.gpu_cbv_srv_uav, dest_index)
			switch entry.kind {
			case .Uniform:
				uniform := state.uniform_bindings[entry.group][entry.logical_slot + array_index]
				if uniform.resource == nil {
					set_validation_errorf(ctx, "gfx.d3d12: missing uniform group %d slot %d", entry.group, entry.logical_slot + array_index)
					return false
				}
				cbv := d3d12.CONSTANT_BUFFER_VIEW_DESC {
					BufferLocation = uniform.gpu_va,
					SizeInBytes = u32(align_up(int(uniform.size), D3D12_CONSTANT_BUFFER_ALIGNMENT)),
				}
				state.device.CreateConstantBufferView(state.device, &cbv, dest)
			case .View:
				view := bindings.views[entry.group][entry.logical_slot + array_index]
				view_info, view_ok := state.views[view]
				if !view_ok || !view_info.has_descriptor {
					set_validation_errorf(ctx, "gfx.d3d12: missing resource view group %d slot %d", entry.group, entry.logical_slot + array_index)
					return false
				}
				if image_valid(view_info.image) {
					if image_info, image_ok := &state.images[view_info.image]; image_ok {
						d3d12_transition_image(state, image_info, d3d12_state_for_bound_view(entry, view_info))
					}
				}
				if buffer_valid(view_info.buffer) {
					if buffer_info, buffer_ok := &state.buffers[view_info.buffer]; buffer_ok {
						d3d12_transition_buffer(state, buffer_info, d3d12_state_for_bound_view(entry, view_info))
					}
				}
				if !d3d12_write_bound_view_descriptor(ctx, state, entry, view_info, dest) {
					return false
				}
			case .Sampler:
			}
		}
	}
	state.gpu_cbv_srv_uav.next += root.resource_table_count
	return true
}

d3d12_copy_sampler_descriptors :: proc(ctx: ^Context, state: ^D3D12_State, root: ^D3D12_Root_Info, bindings: Bindings, table_start: u32) -> bool {
	if state.gpu_samplers.next + root.sampler_table_count > state.gpu_samplers.capacity {
		set_backend_error(ctx, "gfx.d3d12: shader-visible sampler descriptor heap exhausted")
		return false
	}
	for i in 0..<int(root.sampler_count) {
		entry := root.sampler_entries[i]
		if !entry.active {
			continue
		}
		for array_index: u32 = 0; array_index < entry.array_count; array_index += 1 {
			sampler := bindings.samplers[entry.group][entry.logical_slot + array_index]
			sampler_info, sampler_ok := state.samplers[sampler]
			if !sampler_ok {
				set_validation_errorf(ctx, "gfx.d3d12: missing sampler group %d slot %d", entry.group, entry.logical_slot + array_index)
				return false
			}
			dest := d3d12_descriptor_cpu(state.gpu_samplers, table_start + entry.table_offset + array_index)
			state.device.CopyDescriptorsSimple(state.device, 1, dest, sampler_info.cpu_handle, .SAMPLER)
		}
	}
	state.gpu_samplers.next += root.sampler_table_count
	return true
}

d3d12_state_for_bound_view :: proc(entry: D3D12_Root_Entry, view: D3D12_View) -> d3d12.RESOURCE_STATES {
	if entry.descriptor_type == .UAV {
		return {.UNORDERED_ACCESS}
	}
	return d3d12.RESOURCE_STATE_ALL_SHADER_RESOURCE
}

d3d12_write_bound_view_descriptor :: proc(ctx: ^Context, state: ^D3D12_State, entry: D3D12_Root_Entry, view: D3D12_View, dest: d3d12.CPU_DESCRIPTOR_HANDLE) -> bool {
	switch view.kind {
	case .Sampled:
		image_info, image_ok := state.images[view.image]
		if !image_ok || image_info.resource == nil {
			set_invalid_handle_error(ctx, "gfx.d3d12: sampled image view resource is missing")
			return false
		}
		d3d12_write_sampled_image_descriptor(state, image_info, view, 0, dest)
	case .Storage_Image:
		image_info, image_ok := state.images[view.image]
		if !image_ok || image_info.resource == nil {
			set_invalid_handle_error(ctx, "gfx.d3d12: storage image view resource is missing")
			return false
		}
		if entry.descriptor_type == .UAV {
			d3d12_write_storage_image_descriptor(state, image_info, view, dest)
		} else {
			d3d12_write_sampled_image_descriptor(state, image_info, view, 1, dest)
		}
	case .Storage_Buffer:
		buffer_info, buffer_ok := state.buffers[view.buffer]
		if !buffer_ok || buffer_info.resource == nil {
			set_invalid_handle_error(ctx, "gfx.d3d12: storage buffer view resource is missing")
			return false
		}
		if entry.descriptor_type == .UAV {
			d3d12_write_storage_buffer_descriptor(state, buffer_info, view, dest)
		} else {
			d3d12_write_storage_buffer_srv_descriptor(state, buffer_info, view, dest)
		}
	case .Color_Attachment, .Depth_Stencil_Attachment:
		set_validation_error(ctx, "gfx.d3d12: attachment views cannot be bound as shader resource views")
		return false
	}
	return true
}

d3d12_record_bound_masks :: proc(state: ^D3D12_State, required: [3]D3D12_Binding_Masks) {
	for stage in 0..<3 {
		for group in 0..<MAX_BINDING_GROUPS {
			state.current_bindings[stage].views[group] |= required[stage].views[group]
			state.current_bindings[stage].samplers[group] |= required[stage].samplers[group]
		}
	}
}

d3d12_record_bound_resources_from_bindings :: proc(state: ^D3D12_State, bindings: Bindings) {
	for stage in 0..<3 {
		for group in 0..<MAX_BINDING_GROUPS {
			for view, slot in bindings.views[group] {
				if view_valid(view) {
					state.current_bindings[stage].views[group] |= d3d12_slot_mask(u32(slot))
				}
			}
			for sampler, slot in bindings.samplers[group] {
				if sampler_valid(sampler) {
					state.current_bindings[stage].samplers[group] |= d3d12_slot_mask(u32(slot))
				}
			}
		}
	}
}

d3d12_mark_uniform_bound :: proc(state: ^D3D12_State, group, slot: u32) {
	for stage in 0..<3 {
		state.current_bindings[stage].uniforms[group] |= d3d12_slot_mask(slot)
	}
}

d3d12_validate_uniform_binding :: proc(ctx: ^Context, state: ^D3D12_State, group: u32, slot: int, byte_size: u32) -> bool {
	found := false
	expected_size: u32
	if ctx.pass_kind == .Compute {
		pipeline, ok := state.compute_pipelines[state.current_compute_pipeline]
		if !ok {
			set_validation_error(ctx, "gfx.d3d12: apply_uniforms requires an applied compute pipeline")
			return false
		}
		info := pipeline.uniform_slots[int(Shader_Stage.Compute)][group][slot]
		if info.active {
			found = true
			expected_size = info.size
		}
	} else {
		pipeline, ok := state.pipelines[state.current_pipeline]
		if !ok {
			set_validation_error(ctx, "gfx.d3d12: apply_uniforms requires an applied pipeline")
			return false
		}
		for stage in 0..<2 {
			info := pipeline.uniform_slots[stage][group][slot]
			if info.active {
				found = true
				expected_size = info.size
			}
		}
	}
	if !found {
		set_validation_errorf(ctx, "gfx.d3d12: uniform group %d slot %d is not used by the current pipeline", group, slot)
		return false
	}
	if expected_size != 0 && byte_size != expected_size {
		set_validation_errorf(ctx, "gfx.d3d12: uniform group %d slot %d expects %d bytes, got %d", group, slot, expected_size, byte_size)
		return false
	}
	return true
}

d3d12_validate_draw_bindings :: proc(ctx: ^Context, state: ^D3D12_State, pipeline: ^D3D12_Pipeline) -> bool {
	if pipeline.required_vertex_buffers & ~state.current_vertex_buffers != 0 {
		set_validation_error(ctx, "gfx.d3d12: draw is missing a required vertex buffer")
		return false
	}
	for stage in 0..<2 {
		if !d3d12_required_masks_satisfied(ctx, pipeline.required[stage], state.current_bindings[stage], "draw") {
			return false
		}
	}
	return true
}

d3d12_validate_compute_bindings :: proc(ctx: ^Context, state: ^D3D12_State, pipeline: ^D3D12_Compute_Pipeline) -> bool {
	return d3d12_required_masks_satisfied(ctx, pipeline.required[int(Shader_Stage.Compute)], state.current_bindings[int(Shader_Stage.Compute)], "dispatch")
}

d3d12_required_masks_satisfied :: proc(ctx: ^Context, required, current: D3D12_Binding_Masks, op: string) -> bool {
	for group in 0..<MAX_BINDING_GROUPS {
		if required.uniforms[group] & ~current.uniforms[group] != 0 {
			set_validation_errorf(ctx, "gfx.d3d12: %s is missing required uniforms in group %d", op, group)
			return false
		}
		if required.views[group] & ~current.views[group] != 0 {
			set_validation_errorf(ctx, "gfx.d3d12: %s is missing required resource views in group %d", op, group)
			return false
		}
		if required.samplers[group] & ~current.samplers[group] != 0 {
			set_validation_errorf(ctx, "gfx.d3d12: %s is missing required samplers in group %d", op, group)
			return false
		}
	}
	return true
}

d3d12_sync_graphics_root :: proc(ctx: ^Context, state: ^D3D12_State, pipeline: ^D3D12_Pipeline) -> bool {
	return d3d12_bind_graphics_resource_tables(ctx, state, pipeline, state.current_user_bindings)
}

d3d12_sync_compute_root :: proc(ctx: ^Context, state: ^D3D12_State, pipeline: ^D3D12_Compute_Pipeline) -> bool {
	return d3d12_bind_compute_resource_tables(ctx, state, pipeline, state.current_user_bindings)
}

d3d12_validate_pipeline_pass_compatibility :: proc(ctx: ^Context, state: ^D3D12_State, pipeline: ^D3D12_Pipeline) -> bool {
	if pipeline.depth_only {
		if state.current_pass_has_color {
			set_validation_error(ctx, "gfx.d3d12: depth-only pipeline cannot be used in a color pass")
			return false
		}
	} else if !state.current_pass_has_color {
		set_validation_error(ctx, "gfx.d3d12: color pipeline requires a color attachment")
		return false
	}
	if pipeline.depth_enabled && !state.current_pass_has_depth {
		set_validation_error(ctx, "gfx.d3d12: depth-enabled pipeline requires a depth attachment")
		return false
	}
	for format, slot in pipeline.color_formats {
		if format == .Invalid {
			continue
		}
		if state.current_pass_color_formats[slot] != .Invalid && state.current_pass_color_formats[slot] != format {
			set_validation_errorf(ctx, "gfx.d3d12: pipeline color format at slot %d does not match current pass", slot)
			return false
		}
	}
	if pipeline.depth_enabled && state.current_pass_depth_format != .Invalid && state.current_pass_depth_format != pipeline.depth_format {
		set_validation_error(ctx, "gfx.d3d12: pipeline depth format does not match current pass")
		return false
	}
	return true
}
