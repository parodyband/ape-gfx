package gfx

import "core:fmt"

@(private)
HANDLE_INDEX_BITS :: 24
@(private)
HANDLE_GENERATION_BITS :: 24
@(private)
HANDLE_CONTEXT_BITS :: 16
@(private)
HANDLE_INDEX_MASK :: (u64(1) << HANDLE_INDEX_BITS) - 1
@(private)
HANDLE_GENERATION_MASK :: (u64(1) << HANDLE_GENERATION_BITS) - 1
@(private)
HANDLE_CONTEXT_MASK :: (u64(1) << HANDLE_CONTEXT_BITS) - 1
@(private)
HANDLE_GENERATION_SHIFT :: HANDLE_INDEX_BITS
@(private)
HANDLE_CONTEXT_SHIFT :: HANDLE_INDEX_BITS + HANDLE_GENERATION_BITS
@(private)
HANDLE_MAX_SLOT_INDEX :: u32(HANDLE_INDEX_MASK)
@(private)
HANDLE_MAX_GENERATION :: u32(HANDLE_GENERATION_MASK)
@(private)
HANDLE_MAX_CONTEXT_ID :: u32(HANDLE_CONTEXT_MASK)

@(private)
Resource_Handle_Status :: enum {
	Alive,
	Invalid,
	Wrong_Context,
	Stale,
}

@(private)
global_next_context_id: u32 = 1

// init creates a graphics context for the requested backend and native window.
init :: proc(desc: Desc) -> (Context, bool) {
	ctx := Context {
		desc = desc,
		backend = resolve_backend(desc.backend),
		context_id = allocate_context_id(),
	}

	if ctx.context_id == 0 {
		set_validation_error(&ctx, "gfx.init: exhausted context ids")
		return ctx, false
	}

	if desc.width < 0 || desc.height < 0 {
		set_validation_error(&ctx, "gfx.init: width and height must be non-negative")
		return ctx, false
	}

	if !backend_init(&ctx) {
		if ctx.last_error == "" {
			set_validation_error(&ctx, "gfx.init: backend initialization failed")
		}
		return ctx, false
	}

	ctx.initialized = true
	return ctx, true
}

// shutdown releases backend state and reports leaked resources through last_error.
shutdown :: proc(ctx: ^Context) {
	if ctx == nil || !ctx.initialized {
		return
	}

	if ctx.in_pass {
		if ctx.pass_kind == .Compute {
			end_compute_pass(ctx)
		} else {
			end_pass(ctx)
		}
	}

	if resource_pool_live_total(ctx) > 0 {
		set_errorf_code(
			ctx,
			.Resource_Leak,
			"gfx.shutdown: leaked resources: buffers=%d images=%d views=%d samplers=%d shaders=%d pipelines=%d compute_pipelines=%d",
			ctx.buffer_pool.live_count,
			ctx.image_pool.live_count,
			ctx.view_pool.live_count,
			ctx.sampler_pool.live_count,
			ctx.shader_pool.live_count,
			ctx.pipeline_pool.live_count,
			ctx.compute_pipeline_pool.live_count,
		)
	}

	backend_shutdown(ctx)
	delete_resource_pools(ctx)
	ctx.initialized = false
}

// create_buffer creates a GPU buffer and reports whether creation succeeded.
// On failure, the returned handle is Buffer_Invalid and last_error explains why.
create_buffer :: proc(ctx: ^Context, desc: Buffer_Desc) -> (Buffer, bool) {
	if !require_initialized(ctx, "gfx.create_buffer") {
		return Buffer_Invalid, false
	}

	desc := desc
	if !validate_buffer_desc(ctx, &desc) {
		return Buffer_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.buffer_pool, "gfx.create_buffer")
	if handle_id == 0 {
		return Buffer_Invalid, false
	}

	handle := Buffer(handle_id)
	if !backend_create_buffer(ctx, handle, desc) {
		cancel_resource_id(&ctx.buffer_pool, handle_id)
		return Buffer_Invalid, false
	}

	return handle, true
}

// destroy_buffer releases a live buffer handle.
destroy_buffer :: proc(ctx: ^Context, buffer: Buffer) {
	if !require_initialized(ctx, "gfx.destroy_buffer") {
		return
	}
	if !require_resource(ctx, &ctx.buffer_pool, u64(buffer), "gfx.destroy_buffer", "buffer") {
		return
	}

	backend_destroy_buffer(ctx, buffer)
	release_resource_id(&ctx.buffer_pool, u64(buffer))
}

// update_buffer writes CPU data into a Dynamic_Update or Stream_Update buffer.
update_buffer :: proc(ctx: ^Context, desc: Buffer_Update_Desc) -> bool {
	buffer_state, ok := validate_buffer_transfer(ctx, "gfx.update_buffer", desc.buffer, desc.offset, desc.data)
	if !ok {
		return false
	}

	if !(.Dynamic_Update in buffer_state.usage) && !(.Stream_Update in buffer_state.usage) {
		set_validation_error(ctx, "gfx.update_buffer: buffer must use Dynamic_Update or Stream_Update")
		return false
	}

	return backend_update_buffer(ctx, desc)
}

// read_buffer synchronously copies GPU buffer data into CPU memory.
read_buffer :: proc(ctx: ^Context, desc: Buffer_Read_Desc) -> bool {
	_, ok := validate_buffer_transfer(ctx, "gfx.read_buffer", desc.buffer, desc.offset, desc.data)
	if !ok {
		return false
	}

	return backend_read_buffer(ctx, desc)
}

// create_image creates a texture, storage image, or attachment image.
// On failure, the returned handle is Image_Invalid and last_error explains why.
create_image :: proc(ctx: ^Context, desc: Image_Desc) -> (Image, bool) {
	if !require_initialized(ctx, "gfx.create_image") {
		return Image_Invalid, false
	}

	if desc.width <= 0 || desc.height <= 0 {
		set_validation_error(ctx, "gfx.create_image: width and height must be positive")
		return Image_Invalid, false
	}

	if !validate_image_desc(ctx, desc) {
		return Image_Invalid, false
	}

	array_count := image_desc_array_count(desc)
	sample_count := image_desc_sample_count(desc)
	limits := backend_query_limits(ctx)
	if limits.max_image_dimension_2d > 0 {
		if int(desc.width) > limits.max_image_dimension_2d {
			set_validation_errorf(ctx, "gfx.create_image: width exceeds backend 2D image dimension limit (%d)", limits.max_image_dimension_2d)
			return Image_Invalid, false
		}
		if int(desc.height) > limits.max_image_dimension_2d {
			set_validation_errorf(ctx, "gfx.create_image: height exceeds backend 2D image dimension limit (%d)", limits.max_image_dimension_2d)
			return Image_Invalid, false
		}
	}
	if limits.max_image_array_layers > 0 && int(array_count) > limits.max_image_array_layers {
		set_validation_errorf(ctx, "gfx.create_image: array_count exceeds backend image array layer limit (%d)", limits.max_image_array_layers)
		return Image_Invalid, false
	}
	if limits.max_image_sample_count > 0 && int(sample_count) > limits.max_image_sample_count {
		set_validation_errorf(ctx, "gfx.create_image: sample_count exceeds backend sample count limit (%d)", limits.max_image_sample_count)
		return Image_Invalid, false
	}

	if sample_count > 1 {
		features := backend_query_features(ctx)
		if !features.msaa_render_targets {
			set_unsupported_error(ctx, "gfx.create_image: backend does not support multisampled render targets")
			return Image_Invalid, false
		}
		if image_desc_mip_count(desc) > 1 {
			set_validation_error(ctx, "gfx.create_image: multisampled images cannot have mipmaps")
			return Image_Invalid, false
		}
		if .Texture in desc.usage {
			set_validation_error(ctx, "gfx.create_image: multisampled images cannot use Texture usage yet; resolve into a single-sampled texture")
			return Image_Invalid, false
		}
		if .Storage_Image in desc.usage {
			set_unsupported_error(ctx, "gfx.create_image: multisampled storage images are not supported")
			return Image_Invalid, false
		}
		if !(.Color_Attachment in desc.usage) && !(.Depth_Stencil_Attachment in desc.usage) {
			set_validation_error(ctx, "gfx.create_image: multisampled images must be render attachments")
			return Image_Invalid, false
		}
	}

	handle_id := alloc_resource_id(ctx, &ctx.image_pool, "gfx.create_image")
	if handle_id == 0 {
		return Image_Invalid, false
	}

	handle := Image(handle_id)
	if !backend_create_image(ctx, handle, desc) {
		cancel_resource_id(&ctx.image_pool, handle_id)
		return Image_Invalid, false
	}

	return handle, true
}

// destroy_image releases a live image handle.
destroy_image :: proc(ctx: ^Context, image: Image) {
	if !require_initialized(ctx, "gfx.destroy_image") {
		return
	}
	if !require_resource(ctx, &ctx.image_pool, u64(image), "gfx.destroy_image", "image") {
		return
	}

	backend_destroy_image(ctx, image)
	release_resource_id(&ctx.image_pool, u64(image))
}

// update_image writes CPU data into a dynamic image subregion.
update_image :: proc(ctx: ^Context, desc: Image_Update_Desc) -> bool {
	if !require_initialized(ctx, "gfx.update_image") {
		return false
	}

	if ctx.in_pass {
		set_validation_error(ctx, "gfx.update_image: cannot update an image while a pass is in progress")
		return false
	}

	if !require_resource(ctx, &ctx.image_pool, u64(desc.image), "gfx.update_image", "image") {
		return false
	}

	if !validate_image_update_desc(ctx, desc) {
		return false
	}

	return backend_update_image(ctx, desc)
}

// resolve_image resolves a multisampled color image into a single-sampled image.
resolve_image :: proc(ctx: ^Context, desc: Image_Resolve_Desc) -> bool {
	if !require_initialized(ctx, "gfx.resolve_image") {
		return false
	}

	if ctx.in_pass {
		set_validation_error(ctx, "gfx.resolve_image: cannot resolve an image while a pass is in progress")
		return false
	}

	if !require_resource(ctx, &ctx.image_pool, u64(desc.source), "gfx.resolve_image", "source image") {
		return false
	}
	if !require_resource(ctx, &ctx.image_pool, u64(desc.destination), "gfx.resolve_image", "destination image") {
		return false
	}

	if !validate_image_resolve_desc(ctx, desc) {
		return false
	}

	return backend_resolve_image(ctx, desc)
}

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

	backend_destroy_view(ctx, view)
	release_resource_id(&ctx.view_pool, u64(view))
}

// create_sampler creates immutable texture sampling state.
// On failure, the returned handle is Sampler_Invalid and last_error explains why.
create_sampler :: proc(ctx: ^Context, desc: Sampler_Desc) -> (Sampler, bool) {
	if !require_initialized(ctx, "gfx.create_sampler") {
		return Sampler_Invalid, false
	}

	if !validate_sampler_desc(ctx, desc) {
		return Sampler_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.sampler_pool, "gfx.create_sampler")
	if handle_id == 0 {
		return Sampler_Invalid, false
	}

	handle := Sampler(handle_id)
	if !backend_create_sampler(ctx, handle, desc) {
		cancel_resource_id(&ctx.sampler_pool, handle_id)
		return Sampler_Invalid, false
	}

	return handle, true
}

// destroy_sampler releases a live sampler handle.
destroy_sampler :: proc(ctx: ^Context, sampler: Sampler) {
	if !require_initialized(ctx, "gfx.destroy_sampler") {
		return
	}
	if !require_resource(ctx, &ctx.sampler_pool, u64(sampler), "gfx.destroy_sampler", "sampler") {
		return
	}

	backend_destroy_sampler(ctx, sampler)
	release_resource_id(&ctx.sampler_pool, u64(sampler))
}

// create_shader creates backend shader objects from compiled shader bytecode.
// On failure, the returned handle is Shader_Invalid and last_error explains why.
create_shader :: proc(ctx: ^Context, desc: Shader_Desc) -> (Shader, bool) {
	if !require_initialized(ctx, "gfx.create_shader") {
		return Shader_Invalid, false
	}

	if !validate_shader_desc(ctx, desc) {
		return Shader_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.shader_pool, "gfx.create_shader")
	if handle_id == 0 {
		return Shader_Invalid, false
	}

	handle := Shader(handle_id)
	if !backend_create_shader(ctx, handle, desc) {
		cancel_resource_id(&ctx.shader_pool, handle_id)
		return Shader_Invalid, false
	}

	track_shader_state(ctx, handle, desc)
	return handle, true
}

// destroy_shader releases a live shader handle.
destroy_shader :: proc(ctx: ^Context, shader: Shader) {
	if !require_initialized(ctx, "gfx.destroy_shader") {
		return
	}
	if !require_resource(ctx, &ctx.shader_pool, u64(shader), "gfx.destroy_shader", "shader") {
		return
	}

	backend_destroy_shader(ctx, shader)
	untrack_shader_state(ctx, shader)
	release_resource_id(&ctx.shader_pool, u64(shader))
}

// create_pipeline creates an immutable graphics pipeline state object.
// On failure, the returned handle is Pipeline_Invalid and last_error explains why.
create_pipeline :: proc(ctx: ^Context, desc: Pipeline_Desc) -> (Pipeline, bool) {
	if !require_initialized(ctx, "gfx.create_pipeline") {
		return Pipeline_Invalid, false
	}

	if !require_resource(ctx, &ctx.shader_pool, u64(desc.shader), "gfx.create_pipeline", "shader") {
		return Pipeline_Invalid, false
	}

	if !validate_pipeline_desc(ctx, desc) {
		return Pipeline_Invalid, false
	}
	if !validate_graphics_pipeline_shader(ctx, desc) {
		return Pipeline_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.pipeline_pool, "gfx.create_pipeline")
	if handle_id == 0 {
		return Pipeline_Invalid, false
	}

	handle := Pipeline(handle_id)
	if !backend_create_pipeline(ctx, handle, desc) {
		cancel_resource_id(&ctx.pipeline_pool, handle_id)
		return Pipeline_Invalid, false
	}

	return handle, true
}

// destroy_pipeline releases a live graphics pipeline handle.
destroy_pipeline :: proc(ctx: ^Context, pipeline: Pipeline) {
	if !require_initialized(ctx, "gfx.destroy_pipeline") {
		return
	}
	if !require_resource(ctx, &ctx.pipeline_pool, u64(pipeline), "gfx.destroy_pipeline", "pipeline") {
		return
	}

	backend_destroy_pipeline(ctx, pipeline)
	release_resource_id(&ctx.pipeline_pool, u64(pipeline))
}

// create_compute_pipeline creates an immutable compute pipeline state object.
// On failure, the returned handle is Compute_Pipeline_Invalid and last_error explains why.
create_compute_pipeline :: proc(ctx: ^Context, desc: Compute_Pipeline_Desc) -> (Compute_Pipeline, bool) {
	if !require_initialized(ctx, "gfx.create_compute_pipeline") {
		return Compute_Pipeline_Invalid, false
	}

	if !require_resource(ctx, &ctx.shader_pool, u64(desc.shader), "gfx.create_compute_pipeline", "shader") {
		return Compute_Pipeline_Invalid, false
	}

	if !validate_compute_pipeline_desc(ctx, desc) {
		return Compute_Pipeline_Invalid, false
	}

	features := backend_query_features(ctx)
	if !features.compute {
		set_unsupported_error(ctx, "gfx.create_compute_pipeline: backend does not support compute")
		return Compute_Pipeline_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.compute_pipeline_pool, "gfx.create_compute_pipeline")
	if handle_id == 0 {
		return Compute_Pipeline_Invalid, false
	}

	handle := Compute_Pipeline(handle_id)
	if !backend_create_compute_pipeline(ctx, handle, desc) {
		cancel_resource_id(&ctx.compute_pipeline_pool, handle_id)
		return Compute_Pipeline_Invalid, false
	}

	return handle, true
}

// destroy_compute_pipeline releases a live compute pipeline handle.
destroy_compute_pipeline :: proc(ctx: ^Context, pipeline: Compute_Pipeline) {
	if !require_initialized(ctx, "gfx.destroy_compute_pipeline") {
		return
	}
	if !require_resource(ctx, &ctx.compute_pipeline_pool, u64(pipeline), "gfx.destroy_compute_pipeline", "compute pipeline") {
		return
	}

	backend_destroy_compute_pipeline(ctx, pipeline)
	release_resource_id(&ctx.compute_pipeline_pool, u64(pipeline))
}

// resize recreates swapchain-dependent backend resources after a window resize.
resize :: proc(ctx: ^Context, width, height: i32) -> bool {
	if !require_initialized(ctx, "gfx.resize") {
		return false
	}

	if ctx.in_pass {
		set_validation_error(ctx, "gfx.resize: cannot resize while a pass is in progress")
		return false
	}

	if width <= 0 || height <= 0 {
		set_validation_error(ctx, "gfx.resize: width and height must be positive")
		return false
	}

	if ctx.desc.width == width && ctx.desc.height == height {
		return true
	}

	if !backend_resize(ctx, width, height) {
		return false
	}

	ctx.desc.width = width
	ctx.desc.height = height
	return true
}

// query_buffer_state returns read-only state for a live buffer, or zero if invalid.
query_buffer_state :: proc(ctx: ^Context, buffer: Buffer) -> Buffer_State {
	if ctx == nil || !ctx.initialized || !resource_id_alive(ctx, &ctx.buffer_pool, u64(buffer)) {
		return {}
	}

	return backend_query_buffer_state(ctx, buffer)
}

// query_image_state returns read-only state for a live image, or zero if invalid.
query_image_state :: proc(ctx: ^Context, image: Image) -> Image_State {
	if ctx == nil || !ctx.initialized || !resource_id_alive(ctx, &ctx.image_pool, u64(image)) {
		return {}
	}

	return backend_query_image_state(ctx, image)
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

// query_features returns optional features supported by the active backend.
query_features :: proc(ctx: ^Context) -> Features {
	if ctx == nil || !ctx.initialized {
		return {}
	}

	return backend_query_features(ctx)
}

@(private)
api_limits :: proc() -> Limits {
	return {
		max_vertex_buffers = MAX_VERTEX_BUFFERS,
		max_vertex_attributes = MAX_VERTEX_ATTRIBUTES,
		max_color_attachments = MAX_COLOR_ATTACHMENTS,
		max_resource_views = MAX_RESOURCE_VIEWS,
		max_samplers = MAX_SAMPLERS,
		max_uniform_blocks = MAX_UNIFORM_BLOCKS,
		max_shader_bindings = MAX_SHADER_BINDINGS,
		max_image_mips = MAX_IMAGE_MIPS,
	}
}

// query_limits returns backend-independent public API limits.
query_limits :: proc() -> Limits {
	return api_limits()
}

// query_backend_limits returns concrete limits reported by the active backend.
query_backend_limits :: proc(ctx: ^Context) -> Limits {
	if ctx == nil || !ctx.initialized {
		return {}
	}

	return backend_query_limits(ctx)
}

@(private)
validate_buffer_desc :: proc(ctx: ^Context, desc: ^Buffer_Desc) -> bool {
	if desc == nil {
		set_validation_error(ctx, "gfx.create_buffer: descriptor is nil")
		return false
	}

	if !validate_optional_range(ctx, "gfx.create_buffer", "data", desc.data) {
		return false
	}

	if desc.size == 0 && desc.data.size > 0 {
		desc.size = desc.data.size
	}
	if desc.size <= 0 {
		set_validation_error(ctx, "gfx.create_buffer: size must be positive or inferred from initial data")
		return false
	}
	if range_has_data(desc.data) && desc.data.size < desc.size {
		set_validation_error(ctx, "gfx.create_buffer: initial data range must cover Buffer_Desc.size")
		return false
	}

	role_count := buffer_usage_role_count(desc.usage)
	if role_count == 0 {
		set_validation_error(ctx, "gfx.create_buffer: usage must include at least one role flag")
		return false
	}

	update_count := buffer_usage_update_count(desc.usage)
	if update_count == 0 && !(.Storage in desc.usage) {
		set_validation_error(ctx, "gfx.create_buffer: usage must include Immutable, Dynamic_Update, or Stream_Update")
		return false
	}
	if update_count > 1 {
		set_validation_error(ctx, "gfx.create_buffer: usage has conflicting update/lifetime flags")
		return false
	}
	if .Storage in desc.usage && update_count > 0 {
		set_validation_error(ctx, "gfx.create_buffer: storage buffers are GPU-only for now and must not use update/lifetime flags")
		return false
	}
	if .Immutable in desc.usage && !range_has_data(desc.data) {
		set_validation_error(ctx, "gfx.create_buffer: immutable buffers require initial data")
		return false
	}

	if desc.storage_stride < 0 {
		set_validation_error(ctx, "gfx.create_buffer: storage_stride must be non-negative")
		return false
	}
	if desc.storage_stride > 0 {
		if !(.Storage in desc.usage) {
			set_validation_error(ctx, "gfx.create_buffer: storage_stride requires Storage usage")
			return false
		}
		if desc.storage_stride % 4 != 0 {
			set_validation_error(ctx, "gfx.create_buffer: storage_stride must be 4-byte aligned")
			return false
		}
		if desc.size % desc.storage_stride != 0 {
			set_validation_error(ctx, "gfx.create_buffer: structured storage buffer size must be a multiple of storage_stride")
			return false
		}
	} else if .Storage in desc.usage && desc.size % 4 != 0 {
		set_validation_error(ctx, "gfx.create_buffer: raw storage buffer size must be 4-byte aligned")
		return false
	}

	return true
}

@(private)
buffer_usage_role_count :: proc(usage: Buffer_Usage) -> int {
	count := 0
	if .Vertex in usage {
		count += 1
	}
	if .Index in usage {
		count += 1
	}
	if .Uniform in usage {
		count += 1
	}
	if .Storage in usage {
		count += 1
	}
	return count
}

@(private)
buffer_usage_update_count :: proc(usage: Buffer_Usage) -> int {
	count := 0
	if .Immutable in usage {
		count += 1
	}
	if .Dynamic_Update in usage {
		count += 1
	}
	if .Stream_Update in usage {
		count += 1
	}
	return count
}

@(private)
validate_sampler_desc :: proc(ctx: ^Context, desc: Sampler_Desc) -> bool {
	if !filter_valid(desc.min_filter) {
		set_validation_error(ctx, "gfx.create_sampler: min_filter is invalid")
		return false
	}
	if !filter_valid(desc.mag_filter) {
		set_validation_error(ctx, "gfx.create_sampler: mag_filter is invalid")
		return false
	}
	if !filter_valid(desc.mip_filter) {
		set_validation_error(ctx, "gfx.create_sampler: mip_filter is invalid")
		return false
	}
	if !wrap_valid(desc.wrap_u) {
		set_validation_error(ctx, "gfx.create_sampler: wrap_u is invalid")
		return false
	}
	if !wrap_valid(desc.wrap_v) {
		set_validation_error(ctx, "gfx.create_sampler: wrap_v is invalid")
		return false
	}
	if !wrap_valid(desc.wrap_w) {
		set_validation_error(ctx, "gfx.create_sampler: wrap_w is invalid")
		return false
	}

	return true
}

@(private)
validate_shader_desc :: proc(ctx: ^Context, desc: Shader_Desc) -> bool {
	stage_seen: [3]bool
	has_stage := false

	for stage_desc, stage_index in desc.stages {
		if !range_has_data(stage_desc.bytecode) {
			continue
		}
		if !validate_optional_range(ctx, "gfx.create_shader", "stage bytecode", stage_desc.bytecode) {
			return false
		}
		if !shader_stage_valid(stage_desc.stage) {
			set_validation_errorf(ctx, "gfx.create_shader: stage descriptor %d has an invalid stage", stage_index)
			return false
		}

		stage := int(stage_desc.stage)
		if stage_seen[stage] {
			set_validation_errorf(ctx, "gfx.create_shader: duplicate %s stage bytecode", shader_stage_name(stage_desc.stage))
			return false
		}

		stage_seen[stage] = true
		has_stage = true
	}

	if !has_stage {
		set_validation_error(ctx, "gfx.create_shader: at least one stage bytecode range is required")
		return false
	}

	has_vertex := stage_seen[int(Shader_Stage.Vertex)]
	has_fragment := stage_seen[int(Shader_Stage.Fragment)]
	has_compute := stage_seen[int(Shader_Stage.Compute)]
	if has_compute && (has_vertex || has_fragment) {
		set_validation_error(ctx, "gfx.create_shader: compute stages cannot be combined with graphics stages")
		return false
	}
	if !has_compute && (!has_vertex || !has_fragment) {
		set_validation_error(ctx, "gfx.create_shader: graphics shaders require both vertex and fragment stages")
		return false
	}

	if !validate_shader_binding_metadata(ctx, desc, stage_seen) {
		return false
	}
	if !validate_shader_vertex_input_metadata(ctx, desc, has_vertex) {
		return false
	}

	return true
}

@(private)
validate_shader_binding_metadata :: proc(ctx: ^Context, desc: Shader_Desc, stage_seen: [3]bool) -> bool {
	for binding, index in desc.bindings {
		if !binding.active {
			continue
		}
		if !desc.has_binding_metadata {
			set_validation_errorf(ctx, "gfx.create_shader: active binding metadata at index %d requires has_binding_metadata", index)
			return false
		}
		if !validate_shader_binding_desc(ctx, binding, index, stage_seen) {
			return false
		}

		for other, other_index in desc.bindings {
			if other_index >= index || !other.active {
				continue
			}
			if other.stage == binding.stage && other.kind == binding.kind && other.slot == binding.slot {
				set_validation_errorf(
					ctx,
					"gfx.create_shader: duplicate %s binding metadata for %s slot %d",
					shader_binding_kind_name(binding.kind),
					shader_stage_name(binding.stage),
					binding.slot,
				)
				return false
			}
		}
	}

	return true
}

@(private)
validate_shader_binding_desc :: proc(ctx: ^Context, binding: Shader_Binding_Desc, index: int, stage_seen: [3]bool) -> bool {
	if !shader_stage_valid(binding.stage) {
		set_validation_errorf(ctx, "gfx.create_shader: binding metadata index %d has an invalid stage", index)
		return false
	}
	if !stage_seen[int(binding.stage)] {
		set_validation_errorf(
			ctx,
			"gfx.create_shader: binding metadata index %d references missing %s stage",
			index,
			shader_stage_name(binding.stage),
		)
		return false
	}
	if !shader_binding_kind_valid(binding.kind) {
		set_validation_errorf(ctx, "gfx.create_shader: binding metadata index %d has an invalid kind", index)
		return false
	}

	switch binding.kind {
	case .Uniform_Block:
		if binding.slot >= MAX_UNIFORM_BLOCKS {
			set_validation_errorf(ctx, "gfx.create_shader: uniform binding slot %d is out of range", binding.slot)
			return false
		}
		if binding.native_slot >= MAX_UNIFORM_BLOCKS {
			set_validation_errorf(ctx, "gfx.create_shader: native uniform binding slot %d is out of range", binding.native_slot)
			return false
		}
		if binding.size == 0 {
			set_validation_errorf(ctx, "gfx.create_shader: uniform binding metadata index %d requires nonzero size", index)
			return false
		}
	case .Resource_View:
		if binding.slot >= MAX_RESOURCE_VIEWS {
			set_validation_errorf(ctx, "gfx.create_shader: resource view binding slot %d is out of range", binding.slot)
			return false
		}
		if binding.native_slot >= MAX_RESOURCE_VIEWS {
			set_validation_errorf(ctx, "gfx.create_shader: native resource view binding slot %d is out of range", binding.native_slot)
			return false
		}
		if !shader_resource_view_kind_valid(binding.view_kind) {
			set_validation_errorf(ctx, "gfx.create_shader: resource view binding metadata index %d has an invalid view kind", index)
			return false
		}
		if !shader_resource_access_valid(binding.access) {
			set_validation_errorf(ctx, "gfx.create_shader: resource view binding metadata index %d has an invalid access", index)
			return false
		}
		if binding.view_kind == .Storage_Image {
			if !shader_storage_image_format_valid(binding.storage_image_format) {
				set_validation_errorf(ctx, "gfx.create_shader: storage image binding metadata index %d has an unsupported format", index)
				return false
			}
		} else if binding.storage_image_format != .Invalid {
			set_validation_errorf(
				ctx,
				"gfx.create_shader: non-storage-image binding metadata index %d must not declare a storage image format",
				index,
			)
			return false
		}
		if binding.view_kind == .Storage_Buffer {
			if binding.storage_buffer_stride != 0 && binding.storage_buffer_stride % 4 != 0 {
				set_validation_errorf(ctx, "gfx.create_shader: storage buffer binding metadata index %d stride must be 4-byte aligned", index)
				return false
			}
		} else if binding.storage_buffer_stride != 0 {
			set_validation_errorf(
				ctx,
				"gfx.create_shader: non-storage-buffer binding metadata index %d must not declare a storage buffer stride",
				index,
			)
			return false
		}
	case .Sampler:
		if binding.slot >= MAX_SAMPLERS {
			set_validation_errorf(ctx, "gfx.create_shader: sampler binding slot %d is out of range", binding.slot)
			return false
		}
		if binding.native_slot >= MAX_SAMPLERS {
			set_validation_errorf(ctx, "gfx.create_shader: native sampler binding slot %d is out of range", binding.native_slot)
			return false
		}
	}

	return true
}

@(private)
validate_shader_vertex_input_metadata :: proc(ctx: ^Context, desc: Shader_Desc, has_vertex: bool) -> bool {
	for input, index in desc.vertex_inputs {
		if !input.active {
			continue
		}
		if !desc.has_vertex_input_metadata {
			set_validation_errorf(ctx, "gfx.create_shader: active vertex input metadata at index %d requires has_vertex_input_metadata", index)
			return false
		}
		if !has_vertex {
			set_validation_errorf(ctx, "gfx.create_shader: vertex input metadata index %d requires a vertex stage", index)
			return false
		}
		if input.semantic == "" {
			set_validation_errorf(ctx, "gfx.create_shader: vertex input metadata index %d requires a semantic", index)
			return false
		}
		if !vertex_format_valid(input.format) {
			set_validation_errorf(ctx, "gfx.create_shader: vertex input metadata index %d has an invalid format", index)
			return false
		}

		for other, other_index in desc.vertex_inputs {
			if other_index >= index || !other.active {
				continue
			}
			if other.semantic == input.semantic && other.semantic_index == input.semantic_index {
				set_validation_errorf(ctx, "gfx.create_shader: duplicate vertex input metadata for %s%d", input.semantic, input.semantic_index)
				return false
			}
		}
	}

	return true
}

@(private)
track_shader_state :: proc(ctx: ^Context, shader: Shader, desc: Shader_Desc) {
	if ctx == nil || !shader_valid(shader) {
		return
	}
	if ctx.shader_states == nil {
		ctx.shader_states = make(map[Shader]Shader_State)
	}

	ctx.shader_states[shader] = shader_state_from_desc(desc)
}

@(private)
untrack_shader_state :: proc(ctx: ^Context, shader: Shader) {
	if ctx == nil || ctx.shader_states == nil {
		return
	}

	delete_key(&ctx.shader_states, shader)
}

@(private)
query_shader_state :: proc(ctx: ^Context, shader: Shader) -> (Shader_State, bool) {
	if ctx == nil || ctx.shader_states == nil {
		return {}, false
	}

	state, ok := ctx.shader_states[shader]
	return state, ok && state.valid
}

@(private)
shader_state_from_desc :: proc(desc: Shader_Desc) -> Shader_State {
	state := Shader_State {
		valid = true,
		has_binding_metadata = desc.has_binding_metadata,
		has_vertex_input_metadata = desc.has_vertex_input_metadata,
	}

	for stage_desc in desc.stages {
		if !range_has_data(stage_desc.bytecode) {
			continue
		}

		switch stage_desc.stage {
		case .Vertex:
			state.has_vertex = true
		case .Fragment:
			state.has_fragment = true
		case .Compute:
			state.has_compute = true
		}
	}

	for input, index in desc.vertex_inputs {
		state.vertex_inputs[index] = input
	}

	return state
}

@(private)
validate_image_desc :: proc(ctx: ^Context, desc: Image_Desc) -> bool {
	if desc.kind != .Image_2D {
		set_unsupported_error(ctx, "gfx.create_image: only Image_2D is supported for now")
		return false
	}
	if desc.depth < 0 {
		set_validation_error(ctx, "gfx.create_image: depth must be non-negative")
		return false
	}
	if desc.depth > 1 {
		set_unsupported_error(ctx, "gfx.create_image: Image_2D depth must be 1 when specified")
		return false
	}
	if desc.format == .Invalid {
		set_validation_error(ctx, "gfx.create_image: format must be valid")
		return false
	}
	if pixel_format_size(desc.format) == 0 {
		set_unsupported_error(ctx, "gfx.create_image: unsupported image format")
		return false
	}
	if desc.mip_count < 0 {
		set_validation_error(ctx, "gfx.create_image: mip_count must be positive when specified")
		return false
	}
	if image_desc_mip_count(desc) > MAX_IMAGE_MIPS {
		set_validation_errorf(ctx, "gfx.create_image: mip_count exceeds public image mip limit (%d)", MAX_IMAGE_MIPS)
		return false
	}
	if desc.array_count < 0 {
		set_validation_error(ctx, "gfx.create_image: array_count must be positive when specified")
		return false
	}
	if desc.sample_count < 0 {
		set_validation_error(ctx, "gfx.create_image: sample_count must be positive when specified")
		return false
	}
	if !validate_image_usage(ctx, desc.usage) {
		return false
	}

	has_depth := .Depth_Stencil_Attachment in desc.usage
	has_storage := .Storage_Image in desc.usage
	has_color := .Color_Attachment in desc.usage
	has_dynamic := image_usage_has_dynamic_update(desc.usage)
	has_immutable := .Immutable in desc.usage
	has_mip_data := image_desc_has_mip_data(desc)
	if has_depth && !pixel_format_is_depth(desc.format) {
		set_validation_error(ctx, "gfx.create_image: depth-stencil images require a depth format")
		return false
	}
	if !has_depth && !pixel_format_is_color(desc.format) {
		set_validation_error(ctx, "gfx.create_image: color images require a color format")
		return false
	}

	if !validate_optional_range(ctx, "gfx.create_image", "data", desc.data) {
		return false
	}
	for mip_data, mip in desc.mips {
		if mip_data.row_pitch < 0 {
			set_validation_errorf(ctx, "gfx.create_image: mip %d row_pitch must be non-negative", mip)
			return false
		}
		if mip_data.slice_pitch < 0 {
			set_validation_errorf(ctx, "gfx.create_image: mip %d slice_pitch must be non-negative", mip)
			return false
		}
		if !validate_optional_range(ctx, "gfx.create_image", "mip data", mip_data.data) {
			return false
		}
		if range_has_data(mip_data.data) && mip >= int(image_desc_mip_count(desc)) {
			set_validation_errorf(ctx, "gfx.create_image: mip data specified beyond mip_count at mip %d", mip)
			return false
		}
	}

	mip_count := image_desc_mip_count(desc)
	if mip_count > 1 && !has_dynamic && !(has_immutable && has_mip_data) {
		set_validation_error(ctx, "gfx.create_image: immutable mip chains require explicit mip data")
		return false
	}
	if has_dynamic && range_has_data(desc.data) && mip_count != 1 {
		set_validation_error(ctx, "gfx.create_image: initial dynamic image data only supports one mip level; use update_image for mip chains")
		return false
	}
	if has_dynamic && has_mip_data {
		set_validation_error(ctx, "gfx.create_image: dynamic images do not accept initial mip-chain data; use update_image")
		return false
	}
	if has_color && (range_has_data(desc.data) || has_mip_data) {
		set_validation_error(ctx, "gfx.create_image: color attachment images do not accept initial pixel data yet")
		return false
	}
	if has_storage && (range_has_data(desc.data) || has_mip_data) {
		set_validation_error(ctx, "gfx.create_image: storage images do not accept initial pixel data yet")
		return false
	}
	if has_depth && (range_has_data(desc.data) || has_mip_data) {
		set_validation_error(ctx, "gfx.create_image: depth-stencil images do not accept initial data yet")
		return false
	}
	if has_immutable && !validate_initial_image_data(ctx, desc, mip_count, pixel_format_size(desc.format)) {
		return false
	}
	if has_dynamic && range_has_data(desc.data) {
		if !validate_image_data_range(
			ctx,
			"gfx.create_image",
			"dynamic image initial",
			Image_Subresource_Data{data = desc.data},
			u32(desc.width),
			u32(desc.height),
			pixel_format_size(desc.format),
			"requires pixel data",
		) {
			return false
		}
	}

	return true
}

@(private)
validate_image_usage :: proc(ctx: ^Context, usage: Image_Usage) -> bool {
	if usage == {} {
		set_validation_error(ctx, "gfx.create_image: usage must not be empty")
		return false
	}

	has_texture := .Texture in usage
	has_storage := .Storage_Image in usage
	has_color := .Color_Attachment in usage
	has_depth := .Depth_Stencil_Attachment in usage
	has_immutable := .Immutable in usage
	has_dynamic := image_usage_has_dynamic_update(usage)

	if !has_texture && !has_storage && !has_color && !has_depth {
		set_validation_error(ctx, "gfx.create_image: usage must include Texture, Storage_Image, Color_Attachment, or Depth_Stencil_Attachment")
		return false
	}
	if has_color && has_depth {
		set_validation_error(ctx, "gfx.create_image: usage cannot combine color and depth-stencil attachments")
		return false
	}
	if has_storage && has_depth {
		set_validation_error(ctx, "gfx.create_image: storage images cannot use depth-stencil formats")
		return false
	}
	if has_immutable && (has_storage || has_color || has_depth || has_dynamic) {
		set_validation_error(ctx, "gfx.create_image: immutable images must be texture-only for now")
		return false
	}
	if has_dynamic && !has_texture {
		set_validation_error(ctx, "gfx.create_image: dynamic image updates require Texture usage")
		return false
	}
	if has_dynamic && (has_storage || has_color || has_depth) {
		set_unsupported_error(ctx, "gfx.create_image: dynamic storage or attachment images are not implemented yet")
		return false
	}
	if .Dynamic_Update in usage && .Stream_Update in usage {
		set_validation_error(ctx, "gfx.create_image: usage has conflicting update flags")
		return false
	}

	return true
}

@(private)
validate_initial_image_data :: proc(ctx: ^Context, desc: Image_Desc, mip_count: i32, pixel_size: int) -> bool {
	for mip in 0..<int(mip_count) {
		mip_data := image_mip_data(desc, mip)
		if !range_has_data(mip_data.data) {
			set_validation_errorf(ctx, "gfx.create_image: immutable image mip %d requires initial pixel data", mip)
			return false
		}

		mip_width := mip_dimension(u32(desc.width), u32(mip))
		mip_height := mip_dimension(u32(desc.height), u32(mip))
		row_pitch := image_mip_row_pitch(mip_data, mip_width, pixel_size)
		min_row_pitch := mip_width * u32(pixel_size)
		if row_pitch < min_row_pitch {
			set_validation_errorf(ctx, "gfx.create_image: immutable image mip %d row pitch is too small", mip)
			return false
		}

		required_size := int(row_pitch) * int(mip_height - 1) + int(min_row_pitch)
		if mip_data.slice_pitch > 0 && int(mip_data.slice_pitch) < required_size {
			set_validation_errorf(ctx, "gfx.create_image: immutable image mip %d slice pitch is too small", mip)
			return false
		}
		if mip_data.data.size < required_size {
			set_validation_errorf(ctx, "gfx.create_image: immutable image mip %d data range is too small", mip)
			return false
		}
	}

	return true
}

@(private)
validate_image_update_desc :: proc(ctx: ^Context, desc: Image_Update_Desc) -> bool {
	image_state := query_image_state(ctx, desc.image)
	if !image_state.valid {
		set_invalid_handle_error(ctx, "gfx.update_image: image handle is invalid")
		return false
	}
	if !image_usage_has_dynamic_update(image_state.usage) {
		set_validation_error(ctx, "gfx.update_image: image must use Dynamic_Update or Stream_Update")
		return false
	}
	if image_state.kind != .Image_2D {
		set_unsupported_error(ctx, "gfx.update_image: only Image_2D updates are supported")
		return false
	}
	if image_state.sample_count > 1 {
		set_validation_error(ctx, "gfx.update_image: multisampled images cannot be updated")
		return false
	}
	if !pixel_format_is_color(image_state.format) {
		set_validation_error(ctx, "gfx.update_image: only color images can be updated")
		return false
	}
	if desc.mip_level < 0 || desc.array_layer < 0 {
		set_validation_error(ctx, "gfx.update_image: mip level and array layer must be non-negative")
		return false
	}
	if desc.mip_level >= image_state.mip_count || desc.array_layer >= image_state.array_count {
		set_validation_error(ctx, "gfx.update_image: subresource is out of range")
		return false
	}
	if desc.x < 0 || desc.y < 0 {
		set_validation_error(ctx, "gfx.update_image: x and y must be non-negative")
		return false
	}
	if desc.width < 0 || desc.height < 0 {
		set_validation_error(ctx, "gfx.update_image: width and height must be non-negative")
		return false
	}
	if !validate_optional_range(ctx, "gfx.update_image", "data", desc.data) {
		return false
	}
	if !range_has_data(desc.data) {
		set_validation_error(ctx, "gfx.update_image: data range is empty")
		return false
	}
	if desc.row_pitch < 0 {
		set_validation_error(ctx, "gfx.update_image: row_pitch must be non-negative")
		return false
	}

	mip_width := mip_dimension(u32(image_state.width), u32(desc.mip_level))
	mip_height := mip_dimension(u32(image_state.height), u32(desc.mip_level))
	update_width := u32(desc.width)
	update_height := u32(desc.height)
	if desc.width == 0 {
		update_width = mip_width
	}
	if desc.height == 0 {
		update_height = mip_height
	}

	if int(desc.x) + int(update_width) > int(mip_width) ||
	   int(desc.y) + int(update_height) > int(mip_height) {
		set_validation_error(ctx, "gfx.update_image: update rectangle is out of range")
		return false
	}

	pixel_size := pixel_format_size(image_state.format)
	mip_data := Image_Subresource_Data {
		data = desc.data,
		row_pitch = desc.row_pitch,
	}
	return validate_image_data_range(
		ctx,
		"gfx.update_image",
		"image update",
		mip_data,
		update_width,
		update_height,
		pixel_size,
		"requires pixel data",
	)
}

@(private)
validate_image_resolve_desc :: proc(ctx: ^Context, desc: Image_Resolve_Desc) -> bool {
	source_state := query_image_state(ctx, desc.source)
	destination_state := query_image_state(ctx, desc.destination)
	if !source_state.valid || !destination_state.valid {
		set_validation_error(ctx, "gfx.resolve_image: source or destination image is invalid")
		return false
	}
	if source_state.kind != .Image_2D || destination_state.kind != .Image_2D {
		set_unsupported_error(ctx, "gfx.resolve_image: only Image_2D resolves are supported")
		return false
	}
	if source_state.sample_count <= 1 {
		set_validation_error(ctx, "gfx.resolve_image: source image must be multisampled")
		return false
	}
	if destination_state.sample_count != 1 {
		set_validation_error(ctx, "gfx.resolve_image: destination image must be single-sampled")
		return false
	}
	if !(.Color_Attachment in source_state.usage) || !pixel_format_is_color(source_state.format) {
		set_unsupported_error(ctx, "gfx.resolve_image: only color attachment resolves are supported")
		return false
	}
	if !(.Texture in destination_state.usage) && !(.Color_Attachment in destination_state.usage) {
		set_validation_error(ctx, "gfx.resolve_image: destination image must be a Texture or Color_Attachment")
		return false
	}
	if source_state.format != destination_state.format {
		set_validation_error(ctx, "gfx.resolve_image: source and destination formats must match")
		return false
	}
	if source_state.width != destination_state.width || source_state.height != destination_state.height {
		set_validation_error(ctx, "gfx.resolve_image: source and destination dimensions must match")
		return false
	}
	if source_state.mip_count != 1 || destination_state.mip_count != 1 ||
	   source_state.array_count != 1 || destination_state.array_count != 1 {
		set_unsupported_error(ctx, "gfx.resolve_image: only single-mip single-layer resolves are supported")
		return false
	}

	return true
}

@(private)
validate_image_data_range :: proc(
	ctx: ^Context,
	op: string,
	label: string,
	mip_data: Image_Subresource_Data,
	width, height: u32,
	pixel_size: int,
	missing_data_message: string,
) -> bool {
	if mip_data.row_pitch < 0 {
		set_validation_errorf(ctx, "%s: %s row_pitch must be non-negative", op, label)
		return false
	}
	if mip_data.slice_pitch < 0 {
		set_validation_errorf(ctx, "%s: %s slice_pitch must be non-negative", op, label)
		return false
	}
	if !range_has_data(mip_data.data) {
		set_validation_errorf(ctx, "%s: %s %s", op, label, missing_data_message)
		return false
	}

	row_pitch := image_mip_row_pitch(mip_data, width, pixel_size)
	min_row_pitch := width * u32(pixel_size)
	if row_pitch < min_row_pitch {
		set_validation_errorf(ctx, "%s: %s row pitch is too small", op, label)
		return false
	}

	required_size := image_data_required_size(int(row_pitch), int(min_row_pitch), int(height))
	if mip_data.slice_pitch > 0 && int(mip_data.slice_pitch) < required_size {
		set_validation_errorf(ctx, "%s: %s slice pitch is too small", op, label)
		return false
	}
	if mip_data.data.size < required_size {
		set_validation_errorf(ctx, "%s: %s data range is too small", op, label)
		return false
	}

	return true
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
range_has_data :: proc(data: Range) -> bool {
	return data.ptr != nil || data.size != 0
}

@(private)
validate_optional_range :: proc(ctx: ^Context, op, label: string, data: Range) -> bool {
	if data.ptr == nil && data.size != 0 {
		set_validation_errorf(ctx, "%s: %s range has nil pointer", op, label)
		return false
	}
	if data.ptr != nil && data.size <= 0 {
		set_validation_errorf(ctx, "%s: %s range size must be positive when pointer is set", op, label)
		return false
	}

	return true
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

// begin_pass starts a graphics render pass.
begin_pass :: proc(ctx: ^Context, desc: Pass_Desc) -> bool {
	if !require_initialized(ctx, "gfx.begin_pass") {
		return false
	}

	if ctx.in_pass {
		set_validation_error(ctx, "gfx.begin_pass: pass already in progress")
		return false
	}

	if !validate_pass_desc(ctx, desc) {
		return false
	}

	if !backend_begin_pass(ctx, desc) {
		return false
	}

	capture_pass_attachments(ctx, desc)
	ctx.in_pass = true
	ctx.pass_kind = .Render
	return true
}

// apply_pipeline binds a graphics pipeline inside a render pass.
apply_pipeline :: proc(ctx: ^Context, pipeline: Pipeline) -> bool {
	if !require_render_pass(ctx, "gfx.apply_pipeline") {
		return false
	}

	if !require_resource(ctx, &ctx.pipeline_pool, u64(pipeline), "gfx.apply_pipeline", "pipeline") {
		return false
	}

	return backend_apply_pipeline(ctx, pipeline)
}

// begin_compute_pass starts a compute-only pass.
begin_compute_pass :: proc(ctx: ^Context, desc: Compute_Pass_Desc = {}) -> bool {
	if !require_initialized(ctx, "gfx.begin_compute_pass") {
		return false
	}

	if ctx.in_pass {
		set_validation_error(ctx, "gfx.begin_compute_pass: pass already in progress")
		return false
	}

	features := backend_query_features(ctx)
	if !features.compute {
		set_unsupported_error(ctx, "gfx.begin_compute_pass: backend does not support compute")
		return false
	}

	if !backend_begin_compute_pass(ctx, desc) {
		return false
	}

	clear_pass_attachments(ctx)
	ctx.in_pass = true
	ctx.pass_kind = .Compute
	return true
}

// apply_compute_pipeline binds a compute pipeline inside a compute pass.
apply_compute_pipeline :: proc(ctx: ^Context, pipeline: Compute_Pipeline) -> bool {
	if !require_compute_pass(ctx, "gfx.apply_compute_pipeline") {
		return false
	}

	if !require_resource(ctx, &ctx.compute_pipeline_pool, u64(pipeline), "gfx.apply_compute_pipeline", "compute pipeline") {
		return false
	}

	return backend_apply_compute_pipeline(ctx, pipeline)
}

// apply_bindings binds transient buffers, views, and samplers for draw or dispatch.
apply_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	if !require_any_pass(ctx, "gfx.apply_bindings") {
		return false
	}

	if !validate_bindings(ctx, bindings) {
		return false
	}

	return backend_apply_bindings(ctx, bindings)
}

// apply_uniforms uploads one reflected uniform block to the current pipeline.
apply_uniforms :: proc(ctx: ^Context, slot: int, data: Range) -> bool {
	if !require_any_pass(ctx, "gfx.apply_uniforms") {
		return false
	}

	if slot < 0 || slot >= MAX_UNIFORM_BLOCKS {
		set_validation_error(ctx, "gfx.apply_uniforms: slot is out of range")
		return false
	}

	if data.ptr == nil || data.size <= 0 {
		set_validation_error(ctx, "gfx.apply_uniforms: data range is empty")
		return false
	}

	return backend_apply_uniforms(ctx, slot, data)
}

// draw issues a non-indexed or indexed draw depending on the active pipeline.
draw :: proc(ctx: ^Context, base_element: i32, num_elements: i32, num_instances: i32 = 1) -> bool {
	if !require_render_pass(ctx, "gfx.draw") {
		return false
	}

	if num_elements <= 0 || num_instances <= 0 {
		set_validation_error(ctx, "gfx.draw: element and instance counts must be positive")
		return false
	}

	return backend_draw(ctx, base_element, num_elements, num_instances)
}

// dispatch issues a compute dispatch with explicit thread-group counts.
dispatch :: proc(ctx: ^Context, group_count_x: u32 = 1, group_count_y: u32 = 1, group_count_z: u32 = 1) -> bool {
	if !require_compute_pass(ctx, "gfx.dispatch") {
		return false
	}

	if group_count_x == 0 || group_count_y == 0 || group_count_z == 0 {
		set_validation_error(ctx, "gfx.dispatch: thread group counts must be positive")
		return false
	}

	return backend_dispatch(ctx, group_count_x, group_count_y, group_count_z)
}

// end_pass finishes the active render pass.
end_pass :: proc(ctx: ^Context) -> bool {
	if !require_initialized(ctx, "gfx.end_pass") {
		return false
	}

	if !ctx.in_pass {
		set_validation_error(ctx, "gfx.end_pass: no pass in progress")
		return false
	}
	if ctx.pass_kind != .Render {
		set_validation_error(ctx, "gfx.end_pass: current pass is not a render pass")
		return false
	}

	ok := backend_end_pass(ctx)
	clear_pass_attachments(ctx)
	ctx.in_pass = false
	ctx.pass_kind = .None
	return ok
}

// end_compute_pass finishes the active compute pass.
end_compute_pass :: proc(ctx: ^Context) -> bool {
	if !require_initialized(ctx, "gfx.end_compute_pass") {
		return false
	}

	if !ctx.in_pass {
		set_validation_error(ctx, "gfx.end_compute_pass: no pass in progress")
		return false
	}
	if ctx.pass_kind != .Compute {
		set_validation_error(ctx, "gfx.end_compute_pass: current pass is not a compute pass")
		return false
	}

	ok := backend_end_compute_pass(ctx)
	clear_pass_attachments(ctx)
	ctx.in_pass = false
	ctx.pass_kind = .None
	return ok
}

// commit presents the frame and advances frame_index.
commit :: proc(ctx: ^Context) -> bool {
	if !require_initialized(ctx, "gfx.commit") {
		return false
	}

	if ctx.in_pass {
		set_validation_error(ctx, "gfx.commit: cannot commit while a pass is in progress")
		return false
	}

	if !backend_commit(ctx) {
		return false
	}

	ctx.frame_index += 1
	return true
}

// last_error returns the most recent validation or backend error for a context.
last_error :: proc(ctx: ^Context) -> string {
	if ctx == nil {
		return "gfx: nil context"
	}

	return ctx.last_error
}

// last_error_code returns the machine-readable code for the most recent context error.
last_error_code :: proc(ctx: ^Context) -> Error_Code {
	if ctx == nil {
		return .Validation
	}

	return ctx.last_error_code
}

// last_error_info returns the most recent context error code and message together.
last_error_info :: proc(ctx: ^Context) -> Error_Info {
	if ctx == nil {
		return {code = .Validation, message = "gfx: nil context"}
	}

	return {code = ctx.last_error_code, message = ctx.last_error}
}

@(private)
resolve_backend :: proc(requested: Backend) -> Backend {
	if requested == .Auto {
		return .Null
	}

	return requested
}

@(private)
allocate_context_id :: proc() -> u32 {
	if global_next_context_id == 0 || global_next_context_id > HANDLE_MAX_CONTEXT_ID {
		return 0
	}

	id := global_next_context_id
	global_next_context_id += 1
	return id
}

@(private)
alloc_resource_id :: proc(ctx: ^Context, pool: ^Resource_Pool, op: string) -> u64 {
	if ctx == nil || pool == nil || ctx.context_id == 0 {
		set_validation_errorf(ctx, "%s: context handle namespace is invalid", op)
		return 0
	}

	slot: u32
	generation: u32
	if len(pool.free_slots) > 0 {
		free_index := len(pool.free_slots) - 1
		slot = pool.free_slots[free_index]
		pop(&pool.free_slots)
		generation = pool.generations[int(slot)]
	} else {
		if len(pool.generations) > int(HANDLE_MAX_SLOT_INDEX) {
			set_validation_errorf(ctx, "%s: resource pool is full", op)
			return 0
		}

		slot = u32(len(pool.generations))
		generation = 1
		append(&pool.generations, generation)
		append(&pool.live, false)
	}

	pool.live[int(slot)] = true
	pool.live_count += 1

	return encode_resource_id(ctx.context_id, generation, slot)
}

@(private)
cancel_resource_id :: proc(pool: ^Resource_Pool, handle: u64) {
	if pool == nil || handle == 0 {
		return
	}

	slot := handle_slot(handle)
	if slot >= u32(len(pool.live)) || !pool.live[int(slot)] {
		return
	}

	pool.live[int(slot)] = false
	pool.live_count -= 1
	append(&pool.free_slots, slot)
}

@(private)
release_resource_id :: proc(pool: ^Resource_Pool, handle: u64) {
	if pool == nil || handle == 0 {
		return
	}

	slot := handle_slot(handle)
	if slot >= u32(len(pool.live)) || !pool.live[int(slot)] {
		return
	}

	pool.live[int(slot)] = false
	pool.generations[int(slot)] = next_generation(pool.generations[int(slot)])
	pool.live_count -= 1
	append(&pool.free_slots, slot)
}

@(private)
resource_id_alive :: proc(ctx: ^Context, pool: ^Resource_Pool, handle: u64) -> bool {
	return resource_id_status(ctx, pool, handle) == .Alive
}

@(private)
require_resource :: proc(ctx: ^Context, pool: ^Resource_Pool, handle: u64, op, label: string) -> bool {
	status := resource_id_status(ctx, pool, handle)
	switch status {
	case .Alive:
		return true
	case .Invalid:
		set_errorf_code(ctx, .Invalid_Handle, "%s: %s handle is invalid", op, label)
	case .Wrong_Context:
		set_errorf_code(ctx, .Wrong_Context, "%s: %s handle belongs to a different context", op, label)
	case .Stale:
		set_errorf_code(ctx, .Stale_Handle, "%s: %s handle is stale or destroyed", op, label)
	}

	return false
}

@(private)
resource_id_status :: proc(ctx: ^Context, pool: ^Resource_Pool, handle: u64) -> Resource_Handle_Status {
	if handle == 0 || pool == nil {
		return .Invalid
	}
	if ctx == nil || ctx.context_id == 0 || handle_context_id(handle) != ctx.context_id {
		return .Wrong_Context
	}

	slot := handle_slot(handle)
	if slot >= u32(len(pool.generations)) || slot >= u32(len(pool.live)) {
		return .Stale
	}
	if !pool.live[int(slot)] {
		return .Stale
	}
	if pool.generations[int(slot)] != handle_generation(handle) {
		return .Stale
	}

	return .Alive
}

@(private)
encode_resource_id :: proc(context_id, generation, slot: u32) -> u64 {
	return (u64(context_id) << HANDLE_CONTEXT_SHIFT) |
	       (u64(generation) << HANDLE_GENERATION_SHIFT) |
	       u64(slot)
}

@(private)
handle_context_id :: proc(handle: u64) -> u32 {
	return u32((handle >> HANDLE_CONTEXT_SHIFT) & HANDLE_CONTEXT_MASK)
}

@(private)
handle_generation :: proc(handle: u64) -> u32 {
	return u32((handle >> HANDLE_GENERATION_SHIFT) & HANDLE_GENERATION_MASK)
}

@(private)
handle_slot :: proc(handle: u64) -> u32 {
	return u32(handle & HANDLE_INDEX_MASK)
}

@(private)
next_generation :: proc(generation: u32) -> u32 {
	next := generation + 1
	if next == 0 || next > HANDLE_MAX_GENERATION {
		return 1
	}

	return next
}

@(private)
resource_pool_live_total :: proc(ctx: ^Context) -> int {
	if ctx == nil {
		return 0
	}

	return ctx.buffer_pool.live_count +
	       ctx.image_pool.live_count +
	       ctx.view_pool.live_count +
	       ctx.sampler_pool.live_count +
	       ctx.shader_pool.live_count +
	       ctx.pipeline_pool.live_count +
	       ctx.compute_pipeline_pool.live_count
}

@(private)
delete_resource_pools :: proc(ctx: ^Context) {
	delete_resource_pool(&ctx.buffer_pool)
	delete_resource_pool(&ctx.image_pool)
	delete_resource_pool(&ctx.view_pool)
	delete_resource_pool(&ctx.sampler_pool)
	delete_resource_pool(&ctx.shader_pool)
	delete_resource_pool(&ctx.pipeline_pool)
	delete_resource_pool(&ctx.compute_pipeline_pool)
	if ctx.shader_states != nil {
		delete(ctx.shader_states)
		ctx.shader_states = nil
	}
}

@(private)
delete_resource_pool :: proc(pool: ^Resource_Pool) {
	if pool == nil {
		return
	}

	delete(pool.generations)
	delete(pool.live)
	delete(pool.free_slots)
	pool^ = {}
}

@(private)
set_error_code :: proc(ctx: ^Context, code: Error_Code, message: string) {
	if ctx == nil {
		return
	}

	ctx.last_error = message
	ctx.last_error_code = code
}

@(private)
set_errorf_code :: proc(ctx: ^Context, code: Error_Code, format: string, args: ..any) {
	if ctx == nil {
		return
	}

	set_error_code(ctx, code, fmt.bprintf(ctx.last_error_storage[:], format, ..args))
}

@(private)
set_validation_error :: proc(ctx: ^Context, message: string) {
	set_error_code(ctx, .Validation, message)
}

@(private)
set_validation_errorf :: proc(ctx: ^Context, format: string, args: ..any) {
	set_errorf_code(ctx, .Validation, format, ..args)
}

@(private)
set_unsupported_error :: proc(ctx: ^Context, message: string) {
	set_error_code(ctx, .Unsupported, message)
}

@(private)
set_unsupported_errorf :: proc(ctx: ^Context, format: string, args: ..any) {
	set_errorf_code(ctx, .Unsupported, format, ..args)
}

@(private)
set_invalid_handle_error :: proc(ctx: ^Context, message: string) {
	set_error_code(ctx, .Invalid_Handle, message)
}

@(private)
set_invalid_handle_errorf :: proc(ctx: ^Context, format: string, args: ..any) {
	set_errorf_code(ctx, .Invalid_Handle, format, ..args)
}

@(private)
set_backend_error :: proc(ctx: ^Context, message: string) {
	set_error_code(ctx, .Backend, message)
}

@(private)
set_backend_errorf :: proc(ctx: ^Context, format: string, args: ..any) {
	set_errorf_code(ctx, .Backend, format, ..args)
}

@(private)
require_initialized :: proc(ctx: ^Context, op: string) -> bool {
	if ctx == nil {
		return false
	}

	if !ctx.initialized {
		set_validation_error(ctx, "gfx: context is not initialized")
		return false
	}

	return true
}

@(private)
require_pass :: proc(ctx: ^Context, op: string) -> bool {
	return require_any_pass(ctx, op)
}

@(private)
require_any_pass :: proc(ctx: ^Context, op: string) -> bool {
	if !require_initialized(ctx, op) {
		return false
	}

	if !ctx.in_pass {
		set_validation_error(ctx, "gfx: no pass in progress")
		return false
	}

	return true
}

@(private)
require_render_pass :: proc(ctx: ^Context, op: string) -> bool {
	if !require_any_pass(ctx, op) {
		return false
	}

	if ctx.pass_kind != .Render {
		set_validation_error(ctx, "gfx: render pass is not in progress")
		return false
	}

	return true
}

@(private)
require_compute_pass :: proc(ctx: ^Context, op: string) -> bool {
	if !require_any_pass(ctx, op) {
		return false
	}

	if ctx.pass_kind != .Compute {
		set_validation_error(ctx, "gfx: compute pass is not in progress")
		return false
	}

	return true
}

@(private)
validate_buffer_transfer :: proc(ctx: ^Context, op: string, buffer: Buffer, offset: int, data: Range) -> (Buffer_State, bool) {
	if !require_initialized(ctx, op) {
		return {}, false
	}

	if ctx.in_pass {
		set_validation_errorf(ctx, "%s: cannot transfer buffer data while a pass is in progress", op)
		return {}, false
	}

	if !require_resource(ctx, &ctx.buffer_pool, u64(buffer), op, "buffer") {
		return {}, false
	}

	if offset < 0 {
		set_validation_errorf(ctx, "%s: offset must be non-negative", op)
		return {}, false
	}

	if data.ptr == nil || data.size <= 0 {
		set_validation_errorf(ctx, "%s: data range is empty", op)
		return {}, false
	}

	buffer_state := query_buffer_state(ctx, buffer)
	if !buffer_state.valid {
		set_invalid_handle_errorf(ctx, "%s: buffer handle is invalid", op)
		return {}, false
	}

	if offset > buffer_state.size || data.size > buffer_state.size - offset {
		set_validation_errorf(ctx, "%s: range exceeds buffer size", op)
		return {}, false
	}

	return buffer_state, true
}

@(private)
capture_pass_attachments :: proc(ctx: ^Context, desc: Pass_Desc) {
	if ctx == nil {
		return
	}

	ctx.pass_color_attachments = desc.color_attachments
	ctx.pass_depth_stencil_attachment = desc.depth_stencil_attachment
}

@(private)
clear_pass_attachments :: proc(ctx: ^Context) {
	if ctx == nil {
		return
	}

	ctx.pass_color_attachments = {}
	ctx.pass_depth_stencil_attachment = View_Invalid
}

@(private)
validate_pass_desc :: proc(ctx: ^Context, desc: Pass_Desc) -> bool {
	if !validate_pass_action_desc(ctx, desc.action) {
		return false
	}

	has_color := false
	color_count := 0
	highest_color_slot := -1
	pass_width: i32
	pass_height: i32
	pass_sample_count: i32

	for attachment, slot in desc.color_attachments {
		if !view_valid(attachment) {
			continue
		}
		color_count += 1
		highest_color_slot = slot
		if !require_resource(ctx, &ctx.view_pool, u64(attachment), "gfx.begin_pass", "color attachment view") {
			return false
		}

		view_state := query_view_state(ctx, attachment)
		if !view_state.valid {
			set_invalid_handle_errorf(ctx, "gfx.begin_pass: color attachment view slot %d is invalid", slot)
			return false
		}
		if view_state.kind != .Color_Attachment {
			set_validation_errorf(ctx, "gfx.begin_pass: color attachment slot %d requires a color attachment view", slot)
			return false
		}

		for other_attachment, other_slot in desc.color_attachments {
			if other_slot >= slot || !view_valid(other_attachment) {
				continue
			}
			if other_attachment == attachment {
				set_validation_errorf(ctx, "gfx.begin_pass: color attachment view is bound more than once at slots %d and %d", other_slot, slot)
				return false
			}

			other_state := query_view_state(ctx, other_attachment)
			if other_state.valid && view_states_alias_resource(view_state, other_state) {
				set_validation_errorf(ctx, "gfx.begin_pass: color attachment slots %d and %d alias the same image", other_slot, slot)
				return false
			}
		}

		if !has_color {
			pass_width = view_state.width
			pass_height = view_state.height
			pass_sample_count = view_state.sample_count
			has_color = true
		} else if view_state.width != pass_width || view_state.height != pass_height {
			set_validation_error(ctx, "gfx.begin_pass: color attachments must have matching dimensions")
			return false
		} else if view_state.sample_count != pass_sample_count {
			set_validation_error(ctx, "gfx.begin_pass: color attachments must have matching sample counts")
			return false
		}
	}

	if highest_color_slot > 0 {
		for slot in 0..<highest_color_slot {
			if !view_valid(desc.color_attachments[slot]) {
				set_validation_errorf(ctx, "gfx.begin_pass: color attachments must be contiguous from slot 0; slot %d is missing", slot)
				return false
			}
		}
	}
	if color_count > 1 {
		features := backend_query_features(ctx)
		if !features.multiple_render_targets {
			set_unsupported_error(ctx, "gfx.begin_pass: multiple color attachments are not supported by this backend")
			return false
		}
	}

	if view_valid(desc.depth_stencil_attachment) {
		if !require_resource(ctx, &ctx.view_pool, u64(desc.depth_stencil_attachment), "gfx.begin_pass", "depth-stencil attachment view") {
			return false
		}

		depth_state := query_view_state(ctx, desc.depth_stencil_attachment)
		if !depth_state.valid {
			set_invalid_handle_error(ctx, "gfx.begin_pass: depth-stencil attachment view is invalid")
			return false
		}
		if depth_state.kind != .Depth_Stencil_Attachment {
			set_validation_error(ctx, "gfx.begin_pass: depth-stencil attachment requires a depth-stencil attachment view")
			return false
		}

		for attachment, slot in desc.color_attachments {
			if view_valid(attachment) && attachment == desc.depth_stencil_attachment {
				set_validation_errorf(ctx, "gfx.begin_pass: depth-stencil attachment is also bound as color attachment slot %d", slot)
				return false
			}
			if !view_valid(attachment) {
				continue
			}

			color_state := query_view_state(ctx, attachment)
			if color_state.valid && view_states_alias_resource(depth_state, color_state) {
				set_validation_errorf(ctx, "gfx.begin_pass: depth-stencil attachment aliases color attachment slot %d", slot)
				return false
			}
		}

		if has_color {
			if depth_state.width != pass_width || depth_state.height != pass_height {
				set_validation_error(ctx, "gfx.begin_pass: depth-stencil attachment dimensions must match color attachments")
				return false
			}
			if depth_state.sample_count != pass_sample_count {
				set_validation_error(ctx, "gfx.begin_pass: depth-stencil attachment sample count must match color attachments")
				return false
			}
		}
	}

	return true
}

@(private)
validate_pass_action_desc :: proc(ctx: ^Context, action: Pass_Action) -> bool {
	for color, slot in action.colors {
		if !load_action_valid(color.load_action) {
			set_validation_errorf(ctx, "gfx.begin_pass: color action slot %d has an invalid load_action", slot)
			return false
		}
		if !store_action_valid(color.store_action) {
			set_validation_errorf(ctx, "gfx.begin_pass: color action slot %d has an invalid store_action", slot)
			return false
		}
	}

	if !load_action_valid(action.depth.load_action) {
		set_validation_error(ctx, "gfx.begin_pass: depth action has an invalid load_action")
		return false
	}
	if !store_action_valid(action.depth.store_action) {
		set_validation_error(ctx, "gfx.begin_pass: depth action has an invalid store_action")
		return false
	}
	if action.depth.load_action == .Clear && (action.depth.clear_value < 0 || action.depth.clear_value > 1) {
		set_validation_error(ctx, "gfx.begin_pass: depth clear value must be between 0 and 1")
		return false
	}

	if !load_action_valid(action.stencil.load_action) {
		set_validation_error(ctx, "gfx.begin_pass: stencil action has an invalid load_action")
		return false
	}
	if !store_action_valid(action.stencil.store_action) {
		set_validation_error(ctx, "gfx.begin_pass: stencil action has an invalid store_action")
		return false
	}

	return true
}

@(private)
validate_pipeline_desc :: proc(ctx: ^Context, desc: Pipeline_Desc) -> bool {
	if !primitive_type_valid(desc.primitive_type) {
		set_validation_error(ctx, "gfx.create_pipeline: primitive_type is invalid")
		return false
	}
	if !index_type_valid(desc.index_type) {
		set_validation_error(ctx, "gfx.create_pipeline: index_type is invalid")
		return false
	}
	if !validate_raster_state(ctx, desc.raster) {
		return false
	}
	if !validate_depth_state(ctx, desc.depth) {
		return false
	}
	for color, slot in desc.colors {
		if !validate_color_state(ctx, color, slot) {
			return false
		}
	}

	if desc.depth_only {
		if !desc.depth.enabled {
			set_validation_error(ctx, "gfx.create_pipeline: depth-only pipeline requires depth to be enabled")
			return false
		}
		for format, slot in desc.color_formats {
			if format != .Invalid {
				set_validation_errorf(ctx, "gfx.create_pipeline: depth-only pipeline cannot declare color format at slot %d", slot)
				return false
			}
		}
	} else if !validate_pipeline_color_formats(ctx, desc.color_formats) {
		return false
	}

	if desc.depth.enabled {
		if !pixel_format_is_depth(desc.depth.format) {
			set_validation_error(ctx, "gfx.create_pipeline: depth-enabled pipeline requires a depth format")
			return false
		}
	} else {
		if desc.depth.write_enabled {
			set_validation_error(ctx, "gfx.create_pipeline: depth writes require depth to be enabled")
			return false
		}
		if desc.depth.format != .Invalid && !pixel_format_is_depth(desc.depth.format) {
			set_validation_error(ctx, "gfx.create_pipeline: disabled depth state has an invalid depth format")
			return false
		}
	}

	if !validate_layout_desc(ctx, desc.layout) {
		return false
	}

	return true
}

@(private)
validate_raster_state :: proc(ctx: ^Context, state: Raster_State) -> bool {
	if !fill_mode_valid(state.fill_mode) {
		set_validation_error(ctx, "gfx.create_pipeline: raster fill_mode is invalid")
		return false
	}
	if !cull_mode_valid(state.cull_mode) {
		set_validation_error(ctx, "gfx.create_pipeline: raster cull_mode is invalid")
		return false
	}
	if !face_winding_valid(state.winding) {
		set_validation_error(ctx, "gfx.create_pipeline: raster winding is invalid")
		return false
	}

	return true
}

@(private)
validate_depth_state :: proc(ctx: ^Context, state: Depth_State) -> bool {
	if !compare_func_valid(state.compare) {
		set_validation_error(ctx, "gfx.create_pipeline: depth compare function is invalid")
		return false
	}

	return true
}

@(private)
validate_color_state :: proc(ctx: ^Context, state: Color_State, slot: int) -> bool {
	if state.write_mask & COLOR_MASK_RGBA != state.write_mask {
		set_validation_errorf(ctx, "gfx.create_pipeline: color state slot %d write_mask has invalid bits", slot)
		return false
	}

	blend := state.blend
	if !blend_factor_valid(blend.src_factor) {
		set_validation_errorf(ctx, "gfx.create_pipeline: color state slot %d blend src_factor is invalid", slot)
		return false
	}
	if !blend_factor_valid(blend.dst_factor) {
		set_validation_errorf(ctx, "gfx.create_pipeline: color state slot %d blend dst_factor is invalid", slot)
		return false
	}
	if !blend_op_valid(blend.op) {
		set_validation_errorf(ctx, "gfx.create_pipeline: color state slot %d blend op is invalid", slot)
		return false
	}
	if !blend_factor_valid(blend.src_alpha_factor) {
		set_validation_errorf(ctx, "gfx.create_pipeline: color state slot %d blend src_alpha_factor is invalid", slot)
		return false
	}
	if !blend_factor_valid(blend.dst_alpha_factor) {
		set_validation_errorf(ctx, "gfx.create_pipeline: color state slot %d blend dst_alpha_factor is invalid", slot)
		return false
	}
	if !blend_op_valid(blend.alpha_op) {
		set_validation_errorf(ctx, "gfx.create_pipeline: color state slot %d blend alpha_op is invalid", slot)
		return false
	}

	return true
}

@(private)
validate_graphics_pipeline_shader :: proc(ctx: ^Context, desc: Pipeline_Desc) -> bool {
	shader_state, shader_state_ok := query_shader_state(ctx, desc.shader)
	if !shader_state_ok {
		set_validation_error(ctx, "gfx.create_pipeline: shader state is unavailable")
		return false
	}
	if shader_state.has_compute {
		set_validation_error(ctx, "gfx.create_pipeline: compute shaders cannot be used for graphics pipelines")
		return false
	}
	if !shader_state.has_vertex || !shader_state.has_fragment {
		set_validation_error(ctx, "gfx.create_pipeline: shader must contain vertex and fragment stages")
		return false
	}

	return validate_pipeline_vertex_inputs(ctx, shader_state, desc.layout)
}

@(private)
validate_compute_pipeline_desc :: proc(ctx: ^Context, desc: Compute_Pipeline_Desc) -> bool {
	shader_state, shader_state_ok := query_shader_state(ctx, desc.shader)
	if !shader_state_ok {
		set_validation_error(ctx, "gfx.create_compute_pipeline: shader state is unavailable")
		return false
	}
	if !shader_state.has_compute {
		set_validation_error(ctx, "gfx.create_compute_pipeline: shader must contain a compute stage")
		return false
	}
	if shader_state.has_vertex || shader_state.has_fragment {
		set_validation_error(ctx, "gfx.create_compute_pipeline: graphics shaders cannot be used for compute pipelines")
		return false
	}

	return true
}

@(private)
validate_pipeline_vertex_inputs :: proc(ctx: ^Context, shader_state: Shader_State, layout: Layout_Desc) -> bool {
	if !shader_state.has_vertex_input_metadata {
		return true
	}

	for input in shader_state.vertex_inputs {
		if !input.active {
			continue
		}

		attr, attr_ok := find_layout_attr(layout, input.semantic, input.semantic_index)
		if !attr_ok {
			set_validation_errorf(
				ctx,
				"gfx.create_pipeline: pipeline layout is missing shader vertex input %s%d",
				input.semantic,
				input.semantic_index,
			)
			return false
		}
		if attr.format != input.format {
			set_validation_errorf(
				ctx,
				"gfx.create_pipeline: pipeline vertex input %s%d format does not match shader reflection",
				input.semantic,
				input.semantic_index,
			)
			return false
		}
	}

	for attr in layout.attrs {
		if !vertex_attr_desc_active(attr) {
			continue
		}
		if !shader_has_vertex_input(shader_state, string(attr.semantic), attr.semantic_index) {
			set_validation_errorf(
				ctx,
				"gfx.create_pipeline: pipeline layout declares unused shader vertex input %s%d",
				string(attr.semantic),
				attr.semantic_index,
			)
			return false
		}
	}

	return true
}

@(private)
validate_pipeline_color_formats :: proc(ctx: ^Context, formats: [MAX_COLOR_ATTACHMENTS]Pixel_Format) -> bool {
	highest_used_slot := -1
	for format, slot in formats {
		if format == .Invalid {
			continue
		}
		if !pixel_format_is_color(format) {
			set_validation_errorf(ctx, "gfx.create_pipeline: color format at slot %d must be a color format", slot)
			return false
		}
		highest_used_slot = slot
	}

	if highest_used_slot > 0 {
		for slot in 0..<highest_used_slot {
			if formats[slot] == .Invalid {
				set_validation_errorf(ctx, "gfx.create_pipeline: color formats must be contiguous from slot 0; slot %d is missing", slot)
				return false
			}
		}
	}

	return true
}

@(private)
validate_layout_desc :: proc(ctx: ^Context, layout: Layout_Desc) -> bool {
	for attr, attr_slot in layout.attrs {
		if !vertex_attr_desc_active(attr) {
			continue
		}

		if attr.semantic == nil {
			set_validation_errorf(ctx, "gfx.create_pipeline: vertex attribute %d requires a semantic", attr_slot)
			return false
		}
		if string(attr.semantic) == "" {
			set_validation_errorf(ctx, "gfx.create_pipeline: vertex attribute %d requires a non-empty semantic", attr_slot)
			return false
		}
		if attr.format == .Invalid {
			set_validation_errorf(ctx, "gfx.create_pipeline: vertex attribute %d requires a format", attr_slot)
			return false
		}
		if attr.buffer_slot >= MAX_VERTEX_BUFFERS {
			set_validation_errorf(ctx, "gfx.create_pipeline: vertex attribute %d buffer slot is out of range", attr_slot)
			return false
		}

		format_size := vertex_format_size(attr.format)
		if format_size == 0 {
			set_unsupported_errorf(ctx, "gfx.create_pipeline: vertex attribute %d uses an unsupported format", attr_slot)
			return false
		}

		buffer_layout := layout.buffers[int(attr.buffer_slot)]
		if buffer_layout.stride == 0 {
			set_validation_errorf(ctx, "gfx.create_pipeline: vertex attribute %d references buffer slot %d with zero stride", attr_slot, attr.buffer_slot)
			return false
		}
		if u64(attr.offset) + u64(format_size) > u64(buffer_layout.stride) {
			set_validation_errorf(ctx, "gfx.create_pipeline: vertex attribute %d exceeds vertex buffer stride", attr_slot)
			return false
		}

		for other_attr, other_slot in layout.attrs {
			if other_slot >= attr_slot || !vertex_attr_desc_active(other_attr) {
				continue
			}
			if other_attr.semantic != nil &&
			   string(other_attr.semantic) == string(attr.semantic) &&
			   other_attr.semantic_index == attr.semantic_index {
				set_validation_errorf(ctx, "gfx.create_pipeline: duplicate vertex semantic %s%d", string(attr.semantic), attr.semantic_index)
				return false
			}
		}
	}

	for buffer_layout, slot in layout.buffers {
		if buffer_layout.stride == 0 {
			continue
		}

		if !vertex_step_function_valid(buffer_layout.step_func) {
			set_validation_errorf(ctx, "gfx.create_pipeline: vertex buffer slot %d step_func is invalid", slot)
			return false
		}

		switch buffer_layout.step_func {
		case .Per_Vertex:
			if buffer_layout.step_rate != 0 {
				set_validation_errorf(ctx, "gfx.create_pipeline: per-vertex buffer slot %d must use step_rate 0", slot)
				return false
			}
		case .Per_Instance:
			if buffer_layout.step_rate == 0 {
				set_validation_errorf(ctx, "gfx.create_pipeline: per-instance buffer slot %d must use nonzero step_rate", slot)
				return false
			}
		}
	}

	return true
}

@(private)
validate_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	for binding, slot in bindings.vertex_buffers {
		if !buffer_valid(binding.buffer) {
			continue
		}
		if ctx.pass_kind == .Compute {
			set_validation_errorf(ctx, "gfx.apply_bindings: vertex buffer slot %d cannot be used in a compute pass", slot)
			return false
		}
		if binding.offset < 0 {
			set_validation_errorf(ctx, "gfx.apply_bindings: vertex buffer slot %d offset must be non-negative", slot)
			return false
		}
		if !require_resource(ctx, &ctx.buffer_pool, u64(binding.buffer), "gfx.apply_bindings", "vertex buffer") {
			return false
		}

		buffer_state := query_buffer_state(ctx, binding.buffer)
		if !buffer_state.valid {
			set_invalid_handle_errorf(ctx, "gfx.apply_bindings: vertex buffer slot %d handle is invalid", slot)
			return false
		}
		if !(.Vertex in buffer_state.usage) {
			set_validation_errorf(ctx, "gfx.apply_bindings: vertex buffer slot %d requires a vertex-capable buffer", slot)
			return false
		}
		if binding.offset > buffer_state.size {
			set_validation_errorf(ctx, "gfx.apply_bindings: vertex buffer slot %d offset exceeds buffer size", slot)
			return false
		}
	}

	if buffer_valid(bindings.index_buffer.buffer) {
		if ctx.pass_kind == .Compute {
			set_validation_error(ctx, "gfx.apply_bindings: index buffer cannot be used in a compute pass")
			return false
		}
		if bindings.index_buffer.offset < 0 {
			set_validation_error(ctx, "gfx.apply_bindings: index buffer offset must be non-negative")
			return false
		}
		if !require_resource(ctx, &ctx.buffer_pool, u64(bindings.index_buffer.buffer), "gfx.apply_bindings", "index buffer") {
			return false
		}

		buffer_state := query_buffer_state(ctx, bindings.index_buffer.buffer)
		if !buffer_state.valid {
			set_invalid_handle_error(ctx, "gfx.apply_bindings: index buffer handle is invalid")
			return false
		}
		if !(.Index in buffer_state.usage) {
			set_validation_error(ctx, "gfx.apply_bindings: index buffer requires an index-capable buffer")
			return false
		}
		if bindings.index_buffer.offset > buffer_state.size {
			set_validation_error(ctx, "gfx.apply_bindings: index buffer offset exceeds buffer size")
			return false
		}
	}

	for view, slot in bindings.views {
		if !view_valid(view) {
			continue
		}
		if !require_resource(ctx, &ctx.view_pool, u64(view), "gfx.apply_bindings", "resource view") {
			return false
		}

		view_state := query_view_state(ctx, view)
		if !view_state.valid {
			set_invalid_handle_errorf(ctx, "gfx.apply_bindings: resource view slot %d handle is invalid", slot)
			return false
		}

		switch view_state.kind {
		case .Sampled, .Storage_Image, .Storage_Buffer:
		case .Color_Attachment, .Depth_Stencil_Attachment:
			set_validation_errorf(ctx, "gfx.apply_bindings: resource view slot %d requires a sampled or storage view", slot)
			return false
		}
	}

	if !validate_binding_resource_hazards(ctx, bindings) {
		return false
	}

	for sampler in bindings.samplers {
		if !sampler_valid(sampler) {
			continue
		}
		if !require_resource(ctx, &ctx.sampler_pool, u64(sampler), "gfx.apply_bindings", "sampler") {
			return false
		}
	}

	return true
}

@(private)
validate_binding_resource_hazards :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	for view, slot in bindings.views {
		if !view_valid(view) {
			continue
		}

		view_state := query_view_state(ctx, view)
		if !view_state.valid {
			continue
		}

		if ctx.pass_kind == .Render && view_state_aliases_active_pass_attachment(ctx, view_state) {
			set_validation_errorf(ctx, "gfx.apply_bindings: resource view slot %d aliases an active pass attachment", slot)
			return false
		}

		current_writes := view_state_writes_resource(view_state)
		current_reads := view_state_reads_resource(view_state)
		for other_view, other_slot in bindings.views {
			if other_slot >= slot || !view_valid(other_view) {
				continue
			}

			other_state := query_view_state(ctx, other_view)
			if !other_state.valid || !view_states_alias_resource(view_state, other_state) {
				continue
			}

			other_writes := view_state_writes_resource(other_state)
			other_reads := view_state_reads_resource(other_state)
			if current_writes && other_writes {
				set_validation_errorf(ctx, "gfx.apply_bindings: resource view slots %d and %d write the same resource", other_slot, slot)
				return false
			}
			if current_reads && other_writes {
				set_validation_errorf(ctx, "gfx.apply_bindings: resource view slot %d reads a resource written by slot %d", slot, other_slot)
				return false
			}
			if current_writes && other_reads {
				set_validation_errorf(ctx, "gfx.apply_bindings: resource view slot %d writes a resource read by slot %d", slot, other_slot)
				return false
			}
		}
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
find_layout_attr :: proc(layout: Layout_Desc, semantic: string, semantic_index: u32) -> (Vertex_Attribute_Desc, bool) {
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

@(private)
shader_has_vertex_input :: proc(shader_state: Shader_State, semantic: string, semantic_index: u32) -> bool {
	for input in shader_state.vertex_inputs {
		if input.active && input.semantic == semantic && input.semantic_index == semantic_index {
			return true
		}
	}

	return false
}

@(private)
vertex_attr_desc_active :: proc(attr: Vertex_Attribute_Desc) -> bool {
	return attr.semantic != nil || attr.format != .Invalid
}

@(private)
filter_valid :: proc(value: Filter) -> bool {
	switch value {
	case .Nearest, .Linear:
		return true
	}

	return false
}

@(private)
wrap_valid :: proc(value: Wrap) -> bool {
	switch value {
	case .Repeat, .Clamp_To_Edge, .Mirrored_Repeat:
		return true
	}

	return false
}

@(private)
shader_stage_valid :: proc(value: Shader_Stage) -> bool {
	switch value {
	case .Vertex, .Fragment, .Compute:
		return true
	}

	return false
}

@(private)
shader_stage_name :: proc(value: Shader_Stage) -> string {
	switch value {
	case .Vertex:
		return "vertex"
	case .Fragment:
		return "fragment"
	case .Compute:
		return "compute"
	}

	return "invalid"
}

@(private)
shader_binding_kind_valid :: proc(value: Shader_Binding_Kind) -> bool {
	switch value {
	case .Uniform_Block, .Resource_View, .Sampler:
		return true
	}

	return false
}

@(private)
shader_binding_kind_name :: proc(value: Shader_Binding_Kind) -> string {
	switch value {
	case .Uniform_Block:
		return "uniform"
	case .Resource_View:
		return "resource view"
	case .Sampler:
		return "sampler"
	}

	return "invalid"
}

@(private)
shader_resource_view_kind_valid :: proc(value: View_Kind) -> bool {
	switch value {
	case .Sampled, .Storage_Image, .Storage_Buffer:
		return true
	case .Color_Attachment, .Depth_Stencil_Attachment:
		return false
	}

	return false
}

@(private)
shader_resource_access_valid :: proc(value: Shader_Resource_Access) -> bool {
	switch value {
	case .Unknown, .Read, .Write, .Read_Write:
		return true
	}

	return false
}

@(private)
shader_storage_image_format_valid :: proc(value: Pixel_Format) -> bool {
	switch value {
	case .Invalid, .RGBA32F, .R32F:
		return true
	case .RGBA8, .BGRA8, .RGBA16F, .D24S8, .D32F:
		return false
	}

	return false
}

@(private)
primitive_type_valid :: proc(value: Primitive_Type) -> bool {
	switch value {
	case .Triangles, .Lines, .Points:
		return true
	}

	return false
}

@(private)
index_type_valid :: proc(value: Index_Type) -> bool {
	switch value {
	case .None, .Uint16, .Uint32:
		return true
	}

	return false
}

@(private)
fill_mode_valid :: proc(value: Fill_Mode) -> bool {
	switch value {
	case .Solid, .Wireframe:
		return true
	}

	return false
}

@(private)
cull_mode_valid :: proc(value: Cull_Mode) -> bool {
	switch value {
	case .None, .Front, .Back:
		return true
	}

	return false
}

@(private)
face_winding_valid :: proc(value: Face_Winding) -> bool {
	switch value {
	case .Clockwise, .Counter_Clockwise:
		return true
	}

	return false
}

@(private)
compare_func_valid :: proc(value: Compare_Func) -> bool {
	switch value {
	case .Always, .Never, .Less, .Less_Equal, .Equal, .Greater_Equal, .Greater, .Not_Equal:
		return true
	}

	return false
}

@(private)
blend_factor_valid :: proc(value: Blend_Factor) -> bool {
	switch value {
	case .Default,
	     .Zero,
	     .One,
	     .Src_Color,
	     .One_Minus_Src_Color,
	     .Src_Alpha,
	     .One_Minus_Src_Alpha,
	     .Dst_Color,
	     .One_Minus_Dst_Color,
	     .Dst_Alpha,
	     .One_Minus_Dst_Alpha,
	     .Blend_Color,
	     .One_Minus_Blend_Color,
	     .Src_Alpha_Saturated:
		return true
	}

	return false
}

@(private)
blend_op_valid :: proc(value: Blend_Op) -> bool {
	switch value {
	case .Default, .Add, .Subtract, .Reverse_Subtract, .Min, .Max:
		return true
	}

	return false
}

@(private)
vertex_step_function_valid :: proc(value: Vertex_Step_Function) -> bool {
	switch value {
	case .Per_Vertex, .Per_Instance:
		return true
	}

	return false
}

@(private)
load_action_valid :: proc(value: Load_Action) -> bool {
	switch value {
	case .Clear, .Load, .Dont_Care:
		return true
	}

	return false
}

@(private)
store_action_valid :: proc(value: Store_Action) -> bool {
	switch value {
	case .Store, .Dont_Care:
		return true
	}

	return false
}

@(private)
vertex_format_valid :: proc(format: Vertex_Format) -> bool {
	switch format {
	case .Float32, .Float32x2, .Float32x3, .Float32x4, .Uint8x4_Norm:
		return true
	case .Invalid:
		return false
	}

	return false
}

@(private)
vertex_format_size :: proc(format: Vertex_Format) -> u32 {
	switch format {
	case .Float32:
		return 4
	case .Float32x2:
		return 8
	case .Float32x3:
		return 12
	case .Float32x4:
		return 16
	case .Uint8x4_Norm:
		return 4
	case .Invalid:
		return 0
	}

	return 0
}

@(private)
image_desc_mip_count :: proc(desc: Image_Desc) -> i32 {
	if desc.mip_count <= 0 {
		return 1
	}
	return desc.mip_count
}

@(private)
image_desc_array_count :: proc(desc: Image_Desc) -> i32 {
	if desc.array_count <= 0 {
		return 1
	}
	return desc.array_count
}

@(private)
image_desc_sample_count :: proc(desc: Image_Desc) -> i32 {
	if desc.sample_count <= 0 {
		return 1
	}
	return desc.sample_count
}

@(private)
image_desc_depth :: proc(desc: Image_Desc) -> i32 {
	if desc.depth <= 0 {
		return 1
	}
	return desc.depth
}

@(private)
image_usage_has_dynamic_update :: proc(usage: Image_Usage) -> bool {
	return .Dynamic_Update in usage || .Stream_Update in usage
}

@(private)
image_desc_has_mip_data :: proc(desc: Image_Desc) -> bool {
	for mip_data in desc.mips {
		if range_has_data(mip_data.data) {
			return true
		}
	}

	return false
}

@(private)
image_mip_data :: proc(desc: Image_Desc, mip: int) -> Image_Subresource_Data {
	mip_data := desc.mips[mip]
	if mip == 0 && !range_has_data(mip_data.data) {
		mip_data.data = desc.data
	}

	return mip_data
}

@(private)
image_mip_row_pitch :: proc(mip_data: Image_Subresource_Data, width: u32, pixel_size: int) -> u32 {
	if mip_data.row_pitch > 0 {
		return u32(mip_data.row_pitch)
	}
	return width * u32(pixel_size)
}

@(private)
image_data_required_size :: proc(row_pitch, min_row_pitch, height: int) -> int {
	if height <= 0 {
		return 0
	}
	return row_pitch * (height - 1) + min_row_pitch
}

@(private)
mip_dimension :: proc(value, mip_level: u32) -> u32 {
	result := value >> mip_level
	if result == 0 {
		return 1
	}
	return result
}

@(private)
pixel_format_size :: proc(format: Pixel_Format) -> int {
	switch format {
	case .RGBA8, .BGRA8:
		return 4
	case .RGBA16F:
		return 8
	case .RGBA32F:
		return 16
	case .R32F, .D24S8, .D32F:
		return 4
	case .Invalid:
		return 0
	}

	return 0
}

@(private)
pixel_format_is_color :: proc(format: Pixel_Format) -> bool {
	switch format {
	case .RGBA8, .BGRA8, .RGBA16F, .RGBA32F, .R32F:
		return true
	case .Invalid, .D24S8, .D32F:
		return false
	}

	return false
}

@(private)
pixel_format_is_depth :: proc(format: Pixel_Format) -> bool {
	switch format {
	case .D24S8, .D32F:
		return true
	case .Invalid, .RGBA8, .BGRA8, .RGBA16F, .RGBA32F, .R32F:
		return false
	}

	return false
}
