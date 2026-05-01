package gfx

@(private)
buffer_blocked_from_destroy :: proc(ctx: ^Context, buffer: Buffer) -> string {
	if buffer_referenced_by_live_view(ctx, buffer) {
		return "gfx.destroy_buffer: buffer is still referenced by a view"
	}
	if buffer_currently_bound(ctx, buffer) {
		return "gfx.destroy_buffer: buffer is currently bound"
	}

	return ""
}

@(private)
image_blocked_from_destroy :: proc(ctx: ^Context, image: Image) -> string {
	if image_referenced_by_live_view(ctx, image) {
		return "gfx.destroy_image: image is still referenced by a view"
	}

	return ""
}

@(private)
view_blocked_from_destroy :: proc(ctx: ^Context, view: View) -> string {
	if view_currently_bound_or_attached(ctx, view) {
		return "gfx.destroy_view: view is currently bound or attached"
	}
	if view_used_by_binding_group(ctx, view) {
		return "gfx.destroy_view: view is still used by a binding group"
	}

	return ""
}

@(private)
sampler_blocked_from_destroy :: proc(ctx: ^Context, sampler: Sampler) -> string {
	if sampler_currently_bound(ctx, sampler) {
		return "gfx.destroy_sampler: sampler is currently bound"
	}
	if sampler_used_by_binding_group(ctx, sampler) {
		return "gfx.destroy_sampler: sampler is still used by a binding group"
	}

	return ""
}

@(private)
shader_blocked_from_destroy :: proc(ctx: ^Context, shader: Shader) -> string {
	if shader_used_by_pipeline(ctx, shader) {
		return "gfx.destroy_shader: shader is still used by a pipeline"
	}

	return ""
}

@(private)
buffer_referenced_by_live_view :: proc(ctx: ^Context, buffer: Buffer) -> bool {
	if ctx == nil {
		return false
	}

	for alive, slot in ctx.view_pool.live {
		if !alive {
			continue
		}

		view := live_view_handle(ctx, slot)
		view_state := query_view_state(ctx, view)
		if view_state.valid && view_state.buffer == buffer {
			return true
		}
	}

	return false
}

@(private)
image_referenced_by_live_view :: proc(ctx: ^Context, image: Image) -> bool {
	if ctx == nil {
		return false
	}

	for alive, slot in ctx.view_pool.live {
		if !alive {
			continue
		}

		view := live_view_handle(ctx, slot)
		view_state := query_view_state(ctx, view)
		if view_state.valid && view_state.image == image {
			return true
		}
	}

	return false
}

@(private)
live_view_handle :: proc(ctx: ^Context, slot: int) -> View {
	return View(encode_resource_id(ctx.context_id, ctx.view_pool.generations[slot], u32(slot)))
}

@(private)
buffer_currently_bound :: proc(ctx: ^Context, buffer: Buffer) -> bool {
	if ctx == nil {
		return false
	}

	for binding in ctx.current_bindings.vertex_buffers {
		if binding.buffer == buffer {
			return true
		}
	}
	if ctx.current_bindings.index_buffer.buffer == buffer {
		return true
	}

	for group_views in ctx.current_bindings.views {
		for view in group_views {
			if !view_valid(view) {
				continue
			}
			view_state := query_view_state(ctx, view)
			if view_state.valid && view_state.buffer == buffer {
				return true
			}
		}
	}

	return false
}

@(private)
view_currently_bound_or_attached :: proc(ctx: ^Context, view: View) -> bool {
	if ctx == nil {
		return false
	}

	for group_views in ctx.current_bindings.views {
		for bound_view in group_views {
			if bound_view == view {
				return true
			}
		}
	}

	for attachment in ctx.pass_color_attachments {
		if attachment == view {
			return true
		}
	}
	if ctx.pass_depth_stencil_attachment == view {
		return true
	}

	return false
}

@(private)
sampler_currently_bound :: proc(ctx: ^Context, sampler: Sampler) -> bool {
	if ctx == nil {
		return false
	}

	for group_samplers in ctx.current_bindings.samplers {
		for bound_sampler in group_samplers {
			if bound_sampler == sampler {
				return true
			}
		}
	}

	return false
}

@(private)
view_used_by_binding_group :: proc(ctx: ^Context, view: View) -> bool {
	if ctx == nil || ctx.binding_group_states == nil {
		return false
	}

	for _, group_state in ctx.binding_group_states {
		if !group_state.valid {
			continue
		}

		for group_view in group_state.desc.views {
			if group_view == view {
				return true
			}
		}
		for array in group_state.desc.arrays {
			if !array.active || array.kind != .Resource_View {
				continue
			}
			for group_view in array.views {
				if group_view == view {
					return true
				}
			}
		}
	}

	return false
}

@(private)
sampler_used_by_binding_group :: proc(ctx: ^Context, sampler: Sampler) -> bool {
	if ctx == nil || ctx.binding_group_states == nil {
		return false
	}

	for _, group_state in ctx.binding_group_states {
		if !group_state.valid {
			continue
		}

		for group_sampler in group_state.desc.samplers {
			if group_sampler == sampler {
				return true
			}
		}
		for array in group_state.desc.arrays {
			if !array.active || array.kind != .Sampler {
				continue
			}
			for group_sampler in array.samplers {
				if group_sampler == sampler {
					return true
				}
			}
		}
	}

	return false
}

@(private)
shader_used_by_pipeline :: proc(ctx: ^Context, shader: Shader) -> bool {
	if ctx == nil {
		return false
	}

	if ctx.pipeline_states != nil {
		for _, pipeline_state in ctx.pipeline_states {
			if pipeline_state.valid && pipeline_state.shader == shader {
				return true
			}
		}
	}
	if ctx.compute_pipeline_states != nil {
		for _, pipeline_state in ctx.compute_pipeline_states {
			if pipeline_state.valid && pipeline_state.shader == shader {
				return true
			}
		}
	}

	return false
}
