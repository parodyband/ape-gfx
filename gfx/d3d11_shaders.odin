#+private
package gfx

import "core:mem"
import d3d11 "vendor:directx/d3d11"

d3d11_create_shader :: proc(ctx: ^Context, handle: Shader, desc: Shader_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	shader_info: D3D11_Shader
	for stage_desc in desc.stages {
		if stage_desc.bytecode.ptr == nil || stage_desc.bytecode.size <= 0 {
			continue
		}

		switch stage_desc.stage {
		case .Vertex:
			hr := state.device.CreateVertexShader(
				state.device,
				stage_desc.bytecode.ptr,
				d3d11.SIZE_T(stage_desc.bytecode.size),
				nil,
				&shader_info.vertex,
			)
			if d3d11_failed(hr) {
				d3d11_release_shader(&shader_info)
				set_backend_error(ctx, "gfx.d3d11: CreateVertexShader failed")
				return false
			}
			d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)shader_info.vertex, desc.label, "vertex shader")
			shader_info.vertex_bytecode = d3d11_copy_range(stage_desc.bytecode)
		case .Fragment:
			hr := state.device.CreatePixelShader(
				state.device,
				stage_desc.bytecode.ptr,
				d3d11.SIZE_T(stage_desc.bytecode.size),
				nil,
				&shader_info.pixel,
			)
			if d3d11_failed(hr) {
				d3d11_release_shader(&shader_info)
				set_backend_error(ctx, "gfx.d3d11: CreatePixelShader failed")
				return false
			}
			d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)shader_info.pixel, desc.label, "fragment shader")
		case .Compute:
			hr := state.device.CreateComputeShader(
				state.device,
				stage_desc.bytecode.ptr,
				d3d11.SIZE_T(stage_desc.bytecode.size),
				nil,
				&shader_info.compute,
			)
			if d3d11_failed(hr) {
				d3d11_release_shader(&shader_info)
				set_backend_error(ctx, "gfx.d3d11: CreateComputeShader failed")
				return false
			}
			d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)shader_info.compute, desc.label, "compute shader")
		}
	}

	if shader_info.vertex == nil && shader_info.pixel == nil && shader_info.compute == nil {
		set_validation_error(ctx, "gfx.d3d11: shader did not contain supported bytecode")
		return false
	}

	shader_info.has_binding_metadata = desc.has_binding_metadata
	shader_info.has_vertex_input_metadata = desc.has_vertex_input_metadata
	for input, slot in desc.vertex_inputs {
		shader_info.vertex_inputs[slot] = input
	}
	for binding in desc.bindings {
		if !binding.active {
			continue
		}

		stage := int(binding.stage)
		group := int(binding.group)
		switch binding.kind {
		case .Uniform_Block:
			if binding.group >= MAX_BINDING_GROUPS {
				set_validation_errorf(ctx, "gfx.d3d11: uniform binding group %d is out of range", binding.group)
				d3d11_release_shader(&shader_info)
				return false
			}
			if binding.slot >= MAX_UNIFORM_BLOCKS {
				set_validation_errorf(ctx, "gfx.d3d11: uniform binding slot %d is out of range", binding.slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			if binding.native_slot >= MAX_UNIFORM_BLOCKS {
				set_validation_errorf(ctx, "gfx.d3d11: native uniform binding slot %d is out of range", binding.native_slot)
				d3d11_release_shader(&shader_info)
				return false
			}

			existing_slot := shader_info.uniform_slots[stage][group][int(binding.slot)]
			existing_size := existing_slot.size
			if existing_size != 0 && binding.size != 0 && existing_size != binding.size {
				set_validation_errorf(ctx, "gfx.d3d11: uniform binding slot %d has conflicting reflected sizes", binding.slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			shader_info.required[stage].uniforms[group] |= d3d11_slot_mask(binding.slot)
			shader_info.uniform_slots[stage][group][int(binding.slot)] = {
				active = true,
				native_slot = binding.native_slot,
				size = binding.size,
			}
		case .Resource_View:
			if binding.group >= MAX_BINDING_GROUPS {
				set_validation_errorf(ctx, "gfx.d3d11: resource view binding group %d is out of range", binding.group)
				d3d11_release_shader(&shader_info)
				return false
			}
			if binding.slot >= MAX_RESOURCE_VIEWS {
				set_validation_errorf(ctx, "gfx.d3d11: resource view binding slot %d is out of range", binding.slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			if binding.native_slot >= MAX_RESOURCE_VIEWS {
				set_validation_errorf(ctx, "gfx.d3d11: native resource view binding slot %d is out of range", binding.native_slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			if !d3d11_resource_view_kind_supported(binding.view_kind) {
				set_unsupported_errorf(ctx, "gfx.d3d11: resource view binding slot %d has unsupported reflected view kind", binding.slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			if (binding.view_kind == .Storage_Image || binding.view_kind == .Storage_Buffer) && binding.native_slot >= D3D11_MAX_UAV_SLOTS {
				set_validation_errorf(ctx, "gfx.d3d11: native storage resource view binding slot %d is out of range", binding.native_slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			shader_info.required[stage].views[group] |= d3d11_slot_mask(binding.slot)
			shader_info.view_slots[stage][group][int(binding.slot)] = {
				active = true,
				native_slot = binding.native_slot,
				view_kind = binding.view_kind,
				access = binding.access,
				storage_image_format = binding.storage_image_format,
				storage_buffer_stride = binding.storage_buffer_stride,
			}
		case .Sampler:
			if binding.group >= MAX_BINDING_GROUPS {
				set_validation_errorf(ctx, "gfx.d3d11: sampler binding group %d is out of range", binding.group)
				d3d11_release_shader(&shader_info)
				return false
			}
			if binding.slot >= MAX_SAMPLERS {
				set_validation_errorf(ctx, "gfx.d3d11: sampler binding slot %d is out of range", binding.slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			if binding.native_slot >= MAX_SAMPLERS {
				set_validation_errorf(ctx, "gfx.d3d11: native sampler binding slot %d is out of range", binding.native_slot)
				d3d11_release_shader(&shader_info)
				return false
			}
			shader_info.required[stage].samplers[group] |= d3d11_slot_mask(binding.slot)
			shader_info.sampler_slots[stage][group][int(binding.slot)] = {
				active = true,
				native_slot = binding.native_slot,
			}
		}
	}

	state.shaders[handle] = shader_info
	return true
}

d3d11_destroy_shader :: proc(ctx: ^Context, handle: Shader) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if shader_info, ok := state.shaders[handle]; ok {
		d3d11_release_shader(&shader_info)
		delete_key(&state.shaders, handle)
	}
}

d3d11_release_shader :: proc(shader_info: ^D3D11_Shader) {
	if shader_info == nil {
		return
	}

	if shader_info.vertex != nil {
		shader_info.vertex.Release(shader_info.vertex)
		shader_info.vertex = nil
	}
	if shader_info.pixel != nil {
		shader_info.pixel.Release(shader_info.pixel)
		shader_info.pixel = nil
	}
	if shader_info.compute != nil {
		shader_info.compute.Release(shader_info.compute)
		shader_info.compute = nil
	}
	if shader_info.vertex_bytecode != nil {
		delete(shader_info.vertex_bytecode)
		shader_info.vertex_bytecode = nil
	}
}

d3d11_copy_range :: proc(data: Range) -> []u8 {
	if data.ptr == nil || data.size <= 0 {
		return nil
	}

	result := make([]u8, data.size)
	mem.copy(raw_data(result), data.ptr, data.size)
	return result
}
