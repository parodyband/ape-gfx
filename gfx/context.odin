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
			"gfx.shutdown: leaked resources: buffers=%d images=%d views=%d samplers=%d shaders=%d pipelines=%d compute_pipelines=%d binding_group_layouts=%d pipeline_layouts=%d binding_groups=%d transient_allocators=%d",
			ctx.buffer_pool.live_count,
			ctx.image_pool.live_count,
			ctx.view_pool.live_count,
			ctx.sampler_pool.live_count,
			ctx.shader_pool.live_count,
			ctx.pipeline_pool.live_count,
			ctx.compute_pipeline_pool.live_count,
			ctx.binding_group_layout_pool.live_count,
			ctx.pipeline_layout_pool.live_count,
			ctx.binding_group_pool.live_count,
			ctx.transient_allocator_pool.live_count,
		)
	}

	transient_unregister_context(ctx)
	backend_shutdown(ctx)
	delete_resource_pools(ctx)
	ctx.initialized = false
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
		max_binding_groups = MAX_BINDING_GROUPS,
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
	       ctx.compute_pipeline_pool.live_count +
	       ctx.binding_group_layout_pool.live_count +
	       ctx.pipeline_layout_pool.live_count +
	       ctx.binding_group_pool.live_count +
	       ctx.transient_allocator_pool.live_count
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
	delete_resource_pool(&ctx.binding_group_layout_pool)
	delete_resource_pool(&ctx.pipeline_layout_pool)
	delete_resource_pool(&ctx.binding_group_pool)
	delete_resource_pool(&ctx.transient_allocator_pool)
	if ctx.transient_allocator_states != nil {
		delete(ctx.transient_allocator_states)
		ctx.transient_allocator_states = nil
	}
	if ctx.shader_states != nil {
		delete(ctx.shader_states)
		ctx.shader_states = nil
	}
	if ctx.pipeline_states != nil {
		delete(ctx.pipeline_states)
		ctx.pipeline_states = nil
	}
	if ctx.compute_pipeline_states != nil {
		delete(ctx.compute_pipeline_states)
		ctx.compute_pipeline_states = nil
	}
	if ctx.binding_group_layout_states != nil {
		delete(ctx.binding_group_layout_states)
		ctx.binding_group_layout_states = nil
	}
	if ctx.pipeline_layout_states != nil {
		delete(ctx.pipeline_layout_states)
		ctx.pipeline_layout_states = nil
	}
	if ctx.binding_group_states != nil {
		delete(ctx.binding_group_states)
		ctx.binding_group_states = nil
	}
	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
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
