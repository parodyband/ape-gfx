package gfx

// create_binding_group_layout creates an immutable generated binding group layout handle.
create_binding_group_layout :: proc(ctx: ^Context, desc: Binding_Group_Layout_Desc) -> (Binding_Group_Layout, bool) {
	if !require_initialized(ctx, "gfx.create_binding_group_layout") {
		return Binding_Group_Layout_Invalid, false
	}
	if !validate_binding_group_layout_desc(ctx, desc) {
		return Binding_Group_Layout_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.binding_group_layout_pool, "gfx.create_binding_group_layout")
	if handle_id == 0 {
		return Binding_Group_Layout_Invalid, false
	}

	handle := Binding_Group_Layout(handle_id)
	if ctx.binding_group_layout_states == nil {
		ctx.binding_group_layout_states = make(map[Binding_Group_Layout]Binding_Group_Layout_State)
	}
	ctx.binding_group_layout_states[handle] = {
		valid = true,
		desc = desc,
	}

	return handle, true
}

// destroy_binding_group_layout releases a live binding group layout handle.
destroy_binding_group_layout :: proc(ctx: ^Context, layout: Binding_Group_Layout) {
	if !require_initialized(ctx, "gfx.destroy_binding_group_layout") {
		return
	}
	if !require_resource(ctx, &ctx.binding_group_layout_pool, u64(layout), "gfx.destroy_binding_group_layout", "binding group layout") {
		return
	}
	if binding_group_layout_in_use(ctx, layout) {
		set_validation_error(ctx, "gfx.destroy_binding_group_layout: layout is still used by a binding group")
		return
	}

	if ctx.binding_group_layout_states != nil {
		delete_key(&ctx.binding_group_layout_states, layout)
	}
	release_resource_id(&ctx.binding_group_layout_pool, u64(layout))
}

// create_binding_group creates an immutable binding group from a generated layout handle and resource handles.
create_binding_group :: proc(ctx: ^Context, desc: Binding_Group_Desc) -> (Binding_Group, bool) {
	if !require_initialized(ctx, "gfx.create_binding_group") {
		return Binding_Group_Invalid, false
	}
	if !require_resource(ctx, &ctx.binding_group_layout_pool, u64(desc.layout), "gfx.create_binding_group", "binding group layout") {
		return Binding_Group_Invalid, false
	}

	layout_state, layout_ok := query_binding_group_layout_state(ctx, desc.layout)
	if !layout_ok {
		set_validation_error(ctx, "gfx.create_binding_group: binding group layout state is unavailable")
		return Binding_Group_Invalid, false
	}
	if !validate_binding_group_desc(ctx, layout_state.desc, desc, "gfx.create_binding_group") {
		return Binding_Group_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.binding_group_pool, "gfx.create_binding_group")
	if handle_id == 0 {
		return Binding_Group_Invalid, false
	}

	handle := Binding_Group(handle_id)
	if ctx.binding_group_states == nil {
		ctx.binding_group_states = make(map[Binding_Group]Binding_Group_State)
	}
	ctx.binding_group_states[handle] = {
		valid = true,
		layout = desc.layout,
		desc = desc,
	}

	return handle, true
}

// destroy_binding_group releases a live binding group handle.
destroy_binding_group :: proc(ctx: ^Context, group: Binding_Group) {
	if !require_initialized(ctx, "gfx.destroy_binding_group") {
		return
	}
	if !require_resource(ctx, &ctx.binding_group_pool, u64(group), "gfx.destroy_binding_group", "binding group") {
		return
	}

	if ctx.binding_group_states != nil {
		delete_key(&ctx.binding_group_states, group)
	}
	release_resource_id(&ctx.binding_group_pool, u64(group))
}

// apply_binding_group validates one object-backed binding group against the active pipeline and applies it with optional geometry bindings.
apply_binding_group :: proc(ctx: ^Context, group: Binding_Group, base_bindings: Bindings = {}) -> bool {
	groups := [?]Binding_Group{group}
	return apply_binding_groups_internal(ctx, groups[:], base_bindings, "gfx.apply_binding_group")
}

// apply_binding_groups validates all object-backed binding groups against the active pipeline and applies them with optional geometry bindings.
apply_binding_groups :: proc(ctx: ^Context, groups: []Binding_Group, base_bindings: Bindings = {}) -> bool {
	return apply_binding_groups_internal(ctx, groups, base_bindings, "gfx.apply_binding_groups")
}

@(private)
apply_binding_groups_internal :: proc(ctx: ^Context, groups: []Binding_Group, base_bindings: Bindings, op: string) -> bool {
	if !require_any_pass(ctx, op) {
		return false
	}
	if len(groups) == 0 {
		set_validation_errorf(ctx, "%s: at least one binding group is required", op)
		return false
	}
	if binding_group_base_has_shader_resources(base_bindings) {
		set_validation_errorf(ctx, "%s: base bindings must not contain resource views or samplers", op)
		return false
	}

	shader_state, shader_state_ok := current_binding_group_shader_state(ctx, op)
	if !shader_state_ok {
		return false
	}
	if !shader_state.has_binding_metadata {
		set_validation_errorf(ctx, "%s: current pipeline shader has no binding metadata", op)
		return false
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

	seen_groups: [MAX_BINDING_GROUPS]bool
	bindings := base_bindings
	for group in groups {
		if !require_resource(ctx, &ctx.binding_group_pool, u64(group), op, "binding group") {
			return false
		}
		group_state, group_ok := query_binding_group_state(ctx, group)
		if !group_ok {
			set_validation_errorf(ctx, "%s: binding group state is unavailable", op)
			return false
		}
		if !require_resource(ctx, &ctx.binding_group_layout_pool, u64(group_state.layout), op, "binding group layout") {
			return false
		}
		layout_state, layout_ok := query_binding_group_layout_state(ctx, group_state.layout)
		if !layout_ok {
			set_validation_errorf(ctx, "%s: binding group layout state is unavailable", op)
			return false
		}

		logical_group := layout_state.desc.group
		if pipeline_layout_state.desc.group_layouts[logical_group] != group_state.layout {
			set_validation_errorf(ctx, "%s: binding group %d layout does not match current pipeline_layout", op, logical_group)
			return false
		}
		if seen_groups[logical_group] {
			set_validation_errorf(ctx, "%s: duplicate binding group %d", op, logical_group)
			return false
		}
		seen_groups[logical_group] = true

		if !validate_binding_group_pipeline_compatibility(ctx, shader_state, layout_state.desc, op) {
			return false
		}
		if !validate_binding_group_desc(ctx, layout_state.desc, group_state.desc, op) {
			return false
		}

		merge_binding_group(&bindings, layout_state.desc, group_state.desc)
	}

	return apply_bindings(ctx, bindings)
}

// validate_binding_group_layout_desc validates generated binding-group layout data.
validate_binding_group_layout_desc :: proc(ctx: ^Context, desc: Binding_Group_Layout_Desc) -> bool {
	if !require_initialized(ctx, "gfx.validate_binding_group_layout_desc") {
		return false
	}
	if desc.group >= MAX_BINDING_GROUPS {
		set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: group %d is out of range", desc.group)
		return false
	}

	for entry, index in desc.entries {
		if !entry.active {
			continue
		}
		if !validate_binding_group_layout_entry(ctx, entry, index) {
			return false
		}

		entry_first, entry_count := binding_group_layout_entry_slot_range(entry)
		for other, other_index in desc.entries {
			if other_index >= index || !other.active {
				continue
			}
			if other.kind != entry.kind {
				continue
			}
			other_first, other_count := binding_group_layout_entry_slot_range(other)
			if entry_first == other_first && entry_count == 1 && other_count == 1 {
				set_validation_errorf(
					ctx,
					"gfx.validate_binding_group_layout_desc: duplicate %s entry at slot %d",
					shader_binding_kind_name(entry.kind),
					entry.slot,
				)
				return false
			}
			if entry_first < other_first + other_count && other_first < entry_first + entry_count {
				set_validation_errorf(
					ctx,
					"gfx.validate_binding_group_layout_desc: %s slot range [%d, %d) overlaps existing entry at slot %d",
					shader_binding_kind_name(entry.kind),
					entry_first,
					entry_first + entry_count,
					other_first,
				)
				return false
			}
		}
	}

	for native, index in desc.native_bindings {
		if !native.active {
			continue
		}
		if !validate_binding_group_native_binding(ctx, desc, native, index) {
			return false
		}

		for other, other_index in desc.native_bindings {
			if other_index >= index || !other.active {
				continue
			}
			if other.target == native.target &&
			   other.stage == native.stage &&
			   other.kind == native.kind &&
			   other.native_slot == native.native_slot &&
			   other.native_space == native.native_space {
				set_validation_errorf(
					ctx,
					"gfx.validate_binding_group_layout_desc: duplicate native %s %s %s binding at slot %d space %d",
					backend_name(native.target),
					shader_stage_name(native.stage),
					shader_binding_kind_name(native.kind),
					native.native_slot,
					native.native_space,
				)
				return false
			}
		}
	}

	return true
}

@(private)
query_binding_group_layout_state :: proc(ctx: ^Context, layout: Binding_Group_Layout) -> (Binding_Group_Layout_State, bool) {
	if ctx == nil || ctx.binding_group_layout_states == nil {
		return {}, false
	}

	state, ok := ctx.binding_group_layout_states[layout]
	return state, ok && state.valid
}

@(private)
query_binding_group_state :: proc(ctx: ^Context, group: Binding_Group) -> (Binding_Group_State, bool) {
	if ctx == nil || ctx.binding_group_states == nil {
		return {}, false
	}

	state, ok := ctx.binding_group_states[group]
	return state, ok && state.valid
}

@(private)
binding_group_layout_in_use :: proc(ctx: ^Context, layout: Binding_Group_Layout) -> bool {
	if ctx == nil || ctx.binding_group_states == nil {
		return binding_group_layout_used_by_pipeline_layout(ctx, layout)
	}

	for _, group_state in ctx.binding_group_states {
		if group_state.valid && group_state.layout == layout {
			return true
		}
	}

	return binding_group_layout_used_by_pipeline_layout(ctx, layout)
}

@(private)
validate_binding_group_pipeline_compatibility :: proc(ctx: ^Context, shader_state: Shader_State, layout: Binding_Group_Layout_Desc, op: string) -> bool {
	for entry in layout.entries {
		if !entry.active {
			continue
		}
		if !validate_binding_group_entry_against_shader(ctx, shader_state, layout.group, entry, op) {
			return false
		}
	}

	for native in layout.native_bindings {
		if !native.active || native.target != ctx.backend {
			continue
		}
		if !validate_binding_group_native_against_shader(ctx, shader_state, layout.group, native, op) {
			return false
		}
	}

	return true
}

@(private)
current_binding_group_shader_state :: proc(ctx: ^Context, op: string) -> (Shader_State, bool) {
	if ctx == nil {
		return {}, false
	}

	switch ctx.pass_kind {
	case .Render:
		if !pipeline_valid(ctx.current_pipeline) {
			set_validation_errorf(ctx, "%s: requires an applied graphics pipeline", op)
			return {}, false
		}
		pipeline_state, pipeline_state_ok := query_pipeline_state(ctx, ctx.current_pipeline)
		if !pipeline_state_ok {
			set_validation_errorf(ctx, "%s: current graphics pipeline state is unavailable", op)
			return {}, false
		}
		shader_state, shader_state_ok := query_shader_state(ctx, pipeline_state.shader)
		if !shader_state_ok {
			set_validation_errorf(ctx, "%s: current graphics pipeline shader state is unavailable", op)
			return {}, false
		}
		return shader_state, true
	case .Compute:
		if !compute_pipeline_valid(ctx.current_compute_pipeline) {
			set_validation_errorf(ctx, "%s: requires an applied compute pipeline", op)
			return {}, false
		}
		pipeline_state, pipeline_state_ok := query_compute_pipeline_state(ctx, ctx.current_compute_pipeline)
		if !pipeline_state_ok {
			set_validation_errorf(ctx, "%s: current compute pipeline state is unavailable", op)
			return {}, false
		}
		shader_state, shader_state_ok := query_shader_state(ctx, pipeline_state.shader)
		if !shader_state_ok {
			set_validation_errorf(ctx, "%s: current compute pipeline shader state is unavailable", op)
			return {}, false
		}
		return shader_state, true
	case .None:
	}

	set_validation_errorf(ctx, "%s: no pass is active", op)
	return {}, false
}

@(private)
validate_binding_group_entry_against_shader :: proc(ctx: ^Context, shader_state: Shader_State, group: u32, entry: Binding_Group_Layout_Entry_Desc, op: string) -> bool {
	for stage_index in 0..<3 {
		stage := Shader_Stage(stage_index)
		if !(stage in entry.stages) {
			continue
		}

		binding, binding_ok := shader_state_find_binding(shader_state, stage, entry.kind, group, entry.slot)
		if !binding_ok {
			set_validation_errorf(
				ctx,
				"%s: layout %s group %d slot %d for %s is not used by current pipeline",
				op,
				shader_binding_kind_name(entry.kind),
				group,
				entry.slot,
				shader_stage_name(stage),
			)
			return false
		}
		if binding.name != entry.name {
			set_validation_errorf(
				ctx,
				"%s: layout %s group %d slot %d name does not match current pipeline",
				op,
				shader_binding_kind_name(entry.kind),
				group,
				entry.slot,
			)
			return false
		}
		if !binding_group_entry_payload_matches_shader(ctx, entry, binding, op) {
			return false
		}
	}

	return true
}

@(private)
binding_group_entry_payload_matches_shader :: proc(ctx: ^Context, entry: Binding_Group_Layout_Entry_Desc, binding: Shader_Binding_Desc, op: string) -> bool {
	entry_array_count := entry.array_count
	if entry_array_count == 0 {
		entry_array_count = 1
	}
	binding_array_count := binding.array_count
	if binding_array_count == 0 {
		binding_array_count = 1
	}
	if entry_array_count != binding_array_count {
		set_validation_errorf(
			ctx,
			"%s: %s slot %d fixed-array count %d does not match current pipeline (%d)",
			op,
			shader_binding_kind_name(entry.kind),
			entry.slot,
			entry_array_count,
			binding_array_count,
		)
		return false
	}
	if entry.unsized != binding.unsized {
		set_validation_errorf(
			ctx,
			"%s: %s slot %d unsized=%v does not match current pipeline (unsized=%v)",
			op,
			shader_binding_kind_name(entry.kind),
			entry.slot,
			entry.unsized,
			binding.unsized,
		)
		return false
	}
	switch entry.kind {
	case .Uniform_Block:
		if entry.uniform_block.size != binding.size {
			set_validation_errorf(ctx, "%s: uniform slot %d size does not match current pipeline", op, entry.slot)
			return false
		}
	case .Resource_View:
		if entry.resource_view.view_kind != binding.view_kind {
			set_validation_errorf(ctx, "%s: resource view slot %d view kind does not match current pipeline", op, entry.slot)
			return false
		}
		if entry.resource_view.access != binding.access {
			set_validation_errorf(ctx, "%s: resource view slot %d access does not match current pipeline", op, entry.slot)
			return false
		}
		if entry.resource_view.storage_image_format != binding.storage_image_format {
			set_validation_errorf(ctx, "%s: resource view slot %d storage image format does not match current pipeline", op, entry.slot)
			return false
		}
		if entry.resource_view.storage_buffer_stride != binding.storage_buffer_stride {
			set_validation_errorf(ctx, "%s: resource view slot %d storage buffer stride does not match current pipeline", op, entry.slot)
			return false
		}
	case .Sampler:
	}

	return true
}

@(private)
validate_binding_group_native_against_shader :: proc(ctx: ^Context, shader_state: Shader_State, group: u32, native: Binding_Group_Native_Binding_Desc, op: string) -> bool {
	binding, binding_ok := shader_state_find_binding(shader_state, native.stage, native.kind, group, native.slot)
	if !binding_ok {
		set_validation_errorf(
			ctx,
			"%s: native layout %s %s group %d slot %d is not used by current pipeline",
			op,
			shader_stage_name(native.stage),
			shader_binding_kind_name(native.kind),
			group,
			native.slot,
		)
		return false
	}
	if binding.native_slot != native.native_slot || binding.native_space != native.native_space {
		set_validation_errorf(
			ctx,
			"%s: native %s %s group %d slot %d does not match current pipeline",
			op,
			shader_stage_name(native.stage),
			shader_binding_kind_name(native.kind),
			group,
			native.slot,
		)
		return false
	}

	return true
}

@(private)
shader_state_find_binding :: proc(
	shader_state: Shader_State,
	stage: Shader_Stage,
	kind: Shader_Binding_Kind,
	group: u32,
	slot: u32,
) -> (Shader_Binding_Desc, bool) {
	for binding in shader_state.bindings {
		if binding.active && binding.stage == stage && binding.kind == kind && binding.group == group && binding.slot == slot {
			return binding, true
		}
	}

	return {}, false
}

@(private)
binding_group_layout_find_entry :: proc(
	layout: Binding_Group_Layout_Desc,
	kind: Shader_Binding_Kind,
	slot: u32,
) -> (Binding_Group_Layout_Entry_Desc, bool) {
	for entry in layout.entries {
		if !entry.active || entry.kind != kind {
			continue
		}
		first, count := binding_group_layout_entry_slot_range(entry)
		if slot >= first && slot < first + count {
			return entry, true
		}
	}

	return {}, false
}

@(private)
binding_group_layout_has_stage_entry :: proc(
	layout: Binding_Group_Layout_Desc,
	kind: Shader_Binding_Kind,
	slot: u32,
	stage: Shader_Stage,
) -> bool {
	for entry in layout.entries {
		if entry.active && entry.kind == kind && entry.slot == slot && stage in entry.stages {
			return true
		}
	}

	return false
}

@(private)
binding_group_layout_has_native_binding :: proc(layout: Binding_Group_Layout_Desc, target: Backend, binding: Shader_Binding_Desc) -> bool {
	for native in layout.native_bindings {
		if !native.active {
			continue
		}
		if native.target == target &&
		   native.stage == binding.stage &&
		   native.kind == binding.kind &&
		   native.slot == binding.slot &&
		   native.native_slot == binding.native_slot &&
		   native.native_space == binding.native_space {
			return true
		}
	}

	return false
}

@(private)
validate_binding_group_desc :: proc(ctx: ^Context, layout: Binding_Group_Layout_Desc, group: Binding_Group_Desc, op: string) -> bool {
	for entry in layout.entries {
		if !entry.active {
			continue
		}

		if binding_group_layout_entry_is_array(entry) {
			if !validate_binding_group_array_entry(ctx, layout, entry, group, op) {
				return false
			}
			continue
		}

		switch entry.kind {
		case .Uniform_Block:
			// Uniform block data flows through apply_uniforms because it is per-draw mutable.
		case .Resource_View:
			view := group.views[entry.slot]
			if !view_valid(view) {
				set_validation_errorf(ctx, "%s: resource view slot %d requires a view", op, entry.slot)
				return false
			}
			if !validate_binding_group_view(ctx, entry, view, op) {
				return false
			}
		case .Sampler:
			sampler := group.samplers[entry.slot]
			if !sampler_valid(sampler) {
				set_validation_errorf(ctx, "%s: sampler slot %d requires a sampler", op, entry.slot)
				return false
			}
			if !require_resource(ctx, &ctx.sampler_pool, u64(sampler), op, "sampler") {
				return false
			}
		}
	}

	for view, slot in group.views {
		if !view_valid(view) {
			continue
		}
		if !binding_group_layout_slot_in_entry(layout, .Resource_View, u32(slot)) {
			set_validation_errorf(ctx, "%s: resource view slot %d is not declared by layout", op, slot)
			return false
		}
		if binding_group_layout_slot_in_array(layout, .Resource_View, u32(slot)) {
			set_validation_errorf(ctx, "%s: resource view slot %d is declared as a fixed array; populate Binding_Group_Desc.arrays instead", op, slot)
			return false
		}
	}
	for sampler, slot in group.samplers {
		if !sampler_valid(sampler) {
			continue
		}
		if !binding_group_layout_slot_in_entry(layout, .Sampler, u32(slot)) {
			set_validation_errorf(ctx, "%s: sampler slot %d is not declared by layout", op, slot)
			return false
		}
		if binding_group_layout_slot_in_array(layout, .Sampler, u32(slot)) {
			set_validation_errorf(ctx, "%s: sampler slot %d is declared as a fixed array; populate Binding_Group_Desc.arrays instead", op, slot)
			return false
		}
	}

	for array, array_index in group.arrays {
		if !array.active {
			continue
		}
		if !validate_binding_group_array_payload_orphan(ctx, layout, array, array_index, op) {
			return false
		}
	}

	return true
}

@(private)
binding_group_layout_entry_is_array :: proc(entry: Binding_Group_Layout_Entry_Desc) -> bool {
	return entry.array_count > 1
}

@(private)
binding_group_layout_entry_slot_range :: proc(entry: Binding_Group_Layout_Entry_Desc) -> (u32, u32) {
	count := entry.array_count
	if count == 0 {
		count = 1
	}
	return entry.slot, count
}

@(private)
binding_group_layout_slot_in_entry :: proc(layout: Binding_Group_Layout_Desc, kind: Shader_Binding_Kind, slot: u32) -> bool {
	for entry in layout.entries {
		if !entry.active || entry.kind != kind {
			continue
		}
		first, count := binding_group_layout_entry_slot_range(entry)
		if slot >= first && slot < first + count {
			return true
		}
	}
	return false
}

@(private)
binding_group_layout_slot_in_array :: proc(layout: Binding_Group_Layout_Desc, kind: Shader_Binding_Kind, slot: u32) -> bool {
	for entry in layout.entries {
		if !entry.active || entry.kind != kind || !binding_group_layout_entry_is_array(entry) {
			continue
		}
		first, count := binding_group_layout_entry_slot_range(entry)
		if slot >= first && slot < first + count {
			return true
		}
	}
	return false
}

@(private)
validate_binding_group_array_entry :: proc(
	ctx: ^Context,
	layout: Binding_Group_Layout_Desc,
	entry: Binding_Group_Layout_Entry_Desc,
	group: Binding_Group_Desc,
	op: string,
) -> bool {
	matched := false
	matched_index := -1
	for array, array_index in group.arrays {
		if !array.active {
			continue
		}
		if array.kind != entry.kind || array.slot != entry.slot {
			continue
		}
		if matched {
			set_validation_errorf(
				ctx,
				"%s: duplicate fixed-array payload for %s slot %d (arrays index %d and %d)",
				op,
				shader_binding_kind_name(entry.kind),
				entry.slot,
				matched_index,
				array_index,
			)
			return false
		}
		matched = true
		matched_index = array_index

		if array.count != entry.array_count {
			set_validation_errorf(
				ctx,
				"%s: %s slot %d fixed-array count %d does not match layout count %d",
				op,
				shader_binding_kind_name(entry.kind),
				entry.slot,
				array.count,
				entry.array_count,
			)
			return false
		}
		if array.first_index != 0 {
			set_validation_errorf(
				ctx,
				"%s: %s slot %d fixed-array first_index must be 0 for create-time payload (got %d)",
				op,
				shader_binding_kind_name(entry.kind),
				entry.slot,
				array.first_index,
			)
			return false
		}

		switch entry.kind {
		case .Resource_View:
			if len(array.samplers) != 0 {
				set_validation_errorf(ctx, "%s: resource view fixed-array at slot %d must not set samplers payload", op, entry.slot)
				return false
			}
			if u32(len(array.views)) != entry.array_count {
				set_validation_errorf(
					ctx,
					"%s: resource view fixed-array at slot %d expects %d views, got %d",
					op,
					entry.slot,
					entry.array_count,
					len(array.views),
				)
				return false
			}
			for view, element_index in array.views {
				if !view_valid(view) {
					set_validation_errorf(
						ctx,
						"%s: resource view fixed-array at slot %d element %d requires a view",
						op,
						entry.slot,
						element_index,
					)
					return false
				}
				if !validate_binding_group_view(ctx, entry, view, op) {
					return false
				}
			}
		case .Sampler:
			if len(array.views) != 0 {
				set_validation_errorf(ctx, "%s: sampler fixed-array at slot %d must not set views payload", op, entry.slot)
				return false
			}
			if u32(len(array.samplers)) != entry.array_count {
				set_validation_errorf(
					ctx,
					"%s: sampler fixed-array at slot %d expects %d samplers, got %d",
					op,
					entry.slot,
					entry.array_count,
					len(array.samplers),
				)
				return false
			}
			for sampler, element_index in array.samplers {
				if !sampler_valid(sampler) {
					set_validation_errorf(
						ctx,
						"%s: sampler fixed-array at slot %d element %d requires a sampler",
						op,
						entry.slot,
						element_index,
					)
					return false
				}
				if !require_resource(ctx, &ctx.sampler_pool, u64(sampler), op, "sampler") {
					return false
				}
			}
		case .Uniform_Block:
			set_validation_errorf(ctx, "%s: uniform block at slot %d cannot be a fixed array", op, entry.slot)
			return false
		}
	}

	if !matched {
		set_validation_errorf(
			ctx,
			"%s: %s slot %d declares a fixed array of size %d but no Binding_Group_Desc.arrays entry populates it",
			op,
			shader_binding_kind_name(entry.kind),
			entry.slot,
			entry.array_count,
		)
		return false
	}

	return true
}

@(private)
validate_binding_group_array_payload_orphan :: proc(
	ctx: ^Context,
	layout: Binding_Group_Layout_Desc,
	array: Binding_Group_Array_Desc,
	array_index: int,
	op: string,
) -> bool {
	if !shader_binding_kind_valid(array.kind) {
		set_validation_errorf(ctx, "%s: arrays[%d] has an invalid kind", op, array_index)
		return false
	}
	for entry in layout.entries {
		if !entry.active {
			continue
		}
		if entry.kind == array.kind && entry.slot == array.slot && binding_group_layout_entry_is_array(entry) {
			return true
		}
	}
	set_validation_errorf(
		ctx,
		"%s: arrays[%d] %s slot %d is not declared as a fixed array by the layout",
		op,
		array_index,
		shader_binding_kind_name(array.kind),
		array.slot,
	)
	return false
}

@(private)
validate_binding_group_view :: proc(ctx: ^Context, entry: Binding_Group_Layout_Entry_Desc, view: View, op: string) -> bool {
	view_state := query_view_state(ctx, view)
	if !view_state.valid {
		set_invalid_handle_errorf(ctx, "%s: resource view slot %d handle is invalid", op, entry.slot)
		return false
	}
	if view_state.kind != entry.resource_view.view_kind {
		set_validation_errorf(
			ctx,
			"%s: resource view slot %d requires a %s view",
			op,
			entry.slot,
			view_kind_name(entry.resource_view.view_kind),
		)
		return false
	}
	if entry.resource_view.view_kind == .Storage_Image &&
	   entry.resource_view.storage_image_format != .Invalid &&
	   view_state.format != entry.resource_view.storage_image_format {
		set_validation_errorf(ctx, "%s: storage image slot %d format does not match layout", op, entry.slot)
		return false
	}
	if entry.resource_view.view_kind == .Storage_Buffer &&
	   entry.resource_view.storage_buffer_stride != 0 &&
	   u32(view_state.storage_stride) != entry.resource_view.storage_buffer_stride {
		set_validation_errorf(ctx, "%s: storage buffer slot %d stride does not match layout", op, entry.slot)
		return false
	}

	return true
}

@(private)
merge_binding_group :: proc(bindings: ^Bindings, layout: Binding_Group_Layout_Desc, group: Binding_Group_Desc) {
	for entry in layout.entries {
		if !entry.active {
			continue
		}

		switch entry.kind {
		case .Uniform_Block:
		case .Resource_View:
			if binding_group_layout_entry_is_array(entry) {
				for array in group.arrays {
					if !array.active || array.kind != .Resource_View || array.slot != entry.slot {
						continue
					}
					for view, element_index in array.views {
						bindings.views[layout.group][int(entry.slot) + element_index] = view
					}
				}
			} else {
				bindings.views[layout.group][entry.slot] = group.views[entry.slot]
			}
		case .Sampler:
			if binding_group_layout_entry_is_array(entry) {
				for array in group.arrays {
					if !array.active || array.kind != .Sampler || array.slot != entry.slot {
						continue
					}
					for sampler, element_index in array.samplers {
						bindings.samplers[layout.group][int(entry.slot) + element_index] = sampler
					}
				}
			} else {
				bindings.samplers[layout.group][entry.slot] = group.samplers[entry.slot]
			}
		}
	}
}

@(private)
binding_group_base_has_shader_resources :: proc(bindings: Bindings) -> bool {
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
validate_binding_group_layout_entry :: proc(ctx: ^Context, entry: Binding_Group_Layout_Entry_Desc, index: int) -> bool {
	if entry.stages == {} {
		set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: entry %d requires at least one stage", index)
		return false
	}
	if !shader_binding_kind_valid(entry.kind) {
		set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: entry %d has an invalid kind", index)
		return false
	}
	if entry.name == "" {
		set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: entry %d requires a reflected name", index)
		return false
	}
	if !validate_binding_group_slot(ctx, entry.kind, entry.slot, "entry", index) {
		return false
	}
	if entry.unsized {
		set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: entry %d declares an unsized array; runtime / bindless arrays use Binding_Heap (item 28 ships fixed arrays only)", index)
		return false
	}
	if entry.array_count > 1 {
		switch entry.kind {
		case .Resource_View, .Sampler:
		case .Uniform_Block:
			set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: entry %d uniform blocks do not support fixed arrays", index)
			return false
		}
		limit := binding_group_slot_limit(entry.kind)
		if u64(entry.slot) + u64(entry.array_count) > u64(limit) {
			set_validation_errorf(
				ctx,
				"gfx.validate_binding_group_layout_desc: entry %d %s fixed array [%d, %d) exceeds slot limit %d",
				index,
				shader_binding_kind_name(entry.kind),
				entry.slot,
				entry.slot + entry.array_count,
				limit,
			)
			return false
		}
	}

	switch entry.kind {
	case .Uniform_Block:
		if entry.uniform_block.size == 0 {
			set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: uniform entry %d requires nonzero size", index)
			return false
		}
	case .Resource_View:
		if !shader_resource_view_kind_valid(entry.resource_view.view_kind) {
			set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: resource view entry %d has an invalid view kind", index)
			return false
		}
		if !shader_resource_access_valid(entry.resource_view.access) {
			set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: resource view entry %d has an invalid access", index)
			return false
		}
		if entry.resource_view.view_kind == .Storage_Image {
			if !shader_storage_image_format_valid(entry.resource_view.storage_image_format) {
				set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: storage image entry %d has an unsupported format", index)
				return false
			}
		} else if entry.resource_view.storage_image_format != .Invalid {
			set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: non-storage-image entry %d must not declare a storage image format", index)
			return false
		}
		if entry.resource_view.view_kind == .Storage_Buffer {
			if entry.resource_view.storage_buffer_stride != 0 && entry.resource_view.storage_buffer_stride % 4 != 0 {
				set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: storage buffer entry %d stride must be 4-byte aligned", index)
				return false
			}
		} else if entry.resource_view.storage_buffer_stride != 0 {
			set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: non-storage-buffer entry %d must not declare a storage buffer stride", index)
			return false
		}
	case .Sampler:
	}

	return true
}

@(private)
validate_binding_group_native_binding :: proc(
	ctx: ^Context,
	desc: Binding_Group_Layout_Desc,
	native: Binding_Group_Native_Binding_Desc,
	index: int,
) -> bool {
	switch native.target {
	case .D3D11, .Vulkan:
	case .Auto, .Null:
		set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: native binding %d has an invalid backend target", index)
		return false
	}
	if !shader_stage_valid(native.stage) {
		set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: native binding %d has an invalid stage", index)
		return false
	}
	if !shader_binding_kind_valid(native.kind) {
		set_validation_errorf(ctx, "gfx.validate_binding_group_layout_desc: native binding %d has an invalid kind", index)
		return false
	}
	if !validate_binding_group_slot(ctx, native.kind, native.slot, "native binding", index) {
		return false
	}
	if !validate_binding_group_native_slot(ctx, native.kind, native.native_slot, index) {
		return false
	}
	if !binding_group_layout_has_entry_for_native(desc, native) {
		set_validation_errorf(
			ctx,
			"gfx.validate_binding_group_layout_desc: native binding %d references missing %s entry slot %d",
			index,
			shader_binding_kind_name(native.kind),
			native.slot,
		)
		return false
	}

	return true
}

@(private)
validate_binding_group_slot :: proc(ctx: ^Context, kind: Shader_Binding_Kind, slot: u32, label: string, index: int) -> bool {
	limit := binding_group_slot_limit(kind)
	if limit == 0 || slot >= limit {
		set_validation_errorf(
			ctx,
			"gfx.validate_binding_group_layout_desc: %s %d %s slot %d is out of range",
			label,
			index,
			shader_binding_kind_name(kind),
			slot,
		)
		return false
	}

	return true
}

@(private)
validate_binding_group_native_slot :: proc(ctx: ^Context, kind: Shader_Binding_Kind, slot: u32, index: int) -> bool {
	limit := binding_group_slot_limit(kind)
	if limit == 0 || slot >= limit {
		set_validation_errorf(
			ctx,
			"gfx.validate_binding_group_layout_desc: native binding %d %s native slot %d is out of range",
			index,
			shader_binding_kind_name(kind),
			slot,
		)
		return false
	}

	return true
}

@(private)
binding_group_layout_has_entry_for_native :: proc(desc: Binding_Group_Layout_Desc, native: Binding_Group_Native_Binding_Desc) -> bool {
	for entry in desc.entries {
		if !entry.active {
			continue
		}
		if entry.kind == native.kind && entry.slot == native.slot && native.stage in entry.stages {
			return true
		}
	}

	return false
}

@(private)
binding_group_layout_has_entry :: proc(layout: Binding_Group_Layout_Desc, kind: Shader_Binding_Kind, slot: u32) -> bool {
	for entry in layout.entries {
		if entry.active && entry.kind == kind && entry.slot == slot {
			return true
		}
	}

	return false
}

@(private)
view_kind_name :: proc(kind: View_Kind) -> string {
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

@(private)
binding_group_slot_limit :: proc(kind: Shader_Binding_Kind) -> u32 {
	switch kind {
	case .Uniform_Block:
		return MAX_UNIFORM_BLOCKS
	case .Resource_View:
		return MAX_RESOURCE_VIEWS
	case .Sampler:
		return MAX_SAMPLERS
	}

	return 0
}
