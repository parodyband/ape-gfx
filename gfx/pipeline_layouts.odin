package gfx

// create_pipeline_layout creates an immutable layout composed from generated binding group layouts.
create_pipeline_layout :: proc(ctx: ^Context, desc: Pipeline_Layout_Desc) -> (Pipeline_Layout, bool) {
	if !require_initialized(ctx, "gfx.create_pipeline_layout") {
		return Pipeline_Layout_Invalid, false
	}
	if !validate_pipeline_layout_desc(ctx, desc) {
		return Pipeline_Layout_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.pipeline_layout_pool, "gfx.create_pipeline_layout")
	if handle_id == 0 {
		return Pipeline_Layout_Invalid, false
	}

	handle := Pipeline_Layout(handle_id)
	if ctx.pipeline_layout_states == nil {
		ctx.pipeline_layout_states = make(map[Pipeline_Layout]Pipeline_Layout_State)
	}
	ctx.pipeline_layout_states[handle] = {
		valid = true,
		desc = desc,
	}

	return handle, true
}

// destroy_pipeline_layout releases a live pipeline layout handle.
destroy_pipeline_layout :: proc(ctx: ^Context, layout: Pipeline_Layout) {
	if !require_initialized(ctx, "gfx.destroy_pipeline_layout") {
		return
	}
	if !require_resource(ctx, &ctx.pipeline_layout_pool, u64(layout), "gfx.destroy_pipeline_layout", "pipeline layout") {
		return
	}
	if pipeline_layout_in_use(ctx, layout) {
		set_validation_error(ctx, "gfx.destroy_pipeline_layout: layout is still used by a pipeline")
		return
	}

	if ctx.pipeline_layout_states != nil {
		delete_key(&ctx.pipeline_layout_states, layout)
	}
	release_resource_id(&ctx.pipeline_layout_pool, u64(layout))
}

// validate_pipeline_layout_desc validates a pipeline layout before creation.
validate_pipeline_layout_desc :: proc(ctx: ^Context, desc: Pipeline_Layout_Desc) -> bool {
	if !require_initialized(ctx, "gfx.validate_pipeline_layout_desc") {
		return false
	}

	for group_layout, group in desc.group_layouts {
		if !binding_group_layout_valid(group_layout) {
			continue
		}
		if !require_resource(ctx, &ctx.binding_group_layout_pool, u64(group_layout), "gfx.validate_pipeline_layout_desc", "binding group layout") {
			return false
		}

		layout_state, layout_ok := query_binding_group_layout_state(ctx, group_layout)
		if !layout_ok {
			set_validation_errorf(ctx, "gfx.validate_pipeline_layout_desc: binding group layout state at group %d is unavailable", group)
			return false
		}
		if layout_state.desc.group != u32(group) {
			set_validation_errorf(
				ctx,
				"gfx.validate_pipeline_layout_desc: group layout at slot %d declares group %d",
				group,
				layout_state.desc.group,
			)
			return false
		}
	}

	return true
}

@(private)
query_pipeline_layout_state :: proc(ctx: ^Context, layout: Pipeline_Layout) -> (Pipeline_Layout_State, bool) {
	if ctx == nil || ctx.pipeline_layout_states == nil {
		return {}, false
	}

	state, ok := ctx.pipeline_layout_states[layout]
	return state, ok && state.valid
}

@(private)
pipeline_layout_in_use :: proc(ctx: ^Context, layout: Pipeline_Layout) -> bool {
	if ctx == nil {
		return false
	}

	if ctx.pipeline_states != nil {
		for _, pipeline_state in ctx.pipeline_states {
			if pipeline_state.valid && pipeline_state.pipeline_layout == layout {
				return true
			}
		}
	}
	if ctx.compute_pipeline_states != nil {
		for _, pipeline_state in ctx.compute_pipeline_states {
			if pipeline_state.valid && pipeline_state.pipeline_layout == layout {
				return true
			}
		}
	}

	return false
}

@(private)
binding_group_layout_used_by_pipeline_layout :: proc(ctx: ^Context, group_layout: Binding_Group_Layout) -> bool {
	if ctx == nil || ctx.pipeline_layout_states == nil {
		return false
	}

	for _, pipeline_layout_state in ctx.pipeline_layout_states {
		if !pipeline_layout_state.valid {
			continue
		}
		for layout in pipeline_layout_state.desc.group_layouts {
			if layout == group_layout {
				return true
			}
		}
	}

	return false
}

@(private)
validate_pipeline_layout_for_shader :: proc(ctx: ^Context, layout: Pipeline_Layout, shader_state: Shader_State, op: string) -> bool {
	if shader_state.has_binding_metadata {
		if !pipeline_layout_valid(layout) {
			set_validation_errorf(ctx, "%s: shader binding metadata requires pipeline_layout", op)
			return false
		}
	} else {
		if pipeline_layout_valid(layout) {
			set_validation_errorf(ctx, "%s: pipeline_layout requires shader binding metadata", op)
			return false
		}
		return true
	}

	if !require_resource(ctx, &ctx.pipeline_layout_pool, u64(layout), op, "pipeline layout") {
		return false
	}

	pipeline_layout_state, layout_ok := query_pipeline_layout_state(ctx, layout)
	if !layout_ok {
		set_validation_errorf(ctx, "%s: pipeline layout state is unavailable", op)
		return false
	}

	for binding in shader_state.bindings {
		if !binding.active {
			continue
		}
		group_layout_desc, group_layout_ok := pipeline_layout_group_desc(ctx, pipeline_layout_state.desc, binding.group, op)
		if !group_layout_ok {
			return false
		}

		entry, entry_ok := binding_group_layout_find_entry(group_layout_desc, binding.kind, binding.slot)
		if !entry_ok || !(binding.stage in entry.stages) {
			set_validation_errorf(
				ctx,
				"%s: pipeline_layout is missing %s %s group %d slot %d",
				op,
				shader_stage_name(binding.stage),
				shader_binding_kind_name(binding.kind),
				binding.group,
				binding.slot,
			)
			return false
		}
		if entry.name != binding.name {
			set_validation_errorf(
				ctx,
				"%s: pipeline_layout %s group %d slot %d name does not match shader reflection",
				op,
				shader_binding_kind_name(binding.kind),
				binding.group,
				binding.slot,
			)
			return false
		}
		if !binding_group_entry_payload_matches_shader(ctx, entry, binding, op) {
			return false
		}

		if pipeline_layout_requires_native_bindings(ctx.backend) &&
		   !binding_group_layout_has_native_binding(group_layout_desc, ctx.backend, binding) {
			set_validation_errorf(
				ctx,
				"%s: pipeline_layout is missing native %s %s group %d slot %d",
				op,
				backend_name(ctx.backend),
				shader_binding_kind_name(binding.kind),
				binding.group,
				binding.slot,
			)
			return false
		}
	}

	for group_layout in pipeline_layout_state.desc.group_layouts {
		if !binding_group_layout_valid(group_layout) {
			continue
		}
		layout_state, layout_ok := query_binding_group_layout_state(ctx, group_layout)
		if !layout_ok {
			set_validation_errorf(ctx, "%s: pipeline layout binding group state is unavailable", op)
			return false
		}
		if !validate_binding_group_pipeline_compatibility(ctx, shader_state, layout_state.desc, op) {
			return false
		}
	}

	return true
}

@(private)
pipeline_layout_group_desc :: proc(
	ctx: ^Context,
	pipeline_layout: Pipeline_Layout_Desc,
	group: u32,
	op: string,
) -> (Binding_Group_Layout_Desc, bool) {
	if group >= MAX_BINDING_GROUPS {
		set_validation_errorf(ctx, "%s: shader binding group %d is out of range", op, group)
		return {}, false
	}

	group_layout := pipeline_layout.group_layouts[group]
	if !binding_group_layout_valid(group_layout) {
		set_validation_errorf(ctx, "%s: pipeline_layout is missing binding group %d", op, group)
		return {}, false
	}

	layout_state, layout_ok := query_binding_group_layout_state(ctx, group_layout)
	if !layout_ok {
		set_validation_errorf(ctx, "%s: pipeline_layout binding group %d state is unavailable", op, group)
		return {}, false
	}

	return layout_state.desc, true
}

@(private)
current_pipeline_layout :: proc(ctx: ^Context, op: string) -> (Pipeline_Layout, bool) {
	if ctx == nil {
		return Pipeline_Layout_Invalid, false
	}

	switch ctx.pass_kind {
	case .Render:
		if !pipeline_valid(ctx.current_pipeline) {
			set_validation_errorf(ctx, "%s: requires an applied graphics pipeline", op)
			return Pipeline_Layout_Invalid, false
		}
		pipeline_state, pipeline_state_ok := query_pipeline_state(ctx, ctx.current_pipeline)
		if !pipeline_state_ok {
			set_validation_errorf(ctx, "%s: current graphics pipeline state is unavailable", op)
			return Pipeline_Layout_Invalid, false
		}
		return pipeline_state.pipeline_layout, true
	case .Compute:
		if !compute_pipeline_valid(ctx.current_compute_pipeline) {
			set_validation_errorf(ctx, "%s: requires an applied compute pipeline", op)
			return Pipeline_Layout_Invalid, false
		}
		pipeline_state, pipeline_state_ok := query_compute_pipeline_state(ctx, ctx.current_compute_pipeline)
		if !pipeline_state_ok {
			set_validation_errorf(ctx, "%s: current compute pipeline state is unavailable", op)
			return Pipeline_Layout_Invalid, false
		}
		return pipeline_state.pipeline_layout, true
	case .None:
	}

	set_validation_errorf(ctx, "%s: no pass is active", op)
	return Pipeline_Layout_Invalid, false
}

@(private)
pipeline_layout_requires_native_bindings :: proc(backend: Backend) -> bool {
	switch backend {
	case .D3D11, .Vulkan:
		return true
	case .Auto, .Null:
		return false
	}

	return false
}
