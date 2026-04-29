package gfx

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

	track_pipeline_state(ctx, handle, desc)
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
	untrack_pipeline_state(ctx, pipeline)
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

	track_compute_pipeline_state(ctx, handle, desc)
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
	untrack_compute_pipeline_state(ctx, pipeline)
	release_resource_id(&ctx.compute_pipeline_pool, u64(pipeline))
}

@(private)
track_pipeline_state :: proc(ctx: ^Context, pipeline: Pipeline, desc: Pipeline_Desc) {
	if ctx == nil || !pipeline_valid(pipeline) {
		return
	}
	if ctx.pipeline_states == nil {
		ctx.pipeline_states = make(map[Pipeline]Pipeline_State)
	}

	ctx.pipeline_states[pipeline] = {
		valid = true,
		shader = desc.shader,
		pipeline_layout = desc.pipeline_layout,
	}
}

@(private)
untrack_pipeline_state :: proc(ctx: ^Context, pipeline: Pipeline) {
	if ctx == nil {
		return
	}
	if ctx.pipeline_states != nil {
		delete_key(&ctx.pipeline_states, pipeline)
	}
	if ctx.current_pipeline == pipeline {
		ctx.current_pipeline = Pipeline_Invalid
	}
}

@(private)
query_pipeline_state :: proc(ctx: ^Context, pipeline: Pipeline) -> (Pipeline_State, bool) {
	if ctx == nil || ctx.pipeline_states == nil {
		return {}, false
	}

	state, ok := ctx.pipeline_states[pipeline]
	return state, ok && state.valid
}

@(private)
track_compute_pipeline_state :: proc(ctx: ^Context, pipeline: Compute_Pipeline, desc: Compute_Pipeline_Desc) {
	if ctx == nil || !compute_pipeline_valid(pipeline) {
		return
	}
	if ctx.compute_pipeline_states == nil {
		ctx.compute_pipeline_states = make(map[Compute_Pipeline]Compute_Pipeline_State)
	}

	ctx.compute_pipeline_states[pipeline] = {
		valid = true,
		shader = desc.shader,
		pipeline_layout = desc.pipeline_layout,
	}
}

@(private)
untrack_compute_pipeline_state :: proc(ctx: ^Context, pipeline: Compute_Pipeline) {
	if ctx == nil {
		return
	}
	if ctx.compute_pipeline_states != nil {
		delete_key(&ctx.compute_pipeline_states, pipeline)
	}
	if ctx.current_compute_pipeline == pipeline {
		ctx.current_compute_pipeline = Compute_Pipeline_Invalid
	}
}

@(private)
query_compute_pipeline_state :: proc(ctx: ^Context, pipeline: Compute_Pipeline) -> (Compute_Pipeline_State, bool) {
	if ctx == nil || ctx.compute_pipeline_states == nil {
		return {}, false
	}

	state, ok := ctx.compute_pipeline_states[pipeline]
	return state, ok && state.valid
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

	if !validate_pipeline_layout_for_shader(ctx, desc.pipeline_layout, shader_state, "gfx.create_pipeline") {
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

	return validate_pipeline_layout_for_shader(ctx, desc.pipeline_layout, shader_state, "gfx.create_compute_pipeline")
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
