package gfx

// validate_binding_group_layout_desc validates generated binding-group layout data.
validate_binding_group_layout_desc :: proc(ctx: ^Context, desc: Binding_Group_Layout_Desc) -> bool {
	if !require_initialized(ctx, "gfx.validate_binding_group_layout_desc") {
		return false
	}

	for entry, index in desc.entries {
		if !entry.active {
			continue
		}
		if !validate_binding_group_layout_entry(ctx, entry, index) {
			return false
		}

		for other, other_index in desc.entries {
			if other_index >= index || !other.active {
				continue
			}
			if other.kind == entry.kind && other.slot == entry.slot {
				set_validation_errorf(
					ctx,
					"gfx.validate_binding_group_layout_desc: duplicate %s entry at slot %d",
					shader_binding_kind_name(entry.kind),
					entry.slot,
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
