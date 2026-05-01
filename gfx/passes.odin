package gfx

// begin_pass starts a graphics render pass.
//
// A fully zero-init `Pass_Desc.action` defaults to the framework clear/store
// behavior; see `Pass_Action`. Set only the fields you want to override.
//
// example:
//   gfx.begin_pass(&ctx, {
//       label  = "main",
//       action = {colors = {0 = {clear_value = {r = 0.02, g = 0.02, b = 0.03, a = 1}}}},
//   })
//   // ...apply_pipeline / apply_bindings / draw...
//   gfx.end_pass(&ctx)
begin_pass :: proc(ctx: ^Context, desc: Pass_Desc) -> bool {
	if !require_initialized(ctx, "gfx.begin_pass") {
		return false
	}

	if ctx.in_pass {
		set_validation_error(ctx, "gfx.begin_pass: pass already in progress")
		return false
	}

	resolved := desc
	resolved.action = pass_action_with_defaults(desc.action)

	if !validate_pass_desc(ctx, resolved) {
		return false
	}

	if !barrier_tracker_check_pass_attachments(ctx, resolved, "gfx.begin_pass") {
		return false
	}

	if !backend_begin_pass(ctx, resolved) {
		return false
	}

	barrier_tracker_record_pass_attachments(ctx, resolved)
	capture_pass_attachments(ctx, resolved)
	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
	ctx.current_bindings = {}
	clear_compute_pass_resource_writes(ctx)
	ctx.in_pass = true
	ctx.pass_kind = .Render
	return true
}

// apply_pipeline binds a graphics pipeline inside a render pass.
//
// example:
//   gfx.apply_pipeline(&ctx, pipeline)
apply_pipeline :: proc(ctx: ^Context, pipeline: Pipeline) -> bool {
	if !require_render_pass(ctx, "gfx.apply_pipeline") {
		return false
	}

	if !require_resource(ctx, &ctx.pipeline_pool, u64(pipeline), "gfx.apply_pipeline", "pipeline") {
		return false
	}

	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
	ctx.current_bindings = {}
	if !backend_apply_pipeline(ctx, pipeline) {
		return false
	}

	ctx.current_pipeline = pipeline
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
	return true
}

// begin_compute_pass starts a compute-only pass.
//
// example:
//   gfx.begin_compute_pass(&ctx, {label = "simulate"})
//   gfx.apply_compute_pipeline(&ctx, compute_pipeline)
//   gfx.dispatch(&ctx, 64, 1, 1)
//   gfx.end_compute_pass(&ctx)
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
	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
	ctx.current_bindings = {}
	clear_compute_pass_resource_writes(ctx)
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

	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
	ctx.current_bindings = {}
	if !backend_apply_compute_pipeline(ctx, pipeline) {
		return false
	}

	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = pipeline
	return true
}

// apply_bindings binds transient buffers, views, and samplers for draw or dispatch.
//
// example:
//   bindings: gfx.Bindings
//   bindings.vertex_buffers[0] = {buffer = vertex_buffer}
//   bindings.index_buffer = {buffer = index_buffer}
//   gfx.apply_bindings(&ctx, bindings)
apply_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	if !require_any_pass(ctx, "gfx.apply_bindings") {
		return false
	}

	if !validate_bindings(ctx, bindings) {
		return false
	}

	if !barrier_tracker_check_bindings(ctx, bindings, "gfx.apply_bindings") {
		return false
	}

	if !backend_apply_bindings(ctx, bindings) {
		return false
	}

	barrier_tracker_record_bindings(ctx, bindings)
	ctx.current_bindings = bindings
	return true
}

// apply_uniforms uploads one reflected uniform block to the current pipeline.
//
// example:
//   frame := FrameUniforms{view_proj = view_proj}
//   gfx.apply_uniforms(&ctx, 0, 0, gfx.range_raw(&frame, size_of(frame)))
apply_uniforms :: proc(ctx: ^Context, group: u32, slot: int, data: Range) -> bool {
	if !require_any_pass(ctx, "gfx.apply_uniforms") {
		return false
	}

	if group >= MAX_BINDING_GROUPS {
		set_validation_error(ctx, "gfx.apply_uniforms: group is out of range")
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

	return backend_apply_uniforms(ctx, group, slot, data)
}

// apply_uniform_at binds a `Transient_Slice` as a uniform/constant buffer at a slot.
//
// The caller is expected to have already written `byte_size` bytes through
// `slice.mapped`. `byte_size` must match the reflected uniform block size;
// `slice.size` is the slot's alignment-padded size and is at least `byte_size`.
//
// Composes with the transient allocator (APE-20): allocate a slice from a
// `Transient_Allocator` with `Transient_Usage.Uniform`, write into
// `slice.mapped`, then bind it here. The slot is rebound on every call, so the
// usual draw-time required-uniform check is satisfied.
//
// example:
//   slice, _ := gfx.transient_alloc(allocator, size_of(Frame_Uniforms), .Uniform)
//   (^Frame_Uniforms)(slice.mapped)^ = uniforms
//   gfx.apply_uniform_at(&ctx, 0, 0, slice, size_of(Frame_Uniforms))
apply_uniform_at :: proc(ctx: ^Context, group: u32, slot: int, slice: Transient_Slice, byte_size: int) -> bool {
	if !require_any_pass(ctx, "gfx.apply_uniform_at") {
		return false
	}

	if group >= MAX_BINDING_GROUPS {
		set_validation_error(ctx, "gfx.apply_uniform_at: group is out of range")
		return false
	}
	if slot < 0 || slot >= MAX_UNIFORM_BLOCKS {
		set_validation_error(ctx, "gfx.apply_uniform_at: slot is out of range")
		return false
	}
	if !buffer_valid(slice.buffer) {
		set_validation_error(ctx, "gfx.apply_uniform_at: slice has no backing buffer")
		return false
	}
	if !require_resource(ctx, &ctx.buffer_pool, u64(slice.buffer), "gfx.apply_uniform_at", "transient buffer") {
		return false
	}
	if byte_size <= 0 {
		set_validation_error(ctx, "gfx.apply_uniform_at: byte_size must be positive")
		return false
	}
	if slice.offset < 0 || slice.size <= 0 || byte_size > slice.size {
		set_validation_error(ctx, "gfx.apply_uniform_at: byte_size exceeds slice size")
		return false
	}
	if slice.offset % TRANSIENT_UNIFORM_ALIGNMENT != 0 {
		set_validation_error(ctx, "gfx.apply_uniform_at: slice offset is not aligned to TRANSIENT_UNIFORM_ALIGNMENT")
		return false
	}

	buffer_state := query_buffer_state(ctx, slice.buffer)
	if !buffer_state.valid {
		set_invalid_handle_error(ctx, "gfx.apply_uniform_at: slice buffer handle is invalid")
		return false
	}
	if !(.Uniform in buffer_state.usage) {
		set_validation_error(ctx, "gfx.apply_uniform_at: slice buffer is not uniform-capable")
		return false
	}

	return backend_apply_uniform_at(ctx, group, slot, slice, byte_size)
}

// draw issues a non-indexed or indexed draw depending on the active pipeline.
// When the active pipeline declares an index_type, base_element and num_elements
// are indices; otherwise they are vertices.
//
// example:
//   gfx.draw(&ctx, 0, 3)              // 3 vertices, 1 instance
//   gfx.draw(&ctx, 0, index_count, 4) // indexed, 4 instances
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
//
// example:
//   gfx.apply_compute_pipeline(&ctx, simulate_pipeline)
//   gfx.apply_bindings(&ctx, sim_bindings)
//   gfx.dispatch(&ctx, (count + 63) / 64, 1, 1)
dispatch :: proc(ctx: ^Context, group_count_x: u32 = 1, group_count_y: u32 = 1, group_count_z: u32 = 1) -> bool {
	if !require_compute_pass(ctx, "gfx.dispatch") {
		return false
	}

	if group_count_x == 0 || group_count_y == 0 || group_count_z == 0 {
		set_validation_error(ctx, "gfx.dispatch: thread group counts must be positive")
		return false
	}

	if !validate_compute_dispatch_resource_hazards(ctx) {
		return false
	}

	if !backend_dispatch(ctx, group_count_x, group_count_y, group_count_z) {
		return false
	}

	record_compute_dispatch_writes(ctx)
	return true
}

// draw_indirect issues one or more non-indexed draws sourced from an
// indirect-capable buffer (AAA roadmap item 11).
//
// `indirect_buffer` must have been created with `Buffer_Usage_Flag.Indirect`.
// `offset` is the byte offset of the first `Draw_Indirect_Args` record;
// `draw_count` records are read at `stride` bytes apart. `stride == 0`
// uses `DRAW_INDIRECT_ARGS_STRIDE`.
//
draw_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int = 0, draw_count: u32 = 1, stride: u32 = DRAW_INDIRECT_ARGS_STRIDE) -> bool {
	if !require_render_pass(ctx, "gfx.draw_indirect") {
		return false
	}
	if !validate_indirect_buffer(ctx, "gfx.draw_indirect", indirect_buffer, offset, draw_count, int(stride), DRAW_INDIRECT_ARGS_STRIDE, size_of(Draw_Indirect_Args)) {
		return false
	}

	return backend_draw_indirect(ctx, indirect_buffer, offset, draw_count, stride)
}

// draw_indexed_indirect issues one or more indexed draws sourced from an
// indirect-capable buffer (AAA roadmap item 11).
//
// `indirect_buffer` must have been created with `Buffer_Usage_Flag.Indirect`.
// `offset` is the byte offset of the first `Draw_Indexed_Indirect_Args`
// record; `draw_count` records are read at `stride` bytes apart.
// `stride == 0` uses `DRAW_INDEXED_INDIRECT_ARGS_STRIDE`, which includes
// padding so each record offset stays aligned. The active
// pipeline must declare an `index_type` and a valid index buffer must be
// bound through `apply_bindings`.
draw_indexed_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int = 0, draw_count: u32 = 1, stride: u32 = DRAW_INDEXED_INDIRECT_ARGS_STRIDE) -> bool {
	if !require_render_pass(ctx, "gfx.draw_indexed_indirect") {
		return false
	}
	if !validate_indirect_buffer(ctx, "gfx.draw_indexed_indirect", indirect_buffer, offset, draw_count, int(stride), DRAW_INDEXED_INDIRECT_ARGS_STRIDE, DRAW_INDEXED_INDIRECT_ARGS_SIZE) {
		return false
	}

	return backend_draw_indexed_indirect(ctx, indirect_buffer, offset, draw_count, stride)
}

// dispatch_indirect issues one compute dispatch with thread-group counts
// sourced from an indirect-capable buffer (AAA roadmap item 11).
//
// `indirect_buffer` must have been created with `Buffer_Usage_Flag.Indirect`.
// `offset` is the byte offset of the `Dispatch_Indirect_Args` record.
//
dispatch_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int = 0) -> bool {
	if !require_compute_pass(ctx, "gfx.dispatch_indirect") {
		return false
	}
	if !validate_indirect_buffer(ctx, "gfx.dispatch_indirect", indirect_buffer, offset, 1, DISPATCH_INDIRECT_ARGS_STRIDE, DISPATCH_INDIRECT_ARGS_STRIDE, size_of(Dispatch_Indirect_Args)) {
		return false
	}

	return backend_dispatch_indirect(ctx, indirect_buffer, offset)
}

@(private)
validate_indirect_buffer :: proc(ctx: ^Context, op: string, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: int, default_stride: int, args_size: int) -> bool {
	if !buffer_valid(indirect_buffer) {
		set_validation_errorf(ctx, "%s: indirect buffer handle is invalid", op)
		return false
	}
	if !require_resource(ctx, &ctx.buffer_pool, u64(indirect_buffer), op, "indirect buffer") {
		return false
	}
	if offset < 0 {
		set_validation_errorf(ctx, "%s: offset must be non-negative", op)
		return false
	}
	if offset % INDIRECT_ARGS_OFFSET_ALIGNMENT != 0 {
		set_validation_errorf(ctx, "%s: offset must be aligned to INDIRECT_ARGS_OFFSET_ALIGNMENT (%d bytes)", op, INDIRECT_ARGS_OFFSET_ALIGNMENT)
		return false
	}
	if draw_count == 0 {
		set_validation_errorf(ctx, "%s: draw_count must be positive", op)
		return false
	}
	if draw_count > MAX_INDIRECT_DRAW_COUNT {
		set_validation_errorf(ctx, "%s: draw_count %d exceeds MAX_INDIRECT_DRAW_COUNT (%d)", op, draw_count, MAX_INDIRECT_DRAW_COUNT)
		return false
	}
	effective_stride := stride
	if effective_stride == 0 {
		effective_stride = default_stride
	}
	if effective_stride != default_stride {
		set_validation_errorf(ctx, "%s: stride must be 0 or exactly %d bytes (the canonical args size)", op, default_stride)
		return false
	}
	if draw_count > 1 && effective_stride % INDIRECT_ARGS_OFFSET_ALIGNMENT != 0 {
		set_validation_errorf(ctx, "%s: stride must keep every indirect record aligned to INDIRECT_ARGS_OFFSET_ALIGNMENT (%d bytes)", op, INDIRECT_ARGS_OFFSET_ALIGNMENT)
		return false
	}

	buffer_state := query_buffer_state(ctx, indirect_buffer)
	if !buffer_state.valid {
		set_invalid_handle_errorf(ctx, "%s: indirect buffer handle is invalid", op)
		return false
	}
	if !(.Indirect in buffer_state.usage) {
		set_validation_errorf(ctx, "%s: indirect buffer requires Buffer_Usage_Flag.Indirect", op)
		return false
	}
	required := offset + args_size + effective_stride * (int(draw_count) - 1)
	if required > buffer_state.size {
		set_validation_errorf(ctx, "%s: indirect argument range (%d bytes) exceeds buffer size (%d)", op, required, buffer_state.size)
		return false
	}

	return true
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
	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
	ctx.current_bindings = {}
	clear_compute_pass_resource_writes(ctx)
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
	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
	ctx.current_bindings = {}
	clear_compute_pass_resource_writes(ctx)
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

	barrier_tracker_clear(ctx)
	ctx.frame_index += 1
	return true
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

// pass_action_with_defaults applies the zero-init defaulting rule to a Pass_Action.
//
// `begin_pass` calls this internally before validation and dispatch; it is
// exposed so that callers and tests can inspect the resolved action without
// reaching into private helpers. See the `Pass_Action` doc for the contract.
pass_action_with_defaults :: proc(action: Pass_Action) -> Pass_Action {
	resolved := action

	color_default := Color_Attachment_Action {
		load_action  = .Clear,
		store_action = .Store,
		clear_value  = Color{r = 0, g = 0, b = 0, a = 1},
	}
	for i in 0..<MAX_COLOR_ATTACHMENTS {
		if resolved.colors[i] == (Color_Attachment_Action{}) {
			resolved.colors[i] = color_default
		}
	}

	if resolved.depth == (Depth_Attachment_Action{}) {
		resolved.depth = Depth_Attachment_Action {
			load_action  = .Clear,
			store_action = .Store,
			clear_value  = 1,
		}
	}

	// Stencil's framework default (Clear/Store/0) is bytewise zero, so the
	// zero-init form already matches it; no explicit fill-in is required.
	return resolved
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

	for group_views, group in bindings.views {
		for view, slot in group_views {
			if !view_valid(view) {
				continue
			}
			if !require_resource(ctx, &ctx.view_pool, u64(view), "gfx.apply_bindings", "resource view") {
				return false
			}

			view_state := query_view_state(ctx, view)
			if !view_state.valid {
				set_invalid_handle_errorf(ctx, "gfx.apply_bindings: resource view group %d slot %d handle is invalid", group, slot)
				return false
			}

			switch view_state.kind {
			case .Sampled, .Storage_Image, .Storage_Buffer:
			case .Color_Attachment, .Depth_Stencil_Attachment:
				set_validation_errorf(ctx, "gfx.apply_bindings: resource view group %d slot %d requires a sampled or storage view", group, slot)
				return false
			}
		}
	}

	if !validate_binding_resource_hazards(ctx, bindings) {
		return false
	}

	for group_samplers in bindings.samplers {
		for sampler in group_samplers {
			if !sampler_valid(sampler) {
				continue
			}
			if !require_resource(ctx, &ctx.sampler_pool, u64(sampler), "gfx.apply_bindings", "sampler") {
				return false
			}
		}
	}

	if !validate_bindings_against_pipeline_layout(ctx, bindings, "gfx.apply_bindings") {
		return false
	}

	if !validate_compute_bindings_against_pass_writes(ctx, bindings, "gfx.apply_bindings") {
		return false
	}

	return true
}

@(private)
Binding_Resource_Access_Flags :: struct {
	reads: bool,
	writes: bool,
}

@(private)
clear_compute_pass_resource_writes :: proc(ctx: ^Context) {
	if ctx == nil {
		return
	}

	ctx.compute_pass_resource_writes = {}
	ctx.compute_pass_resource_write_count = 0
}

@(private)
validate_compute_dispatch_resource_hazards :: proc(ctx: ^Context) -> bool {
	if !validate_compute_bindings_against_pass_writes(ctx, ctx.current_bindings, "gfx.dispatch") {
		return false
	}
	if !validate_compute_write_tracking_capacity(ctx, ctx.current_bindings) {
		return false
	}

	return true
}

@(private)
validate_compute_bindings_against_pass_writes :: proc(ctx: ^Context, bindings: Bindings, op: string) -> bool {
	if ctx == nil || ctx.pass_kind != .Compute || ctx.compute_pass_resource_write_count == 0 {
		return true
	}

	for group_views, group in bindings.views {
		for view, slot in group_views {
			if !view_valid(view) {
				continue
			}

			view_state := query_view_state(ctx, view)
			if !view_state.valid {
				continue
			}

			access := current_resource_binding_access(ctx, u32(group), u32(slot), view_state)
			if !access.reads {
				continue
			}

			if compute_pass_written_resource_aliases(ctx, view_state) {
				set_validation_errorf(ctx, "%s: resource view group %d slot %d reads a resource written earlier in the current compute pass", op, group, slot)
				return false
			}
		}
	}

	return true
}

@(private)
validate_compute_write_tracking_capacity :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	if ctx == nil || ctx.pass_kind != .Compute {
		return true
	}

	new_write_count := 0
	for group_views, group in bindings.views {
		for view, slot in group_views {
			if !view_valid(view) {
				continue
			}

			view_state := query_view_state(ctx, view)
			if !view_state.valid {
				continue
			}

			access := current_resource_binding_access(ctx, u32(group), u32(slot), view_state)
			if !access.writes || compute_pass_written_resource_aliases(ctx, view_state) {
				continue
			}

			new_write_count += 1
		}
	}

	if ctx.compute_pass_resource_write_count + new_write_count > MAX_COMPUTE_PASS_RESOURCE_WRITES {
		set_validation_error(ctx, "gfx.dispatch: compute pass resource write tracking capacity exceeded")
		return false
	}

	return true
}

@(private)
record_compute_dispatch_writes :: proc(ctx: ^Context) {
	if ctx == nil || ctx.pass_kind != .Compute {
		return
	}

	for group_views, group in ctx.current_bindings.views {
		for view, slot in group_views {
			if !view_valid(view) {
				continue
			}

			view_state := query_view_state(ctx, view)
			if !view_state.valid {
				continue
			}

			access := current_resource_binding_access(ctx, u32(group), u32(slot), view_state)
			if !access.writes || compute_pass_written_resource_aliases(ctx, view_state) {
				continue
			}

			ctx.compute_pass_resource_writes[ctx.compute_pass_resource_write_count] = view_state
			ctx.compute_pass_resource_write_count += 1
		}
	}
}

@(private)
compute_pass_written_resource_aliases :: proc(ctx: ^Context, view_state: View_State) -> bool {
	if ctx == nil {
		return false
	}

	for i in 0..<ctx.compute_pass_resource_write_count {
		written_state := ctx.compute_pass_resource_writes[i]
		if written_state.valid && view_states_alias_resource(view_state, written_state) {
			return true
		}
	}

	return false
}

@(private)
current_resource_binding_access :: proc(ctx: ^Context, group, slot: u32, view_state: View_State) -> Binding_Resource_Access_Flags {
	entry, entry_ok := current_resource_binding_layout_entry(ctx, group, slot)
	if entry_ok {
		return binding_resource_access_from_layout(entry.resource_view)
	}

	return binding_resource_access_from_view_state(view_state)
}

@(private)
current_resource_binding_layout_entry :: proc(ctx: ^Context, group, slot: u32) -> (Binding_Group_Layout_Entry_Desc, bool) {
	if ctx == nil || ctx.pass_kind != .Compute || !compute_pipeline_valid(ctx.current_compute_pipeline) {
		return {}, false
	}

	pipeline_state, pipeline_state_ok := query_compute_pipeline_state(ctx, ctx.current_compute_pipeline)
	if !pipeline_state_ok || !pipeline_layout_valid(pipeline_state.pipeline_layout) {
		return {}, false
	}

	shader_state, shader_state_ok := query_shader_state(ctx, pipeline_state.shader)
	if !shader_state_ok || !shader_state.has_binding_metadata {
		return {}, false
	}

	pipeline_layout_state, pipeline_layout_state_ok := query_pipeline_layout_state(ctx, pipeline_state.pipeline_layout)
	if !pipeline_layout_state_ok || group >= MAX_BINDING_GROUPS {
		return {}, false
	}

	group_layout := pipeline_layout_state.desc.group_layouts[group]
	if !binding_group_layout_valid(group_layout) {
		return {}, false
	}

	group_layout_state, group_layout_state_ok := query_binding_group_layout_state(ctx, group_layout)
	if !group_layout_state_ok {
		return {}, false
	}

	return binding_group_layout_find_entry(group_layout_state.desc, .Resource_View, slot)
}

@(private)
binding_resource_access_from_layout :: proc(desc: Binding_Group_Resource_View_Layout_Desc) -> Binding_Resource_Access_Flags {
	if desc.view_kind == .Sampled {
		return {reads = true}
	}

	switch desc.access {
	case .Read:
		return {reads = true}
	case .Write:
		return {writes = true}
	case .Read_Write, .Unknown:
		return {reads = true, writes = true}
	}

	return {reads = true, writes = true}
}

@(private)
binding_resource_access_from_view_state :: proc(view_state: View_State) -> Binding_Resource_Access_Flags {
	return {
		reads = view_state_reads_resource(view_state),
		writes = view_state_writes_resource(view_state),
	}
}

@(private)
validate_bindings_against_pipeline_layout :: proc(ctx: ^Context, bindings: Bindings, op: string) -> bool {
	if !bindings_have_shader_resources(bindings) {
		return true
	}

	shader_state, shader_state_ok := current_binding_group_shader_state(ctx, op)
	if !shader_state_ok {
		return false
	}
	if !shader_state.has_binding_metadata {
		return true
	}

	pipeline_layout, pipeline_layout_ok := current_pipeline_layout(ctx, op)
	if !pipeline_layout_ok {
		return false
	}
	if !pipeline_layout_valid(pipeline_layout) {
		set_validation_errorf(ctx, "%s: current pipeline has no pipeline_layout", op)
		return false
	}

	pipeline_layout_state, pipeline_layout_state_ok := query_pipeline_layout_state(ctx, pipeline_layout)
	if !pipeline_layout_state_ok {
		set_validation_errorf(ctx, "%s: current pipeline_layout state is unavailable", op)
		return false
	}

	for group_views, group in bindings.views {
		for view, slot in group_views {
			if !view_valid(view) {
				continue
			}

			group_layout, group_layout_ok := pipeline_layout_group_desc(ctx, pipeline_layout_state.desc, u32(group), op)
			if !group_layout_ok {
				return false
			}

			entry, entry_ok := binding_group_layout_find_entry(group_layout, .Resource_View, u32(slot))
			if !entry_ok {
				set_validation_errorf(ctx, "%s: resource view group %d slot %d is not declared by current pipeline_layout", op, group, slot)
				return false
			}
			if !validate_transient_binding_view(ctx, entry, view, u32(group), op) {
				return false
			}
		}
	}

	for group_samplers, group in bindings.samplers {
		for sampler, slot in group_samplers {
			if !sampler_valid(sampler) {
				continue
			}

			group_layout, group_layout_ok := pipeline_layout_group_desc(ctx, pipeline_layout_state.desc, u32(group), op)
			if !group_layout_ok {
				return false
			}

			_, entry_ok := binding_group_layout_find_entry(group_layout, .Sampler, u32(slot))
			if !entry_ok {
				set_validation_errorf(ctx, "%s: sampler group %d slot %d is not declared by current pipeline_layout", op, group, slot)
				return false
			}
		}
	}

	return true
}

@(private)
validate_transient_binding_view :: proc(ctx: ^Context, entry: Binding_Group_Layout_Entry_Desc, view: View, group: u32, op: string) -> bool {
	view_state := query_view_state(ctx, view)
	if !view_state.valid {
		set_invalid_handle_errorf(ctx, "%s: resource view group %d slot %d handle is invalid", op, group, entry.slot)
		return false
	}
	if view_state.kind != entry.resource_view.view_kind {
		set_validation_errorf(
			ctx,
			"%s: resource view group %d slot %d requires a %s view",
			op,
			group,
			entry.slot,
			view_kind_name(entry.resource_view.view_kind),
		)
		return false
	}
	if entry.resource_view.view_kind == .Storage_Image &&
	   entry.resource_view.storage_image_format != .Invalid &&
	   view_state.format != entry.resource_view.storage_image_format {
		set_validation_errorf(ctx, "%s: storage image group %d slot %d format does not match pipeline_layout", op, group, entry.slot)
		return false
	}
	if entry.resource_view.view_kind == .Storage_Buffer &&
	   entry.resource_view.storage_buffer_stride != 0 &&
	   u32(view_state.storage_stride) != entry.resource_view.storage_buffer_stride {
		set_validation_errorf(ctx, "%s: storage buffer group %d slot %d stride does not match pipeline_layout", op, group, entry.slot)
		return false
	}

	return true
}

@(private)
bindings_have_shader_resources :: proc(bindings: Bindings) -> bool {
	for group_views in bindings.views {
		for view in group_views {
			if view_valid(view) {
				return true
			}
		}
	}
	for group_samplers in bindings.samplers {
		for sampler in group_samplers {
			if sampler_valid(sampler) {
				return true
			}
		}
	}

	return false
}

@(private)
validate_binding_resource_hazards :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	for group_views, group in bindings.views {
		for view, slot in group_views {
			if !view_valid(view) {
				continue
			}

			view_state := query_view_state(ctx, view)
			if !view_state.valid {
				continue
			}

			if ctx.pass_kind == .Render && view_state_aliases_active_pass_attachment(ctx, view_state) {
				set_validation_errorf(ctx, "gfx.apply_bindings: resource view group %d slot %d aliases an active pass attachment", group, slot)
				return false
			}

			current_writes := view_state_writes_resource(view_state)
			current_reads := view_state_reads_resource(view_state)
			for other_group_views, other_group in bindings.views {
				for other_view, other_slot in other_group_views {
					if other_group > group || (other_group == group && other_slot >= slot) || !view_valid(other_view) {
						continue
					}

					other_state := query_view_state(ctx, other_view)
					if !other_state.valid || !view_states_alias_resource(view_state, other_state) {
						continue
					}

					other_writes := view_state_writes_resource(other_state)
					other_reads := view_state_reads_resource(other_state)
					if current_writes && other_writes {
						set_validation_errorf(ctx, "gfx.apply_bindings: resource view group %d slot %d and group %d slot %d write the same resource", other_group, other_slot, group, slot)
						return false
					}
					if current_reads && other_writes {
						set_validation_errorf(ctx, "gfx.apply_bindings: resource view group %d slot %d reads a resource written by group %d slot %d", group, slot, other_group, other_slot)
						return false
					}
					if current_writes && other_reads {
						set_validation_errorf(ctx, "gfx.apply_bindings: resource view group %d slot %d writes a resource read by group %d slot %d", group, slot, other_group, other_slot)
						return false
					}
				}
			}
		}
	}

	return true
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
