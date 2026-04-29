package gfx

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
	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
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

	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
	if !backend_apply_pipeline(ctx, pipeline) {
		return false
	}

	ctx.current_pipeline = pipeline
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
	return true
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
	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
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
	if !backend_apply_compute_pipeline(ctx, pipeline) {
		return false
	}

	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = pipeline
	return true
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
	ctx.current_pipeline = Pipeline_Invalid
	ctx.current_compute_pipeline = Compute_Pipeline_Invalid
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
