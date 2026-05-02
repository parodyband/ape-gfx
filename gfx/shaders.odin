package gfx

// create_shader creates backend shader objects from compiled shader bytecode.
// On failure, the returned handle is Shader_Invalid and last_error explains why.
//
// example:
//   pkg, _ := shader_assets.load("build/shaders/triangle.ashader")
//   desc, _ := shader_assets.shader_desc(&pkg, .D3D12_DXIL, "triangle")
//   shader, ok := gfx.create_shader(&ctx, desc)
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
	if message := shader_blocked_from_destroy(ctx, shader); message != "" {
		set_validation_error(ctx, message)
		return
	}

	backend_destroy_shader(ctx, shader)
	untrack_shader_state(ctx, shader)
	release_resource_id(&ctx.shader_pool, u64(shader))
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
			binding_first, binding_count := shader_binding_slot_range(binding)
			other_first, other_count := shader_binding_slot_range(other)
			if other.stage == binding.stage &&
			   other.kind == binding.kind &&
			   other.group == binding.group &&
			   binding_first < other_first + other_count &&
			   other_first < binding_first + binding_count {
				set_validation_errorf(
					ctx,
					"gfx.create_shader: overlapping %s binding metadata for %s group %d slot range [%d, %d)",
					shader_binding_kind_name(binding.kind),
					shader_stage_name(binding.stage),
					binding.group,
					binding_first,
					binding_first + binding_count,
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
	if binding.unsized {
		set_validation_errorf(
			ctx,
			"gfx.create_shader: binding metadata index %d declares an unsized array; runtime / bindless arrays use Binding_Heap (item 28 ships fixed arrays only)",
			index,
		)
		return false
	}
	if binding.array_count > 1 {
		switch binding.kind {
		case .Resource_View, .Sampler:
		case .Uniform_Block:
			set_validation_errorf(ctx, "gfx.create_shader: binding metadata index %d uniform blocks do not support fixed arrays", index)
			return false
		}
	}
	if binding.group >= MAX_BINDING_GROUPS {
		set_validation_errorf(ctx, "gfx.create_shader: binding group %d is out of range", binding.group)
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
		slot_count := shader_binding_array_count(binding)
		if binding.slot >= MAX_RESOURCE_VIEWS || u64(binding.slot) + u64(slot_count) > u64(MAX_RESOURCE_VIEWS) {
			set_validation_errorf(ctx, "gfx.create_shader: resource view binding slot %d is out of range", binding.slot)
			return false
		}
		if binding.native_slot >= MAX_RESOURCE_VIEWS || u64(binding.native_slot) + u64(slot_count) > u64(MAX_RESOURCE_VIEWS) {
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
		slot_count := shader_binding_array_count(binding)
		if binding.slot >= MAX_SAMPLERS || u64(binding.slot) + u64(slot_count) > u64(MAX_SAMPLERS) {
			set_validation_errorf(ctx, "gfx.create_shader: sampler binding slot %d is out of range", binding.slot)
			return false
		}
		if binding.native_slot >= MAX_SAMPLERS || u64(binding.native_slot) + u64(slot_count) > u64(MAX_SAMPLERS) {
			set_validation_errorf(ctx, "gfx.create_shader: native sampler binding slot %d is out of range", binding.native_slot)
			return false
		}
	}

	return true
}

@(private)
shader_binding_array_count :: proc(binding: Shader_Binding_Desc) -> u32 {
	if binding.array_count > 1 {
		return binding.array_count
	}
	return 1
}

@(private)
shader_binding_slot_range :: proc(binding: Shader_Binding_Desc) -> (u32, u32) {
	return binding.slot, shader_binding_array_count(binding)
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
		case .Mesh:
			state.has_mesh = true
		case .Amplification:
			state.has_amplification = true
		}
	}

	for input, index in desc.vertex_inputs {
		state.vertex_inputs[index] = input
	}
	for binding, index in desc.bindings {
		state.bindings[index] = binding
	}

	return state
}

@(private)
shader_stage_valid :: proc(value: Shader_Stage) -> bool {
	switch value {
	case .Vertex, .Fragment, .Compute, .Mesh, .Amplification:
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
	case .Mesh:
		return "mesh"
	case .Amplification:
		return "amplification"
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
	case .RGBA8, .BGRA8, .RGBA16F, .BC1_RGBA, .BC3_RGBA, .BC5_RG, .BC7_RGBA, .D24S8, .D32F:
		return false
	}

	return false
}
