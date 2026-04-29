#+private
package gfx

import "core:fmt"
import "core:mem"
import d3d11 "vendor:directx/d3d11"

d3d11_begin_pass :: proc(ctx: ^Context, desc: Pass_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil || state.backbuffer_rtv == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	rtvs: [MAX_COLOR_ATTACHMENTS]^d3d11.IRenderTargetView
	color_count: u32
	pass_width := state.width
	pass_height := state.height
	has_custom_color := false

	state.current_pipeline = Pipeline_Invalid
	state.current_compute_pipeline = Compute_Pipeline_Invalid
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	state.current_pass_color_formats = {}
	state.current_pass_has_color = false
	state.current_pass_depth_format = .Invalid
	state.current_pass_has_depth = false

	for attachment, slot in desc.color_attachments {
		if !view_valid(attachment) {
			continue
		}

		view_info, view_ok := state.views[attachment]
		if !view_ok || view_info.rtv == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: color attachment view handle is unknown")
			return false
		}
		if view_info.kind != .Color_Attachment {
			set_validation_error(ctx, "gfx.d3d11: pass color attachment requires a color attachment view")
			return false
		}

		if !has_custom_color {
			pass_width = view_info.width
			pass_height = view_info.height
			has_custom_color = true
		} else if view_info.width != pass_width || view_info.height != pass_height {
			set_validation_error(ctx, "gfx.d3d11: color attachments must have matching dimensions")
			return false
		}

		rtvs[slot] = view_info.rtv
		state.current_pass_color_formats[slot] = view_info.format
		state.current_pass_has_color = true
		color_count = u32(slot + 1)
	}

	dsv := state.default_depth_dsv
	if view_valid(desc.depth_stencil_attachment) {
		view_info, view_ok := state.views[desc.depth_stencil_attachment]
		if !view_ok || view_info.dsv == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: depth-stencil attachment view handle is unknown")
			return false
		}
		if view_info.kind != .Depth_Stencil_Attachment {
			set_validation_error(ctx, "gfx.d3d11: pass depth attachment requires a depth-stencil attachment view")
			return false
		}
		if has_custom_color {
			if view_info.width != pass_width || view_info.height != pass_height {
				set_validation_error(ctx, "gfx.d3d11: depth-stencil attachment dimensions must match the color attachments")
				return false
			}
		} else {
			pass_width = view_info.width
			pass_height = view_info.height
		}

		dsv = view_info.dsv
		state.current_pass_depth_format = view_info.format
		state.current_pass_has_depth = true
	} else if has_custom_color {
		dsv = nil
	} else {
		rtvs[0] = state.backbuffer_rtv
		color_count = 1
		state.current_pass_color_formats[0] = ctx.desc.swapchain_format
		state.current_pass_has_color = true
		state.current_pass_has_depth = state.default_depth_dsv != nil
		if state.current_pass_has_depth {
			state.current_pass_depth_format = .D32F
		}
	}

	if color_count == 0 && dsv == nil {
		set_validation_error(ctx, "gfx.d3d11: pass requires at least one color or depth-stencil attachment")
		return false
	}

	null_srvs: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	state.immediate.VSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	state.immediate.PSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	d3d11_clear_compute_resource_bindings(state)

	viewport := d3d11.VIEWPORT {
		TopLeftX = 0,
		TopLeftY = 0,
		Width = f32(pass_width),
		Height = f32(pass_height),
		MinDepth = 0,
		MaxDepth = 1,
	}
	state.immediate.RSSetViewports(state.immediate, 1, &viewport)

	if color_count > 0 {
		state.immediate.OMSetRenderTargets(state.immediate, color_count, &rtvs[0], dsv)
	} else {
		state.immediate.OMSetRenderTargets(state.immediate, 0, nil, dsv)
	}

	for slot in 0..<int(color_count) {
		if rtvs[slot] == nil {
			continue
		}

		color_action := desc.action.colors[slot]
		if color_action.load_action == .Clear {
			clear_color := [4]f32 {
				color_action.clear_value.r,
				color_action.clear_value.g,
				color_action.clear_value.b,
				color_action.clear_value.a,
			}
			state.immediate.ClearRenderTargetView(state.immediate, rtvs[slot], &clear_color)
		}
	}

	if dsv != nil {
		clear_flags: d3d11.CLEAR_FLAGS
		if desc.action.depth.load_action == .Clear {
			clear_flags += {.DEPTH}
		}
		if state.current_pass_depth_format == .D24S8 && desc.action.stencil.load_action == .Clear {
			clear_flags += {.STENCIL}
		}
		if clear_flags == {} {
			return true
		}

		state.immediate.ClearDepthStencilView(
			state.immediate,
			dsv,
			clear_flags,
			desc.action.depth.clear_value,
			desc.action.stencil.clear_value,
		)
	}

	return true
}

d3d11_begin_compute_pass :: proc(ctx: ^Context, desc: Compute_Pass_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	state.immediate.OMSetRenderTargets(state.immediate, 0, nil, nil)
	d3d11_clear_graphics_resource_bindings(state)
	d3d11_clear_compute_resource_bindings(state)

	state.current_pipeline = Pipeline_Invalid
	state.current_compute_pipeline = Compute_Pipeline_Invalid
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	state.current_pass_color_formats = {}
	state.current_pass_has_color = false
	state.current_pass_depth_format = .Invalid
	state.current_pass_has_depth = false
	return true
}

d3d11_apply_pipeline :: proc(ctx: ^Context, pipeline: Pipeline) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.pipelines[pipeline]
	if !pipeline_ok {
		set_invalid_handle_error(ctx, "gfx.d3d11: pipeline handle is unknown")
		return false
	}

	shader_info, shader_ok := state.shaders[pipeline_info.shader]
	if !shader_ok {
		set_invalid_handle_error(ctx, "gfx.d3d11: pipeline shader handle is unknown")
		return false
	}

	if !d3d11_validate_pipeline_pass_compatibility(ctx, state, &pipeline_info) {
		return false
	}

	state.immediate.IASetPrimitiveTopology(state.immediate, pipeline_info.topology)
	state.immediate.IASetInputLayout(state.immediate, pipeline_info.input_layout)
	state.immediate.VSSetShader(state.immediate, shader_info.vertex, nil, 0)
	state.immediate.PSSetShader(state.immediate, shader_info.pixel, nil, 0)
	state.immediate.RSSetState(state.immediate, pipeline_info.raster_state)
	state.immediate.OMSetDepthStencilState(state.immediate, pipeline_info.depth_stencil_state, 0)

	blend_factor := [4]f32{1, 1, 1, 1}
	state.immediate.OMSetBlendState(state.immediate, pipeline_info.blend_state, &blend_factor, 0xffffffff)
	state.current_pipeline = pipeline
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	return true
}

d3d11_apply_compute_pipeline :: proc(ctx: ^Context, pipeline: Compute_Pipeline) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.compute_pipelines[pipeline]
	if !pipeline_ok {
		set_invalid_handle_error(ctx, "gfx.d3d11: compute pipeline handle is unknown")
		return false
	}

	shader_info, shader_ok := state.shaders[pipeline_info.shader]
	if !shader_ok || shader_info.compute == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: compute pipeline shader handle is unknown")
		return false
	}

	state.immediate.CSSetShader(state.immediate, shader_info.compute, nil, 0)
	state.current_pipeline = Pipeline_Invalid
	state.current_compute_pipeline = pipeline
	state.current_vertex_buffers = 0
	state.current_index_buffer = false
	state.current_bindings = {}
	return true
}

d3d11_apply_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	if ctx.pass_kind == .Compute {
		return d3d11_apply_compute_bindings(ctx, bindings)
	}

	pipeline_info, pipeline_ok := state.pipelines[state.current_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: apply_bindings requires an applied pipeline")
		return false
	}

	vertex_buffers: [MAX_VERTEX_BUFFERS]^d3d11.IBuffer
	strides: [MAX_VERTEX_BUFFERS]u32
	offsets: [MAX_VERTEX_BUFFERS]u32
	vertex_count: u32
	vertex_mask: u32

	for binding, slot in bindings.vertex_buffers {
		if !buffer_valid(binding.buffer) {
			continue
		}

		buffer_info, buffer_ok := state.buffers[binding.buffer]
		if !buffer_ok || buffer_info.buffer == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: vertex buffer handle is unknown")
			return false
		}
		if !(.Vertex in buffer_info.usage) {
			set_validation_error(ctx, "gfx.d3d11: bound buffer is not vertex-capable")
			return false
		}

		vertex_buffers[slot] = buffer_info.buffer
		strides[slot] = pipeline_info.vertex_strides[slot]
		offsets[slot] = u32(binding.offset)
		vertex_mask |= d3d11_slot_mask(u32(slot))
		vertex_count = u32(slot + 1)
	}

	if vertex_count > 0 {
		state.immediate.IASetVertexBuffers(
			state.immediate,
			0,
			vertex_count,
			&vertex_buffers[0],
			&strides[0],
			&offsets[0],
		)
	}
	state.current_vertex_buffers = vertex_mask

	if buffer_valid(bindings.index_buffer.buffer) {
		buffer_info, buffer_ok := state.buffers[bindings.index_buffer.buffer]
		if !buffer_ok || buffer_info.buffer == nil {
			set_invalid_handle_error(ctx, "gfx.d3d11: index buffer handle is unknown")
			return false
		}
		if !(.Index in buffer_info.usage) {
			set_validation_error(ctx, "gfx.d3d11: bound buffer is not index-capable")
			return false
		}

		state.immediate.IASetIndexBuffer(
			state.immediate,
			buffer_info.buffer,
			pipeline_info.index_format,
			u32(bindings.index_buffer.offset),
		)
		state.current_index_buffer = true
	} else {
		state.current_index_buffer = false
	}

	resource_views: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	resource_views_by_stage: [3][MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	resource_view_mask: u32
	resource_view_native_masks: [3]u32
	resource_view_logical_masks: [3][MAX_BINDING_GROUPS]u32
	for group_views, group in bindings.views {
		for view, slot in group_views {
			if !view_valid(view) {
				continue
			}

			view_info, view_ok := state.views[view]
			if !view_ok {
				set_invalid_handle_error(ctx, "gfx.d3d11: resource view handle is unknown")
				return false
			}

			logical_mask := d3d11_slot_mask(u32(slot))
			if pipeline_info.has_binding_metadata {
				used := false
				for stage in 0..<3 {
					binding_slot := pipeline_info.view_slots[stage][group][slot]
					if !binding_slot.active {
						continue
					}

					used = true
					if !d3d11_validate_resource_view_binding(ctx, &view_info, binding_slot, u32(group), u32(slot), false) {
						return false
					}
					if binding_slot.view_kind == .Sampled {
						resource_views_by_stage[stage][int(binding_slot.native_slot)] = view_info.srv
						resource_view_native_masks[stage] |= d3d11_slot_mask(binding_slot.native_slot)
						resource_view_logical_masks[stage][group] |= logical_mask
					}
				}

				if !used {
					set_validation_errorf(ctx, "gfx.d3d11: resource view group %d slot %d is not used by the current pipeline", group, slot)
					return false
				}
			} else {
				if group != 0 {
					set_validation_errorf(ctx, "gfx.d3d11: resource view group %d requires shader binding metadata", group)
					return false
				}
				if view_info.srv == nil || view_info.kind != .Sampled {
					set_validation_error(ctx, "gfx.d3d11: shader resource binding requires a sampled view")
					return false
				}
				resource_views[slot] = view_info.srv
				resource_view_mask |= logical_mask
			}
		}
	}
	if pipeline_info.has_binding_metadata {
		vs_count := d3d11_binding_span(resource_view_native_masks[int(Shader_Stage.Vertex)])
		if vs_count > 0 {
			state.immediate.VSSetShaderResources(state.immediate, 0, vs_count, &resource_views_by_stage[int(Shader_Stage.Vertex)][0])
		}

		ps_count := d3d11_binding_span(resource_view_native_masks[int(Shader_Stage.Fragment)])
		if ps_count > 0 {
			state.immediate.PSSetShaderResources(state.immediate, 0, ps_count, &resource_views_by_stage[int(Shader_Stage.Fragment)][0])
		}
	} else {
		resource_view_count := d3d11_binding_span(resource_view_mask)
		if resource_view_count > 0 {
			state.immediate.PSSetShaderResources(state.immediate, 0, resource_view_count, &resource_views[0])
		}
	}

	samplers: [MAX_SAMPLERS]^d3d11.ISamplerState
	samplers_by_stage: [3][MAX_SAMPLERS]^d3d11.ISamplerState
	sampler_mask: u32
	sampler_native_masks: [3]u32
	sampler_logical_masks: [3][MAX_BINDING_GROUPS]u32
	for group_samplers, group in bindings.samplers {
		for sampler, slot in group_samplers {
			if !sampler_valid(sampler) {
				continue
			}

			sampler_info, sampler_ok := state.samplers[sampler]
			if !sampler_ok || sampler_info.sampler == nil {
				set_invalid_handle_error(ctx, "gfx.d3d11: sampler handle is unknown")
				return false
			}

			logical_mask := d3d11_slot_mask(u32(slot))
			if pipeline_info.has_binding_metadata {
				used := false
				for stage in 0..<3 {
					binding_slot := pipeline_info.sampler_slots[stage][group][slot]
					if !binding_slot.active {
						continue
					}

					used = true
					samplers_by_stage[stage][int(binding_slot.native_slot)] = sampler_info.sampler
					sampler_native_masks[stage] |= d3d11_slot_mask(binding_slot.native_slot)
					sampler_logical_masks[stage][group] |= logical_mask
				}

				if !used {
					set_validation_errorf(ctx, "gfx.d3d11: sampler group %d slot %d is not used by the current pipeline", group, slot)
					return false
				}
			} else {
				if group != 0 {
					set_validation_errorf(ctx, "gfx.d3d11: sampler group %d requires shader binding metadata", group)
					return false
				}
				samplers[slot] = sampler_info.sampler
				sampler_mask |= logical_mask
			}
		}
	}
	if pipeline_info.has_binding_metadata {
		vs_count := d3d11_binding_span(sampler_native_masks[int(Shader_Stage.Vertex)])
		if vs_count > 0 {
			state.immediate.VSSetSamplers(state.immediate, 0, vs_count, &samplers_by_stage[int(Shader_Stage.Vertex)][0])
		}

		ps_count := d3d11_binding_span(sampler_native_masks[int(Shader_Stage.Fragment)])
		if ps_count > 0 {
			state.immediate.PSSetSamplers(state.immediate, 0, ps_count, &samplers_by_stage[int(Shader_Stage.Fragment)][0])
		}
	} else {
		sampler_count := d3d11_binding_span(sampler_mask)
		if sampler_count > 0 {
			state.immediate.PSSetSamplers(state.immediate, 0, sampler_count, &samplers[0])
		}
	}

	if pipeline_info.has_binding_metadata {
		for stage in 0..<3 {
			state.current_bindings[stage].views = resource_view_logical_masks[stage]
			state.current_bindings[stage].samplers = sampler_logical_masks[stage]
		}
	} else {
		for stage in 0..<3 {
			state.current_bindings[stage].views[0] = resource_view_mask
			state.current_bindings[stage].samplers[0] = sampler_mask
		}
	}

	return true
}

d3d11_apply_compute_bindings :: proc(ctx: ^Context, bindings: Bindings) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.compute_pipelines[state.current_compute_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: apply_bindings requires an applied compute pipeline")
		return false
	}

	compute_stage := int(Shader_Stage.Compute)
	resource_views: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	unordered_views: [MAX_RESOURCE_VIEWS]^d3d11.IUnorderedAccessView
	resource_view_mask: u32
	unordered_view_mask: u32
	resource_view_logical_masks: [MAX_BINDING_GROUPS]u32
	for group_views, group in bindings.views {
		for view, slot in group_views {
			if !view_valid(view) {
				continue
			}

			view_info, view_ok := state.views[view]
			if !view_ok {
				set_invalid_handle_error(ctx, "gfx.d3d11: resource view handle is unknown")
				return false
			}

			logical_mask := d3d11_slot_mask(u32(slot))
			if pipeline_info.has_binding_metadata {
				binding_slot := pipeline_info.view_slots[compute_stage][group][slot]
				if !binding_slot.active {
					set_validation_errorf(ctx, "gfx.d3d11: resource view group %d slot %d is not used by the current compute pipeline", group, slot)
					return false
				}

				if !d3d11_validate_resource_view_binding(ctx, &view_info, binding_slot, u32(group), u32(slot), true) {
					return false
				}

				switch binding_slot.view_kind {
				case .Sampled:
					resource_views[int(binding_slot.native_slot)] = view_info.srv
					resource_view_mask |= d3d11_slot_mask(binding_slot.native_slot)
				case .Storage_Image:
					unordered_views[int(binding_slot.native_slot)] = view_info.uav
					unordered_view_mask |= d3d11_slot_mask(binding_slot.native_slot)
				case .Storage_Buffer:
					if binding_slot.access == .Read {
						resource_views[int(binding_slot.native_slot)] = view_info.srv
						resource_view_mask |= d3d11_slot_mask(binding_slot.native_slot)
					} else {
						unordered_views[int(binding_slot.native_slot)] = view_info.uav
						unordered_view_mask |= d3d11_slot_mask(binding_slot.native_slot)
					}
				case .Color_Attachment, .Depth_Stencil_Attachment:
				}
				resource_view_logical_masks[group] |= logical_mask
			} else {
				if group != 0 {
					set_validation_errorf(ctx, "gfx.d3d11: resource view group %d requires shader binding metadata", group)
					return false
				}
				switch view_info.kind {
				case .Sampled:
					if view_info.srv == nil {
						set_validation_error(ctx, "gfx.d3d11: shader resource binding requires a sampled view")
						return false
					}
					resource_views[slot] = view_info.srv
					resource_view_mask |= logical_mask
				case .Storage_Image, .Storage_Buffer:
					if slot >= D3D11_MAX_UAV_SLOTS {
						set_validation_errorf(ctx, "gfx.d3d11: storage resource view slot %d is out of range", slot)
						return false
					}
					if view_info.uav == nil {
						set_validation_error(ctx, "gfx.d3d11: storage resource binding requires a storage view")
						return false
					}
					unordered_views[slot] = view_info.uav
					unordered_view_mask |= logical_mask
				case .Color_Attachment, .Depth_Stencil_Attachment:
					set_validation_error(ctx, "gfx.d3d11: compute resource binding requires sampled or storage views")
					return false
				}
				resource_view_logical_masks[0] |= logical_mask
			}
		}
	}

	d3d11_clear_compute_resource_bindings(state)
	resource_view_count := d3d11_binding_span(resource_view_mask)
	if resource_view_count > 0 {
		state.immediate.CSSetShaderResources(state.immediate, 0, resource_view_count, &resource_views[0])
	}
	unordered_view_count := d3d11_binding_span(unordered_view_mask)
	if unordered_view_count > 0 {
		state.immediate.CSSetUnorderedAccessViews(state.immediate, 0, unordered_view_count, &unordered_views[0], nil)
	}

	samplers: [MAX_SAMPLERS]^d3d11.ISamplerState
	sampler_mask: u32
	sampler_logical_masks: [MAX_BINDING_GROUPS]u32
	for group_samplers, group in bindings.samplers {
		for sampler, slot in group_samplers {
			if !sampler_valid(sampler) {
				continue
			}

			sampler_info, sampler_ok := state.samplers[sampler]
			if !sampler_ok || sampler_info.sampler == nil {
				set_invalid_handle_error(ctx, "gfx.d3d11: sampler handle is unknown")
				return false
			}

			logical_mask := d3d11_slot_mask(u32(slot))
			if pipeline_info.has_binding_metadata {
				binding_slot := pipeline_info.sampler_slots[compute_stage][group][slot]
				if !binding_slot.active {
					set_validation_errorf(ctx, "gfx.d3d11: sampler group %d slot %d is not used by the current compute pipeline", group, slot)
					return false
				}

				samplers[int(binding_slot.native_slot)] = sampler_info.sampler
				sampler_mask |= d3d11_slot_mask(binding_slot.native_slot)
				sampler_logical_masks[group] |= logical_mask
			} else {
				if group != 0 {
					set_validation_errorf(ctx, "gfx.d3d11: sampler group %d requires shader binding metadata", group)
					return false
				}
				samplers[slot] = sampler_info.sampler
				sampler_mask |= logical_mask
				sampler_logical_masks[0] |= logical_mask
			}
		}
	}

	sampler_count := d3d11_binding_span(sampler_mask)
	if sampler_count > 0 {
		state.immediate.CSSetSamplers(state.immediate, 0, sampler_count, &samplers[0])
	}

	state.current_bindings[compute_stage].views = resource_view_logical_masks
	state.current_bindings[compute_stage].samplers = sampler_logical_masks
	return true
}

d3d11_apply_uniforms :: proc(ctx: ^Context, group: u32, slot: int, data: Range) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	if ctx.pass_kind == .Compute {
		return d3d11_apply_compute_uniforms(ctx, group, slot, data)
	}

	pipeline_info, pipeline_ok := state.pipelines[state.current_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: apply_uniforms requires an applied pipeline")
		return false
	}

	aligned_size := d3d11_uniform_buffer_size(data.size)
	if aligned_size == 0 || aligned_size > 64 * 1024 {
		set_validation_error(ctx, "gfx.d3d11: uniform data size is invalid")
		return false
	}

	if !d3d11_validate_uniform_upload(ctx, &pipeline_info, group, slot, data.size) {
		return false
	}

	if !d3d11_ensure_uniform_buffer(ctx, state, group, slot, aligned_size) {
		return false
	}

	buffer := state.uniform_buffers[group][slot]
	mapped: d3d11.MAPPED_SUBRESOURCE
	hr := state.immediate.Map(
		state.immediate,
		cast(^d3d11.IResource)buffer,
		0,
		.WRITE_DISCARD,
		{},
		&mapped,
	)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to map uniform buffer")
		return false
	}

	mem.copy(mapped.pData, data.ptr, data.size)
	if aligned_size > u32(data.size) {
		padding := int(aligned_size) - data.size
		padding_ptr := rawptr(uintptr(mapped.pData) + uintptr(data.size))
		mem.zero(padding_ptr, padding)
	}

	state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)buffer, 0)

	buffers := [1]^d3d11.IBuffer{buffer}
	slot_mask := d3d11_slot_mask(u32(slot))
	if pipeline_info.has_binding_metadata {
		vertex_slot := pipeline_info.uniform_slots[int(Shader_Stage.Vertex)][group][slot]
		if vertex_slot.active {
			state.immediate.VSSetConstantBuffers(state.immediate, vertex_slot.native_slot, 1, &buffers[0])
		}
		fragment_slot := pipeline_info.uniform_slots[int(Shader_Stage.Fragment)][group][slot]
		if fragment_slot.active {
			state.immediate.PSSetConstantBuffers(state.immediate, fragment_slot.native_slot, 1, &buffers[0])
		}
	} else {
		state.immediate.VSSetConstantBuffers(state.immediate, u32(slot), 1, &buffers[0])
		state.immediate.PSSetConstantBuffers(state.immediate, u32(slot), 1, &buffers[0])
	}
	if pipeline_info.has_binding_metadata {
		for stage in 0..<2 {
			if pipeline_info.uniform_slots[stage][group][slot].active {
				state.current_bindings[stage].uniforms[group] |= slot_mask
			}
		}
	} else {
		for stage in 0..<2 {
			state.current_bindings[stage].uniforms[0] |= slot_mask
		}
	}
	return true
}

d3d11_apply_compute_uniforms :: proc(ctx: ^Context, group: u32, slot: int, data: Range) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.compute_pipelines[state.current_compute_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: apply_uniforms requires an applied compute pipeline")
		return false
	}

	aligned_size := d3d11_uniform_buffer_size(data.size)
	if aligned_size == 0 || aligned_size > 64 * 1024 {
		set_validation_error(ctx, "gfx.d3d11: uniform data size is invalid")
		return false
	}

	if !d3d11_validate_compute_uniform_upload(ctx, &pipeline_info, group, slot, data.size) {
		return false
	}

	if !d3d11_ensure_uniform_buffer(ctx, state, group, slot, aligned_size) {
		return false
	}

	buffer := state.uniform_buffers[group][slot]
	mapped: d3d11.MAPPED_SUBRESOURCE
	hr := state.immediate.Map(
		state.immediate,
		cast(^d3d11.IResource)buffer,
		0,
		.WRITE_DISCARD,
		{},
		&mapped,
	)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to map uniform buffer")
		return false
	}

	mem.copy(mapped.pData, data.ptr, data.size)
	if aligned_size > u32(data.size) {
		padding := int(aligned_size) - data.size
		padding_ptr := rawptr(uintptr(mapped.pData) + uintptr(data.size))
		mem.zero(padding_ptr, padding)
	}

	state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)buffer, 0)

	buffers := [1]^d3d11.IBuffer{buffer}
	compute_stage := int(Shader_Stage.Compute)
	slot_mask := d3d11_slot_mask(u32(slot))
	if pipeline_info.has_binding_metadata {
		compute_slot := pipeline_info.uniform_slots[compute_stage][group][slot]
		if compute_slot.active {
			state.immediate.CSSetConstantBuffers(state.immediate, compute_slot.native_slot, 1, &buffers[0])
			state.current_bindings[compute_stage].uniforms[group] |= slot_mask
		}
	} else {
		state.immediate.CSSetConstantBuffers(state.immediate, u32(slot), 1, &buffers[0])
		state.current_bindings[compute_stage].uniforms[0] |= slot_mask
	}
	return true
}

d3d11_apply_uniform_at :: proc(ctx: ^Context, group: u32, slot: int, slice: Transient_Slice, byte_size: int) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	buffer_info, buffer_ok := state.buffers[slice.buffer]
	if !buffer_ok || buffer_info.buffer == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: transient slice buffer handle is unknown")
		return false
	}
	if u32(slice.offset) + u32(slice.size) > buffer_info.size {
		set_validation_error(ctx, "gfx.d3d11: apply_uniform_at: slice extends past buffer")
		return false
	}
	if !(.Uniform in buffer_info.usage) {
		set_validation_error(ctx, "gfx.d3d11: apply_uniform_at: buffer is not constant-buffer-capable")
		return false
	}

	if ctx.pass_kind == .Compute {
		return d3d11_apply_compute_uniform_at(ctx, state, group, slot, slice, byte_size, buffer_info.buffer)
	}

	pipeline_info, pipeline_ok := state.pipelines[state.current_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: apply_uniform_at requires an applied pipeline")
		return false
	}

	if !d3d11_validate_uniform_upload(ctx, &pipeline_info, group, slot, byte_size) {
		return false
	}

	// D3D11.0 forbids draws while a bound resource is mapped, and the
	// transient chunk is persistently mapped. Unmap it now so the draw can
	// read; a later transient_alloc on the same chunk will lazily re-Map.
	d3d11_transient_chunk_unmap_for_bind(ctx, slice.buffer)

	first_constant := u32(slice.offset) / 16
	num_constants := (u32(byte_size) + 15) / 16
	num_constants = ((num_constants + 15) / 16) * 16 // D3D11 requires NumConstants to be a multiple of 16 (256 bytes).

	slot_mask := d3d11_slot_mask(u32(slot))
	if state.context1 != nil {
		buffers := [1]^d3d11.IBuffer{buffer_info.buffer}
		first_constants := [1]u32{first_constant}
		num_constants_arr := [1]u32{num_constants}
		if pipeline_info.has_binding_metadata {
			vertex_slot := pipeline_info.uniform_slots[int(Shader_Stage.Vertex)][group][slot]
			if vertex_slot.active {
				state.context1.VSSetConstantBuffers1(state.context1, vertex_slot.native_slot, 1, &buffers[0], &first_constants[0], &num_constants_arr[0])
			}
			fragment_slot := pipeline_info.uniform_slots[int(Shader_Stage.Fragment)][group][slot]
			if fragment_slot.active {
				state.context1.PSSetConstantBuffers1(state.context1, fragment_slot.native_slot, 1, &buffers[0], &first_constants[0], &num_constants_arr[0])
			}
		} else {
			state.context1.VSSetConstantBuffers1(state.context1, u32(slot), 1, &buffers[0], &first_constants[0], &num_constants_arr[0])
			state.context1.PSSetConstantBuffers1(state.context1, u32(slot), 1, &buffers[0], &first_constants[0], &num_constants_arr[0])
		}
	} else {
		// Fallback: copy the slice payload into the per-slot dynamic CB and bind it.
		// Loses the transient allocator's bump-pointer benefit but keeps semantics.
		aligned_size := d3d11_uniform_buffer_size(byte_size)
		if aligned_size == 0 || aligned_size > 64 * 1024 {
			set_validation_error(ctx, "gfx.d3d11: apply_uniform_at: byte_size is invalid")
			return false
		}
		if !d3d11_ensure_uniform_buffer(ctx, state, group, slot, aligned_size) {
			return false
		}

		buffer := state.uniform_buffers[group][slot]
		mapped: d3d11.MAPPED_SUBRESOURCE
		hr := state.immediate.Map(state.immediate, cast(^d3d11.IResource)buffer, 0, .WRITE_DISCARD, {}, &mapped)
		if d3d11_failed(hr) {
			set_backend_error(ctx, "gfx.d3d11: failed to map uniform buffer")
			return false
		}
		mem.copy(mapped.pData, slice.mapped, byte_size)
		if aligned_size > u32(byte_size) {
			padding := int(aligned_size) - byte_size
			padding_ptr := rawptr(uintptr(mapped.pData) + uintptr(byte_size))
			mem.zero(padding_ptr, padding)
		}
		state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)buffer, 0)

		buffers := [1]^d3d11.IBuffer{buffer}
		if pipeline_info.has_binding_metadata {
			vertex_slot := pipeline_info.uniform_slots[int(Shader_Stage.Vertex)][group][slot]
			if vertex_slot.active {
				state.immediate.VSSetConstantBuffers(state.immediate, vertex_slot.native_slot, 1, &buffers[0])
			}
			fragment_slot := pipeline_info.uniform_slots[int(Shader_Stage.Fragment)][group][slot]
			if fragment_slot.active {
				state.immediate.PSSetConstantBuffers(state.immediate, fragment_slot.native_slot, 1, &buffers[0])
			}
		} else {
			state.immediate.VSSetConstantBuffers(state.immediate, u32(slot), 1, &buffers[0])
			state.immediate.PSSetConstantBuffers(state.immediate, u32(slot), 1, &buffers[0])
		}
	}

	if pipeline_info.has_binding_metadata {
		for stage in 0..<2 {
			if pipeline_info.uniform_slots[stage][group][slot].active {
				state.current_bindings[stage].uniforms[group] |= slot_mask
			}
		}
	} else {
		for stage in 0..<2 {
			state.current_bindings[stage].uniforms[0] |= slot_mask
		}
	}
	return true
}

@(private)
d3d11_apply_compute_uniform_at :: proc(ctx: ^Context, state: ^D3D11_State, group: u32, slot: int, slice: Transient_Slice, byte_size: int, native_buffer: ^d3d11.IBuffer) -> bool {
	pipeline_info, pipeline_ok := state.compute_pipelines[state.current_compute_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: apply_uniform_at requires an applied compute pipeline")
		return false
	}
	if !d3d11_validate_compute_uniform_upload(ctx, &pipeline_info, group, slot, byte_size) {
		return false
	}

	d3d11_transient_chunk_unmap_for_bind(ctx, slice.buffer)

	first_constant := u32(slice.offset) / 16
	num_constants := (u32(byte_size) + 15) / 16
	num_constants = ((num_constants + 15) / 16) * 16

	compute_stage := int(Shader_Stage.Compute)
	slot_mask := d3d11_slot_mask(u32(slot))
	if state.context1 != nil {
		buffers := [1]^d3d11.IBuffer{native_buffer}
		first_constants := [1]u32{first_constant}
		num_constants_arr := [1]u32{num_constants}
		if pipeline_info.has_binding_metadata {
			compute_slot := pipeline_info.uniform_slots[compute_stage][group][slot]
			if compute_slot.active {
				state.context1.CSSetConstantBuffers1(state.context1, compute_slot.native_slot, 1, &buffers[0], &first_constants[0], &num_constants_arr[0])
				state.current_bindings[compute_stage].uniforms[group] |= slot_mask
			}
		} else {
			state.context1.CSSetConstantBuffers1(state.context1, u32(slot), 1, &buffers[0], &first_constants[0], &num_constants_arr[0])
			state.current_bindings[compute_stage].uniforms[0] |= slot_mask
		}
		return true
	}

	aligned_size := d3d11_uniform_buffer_size(byte_size)
	if aligned_size == 0 || aligned_size > 64 * 1024 {
		set_validation_error(ctx, "gfx.d3d11: apply_uniform_at: byte_size is invalid")
		return false
	}
	if !d3d11_ensure_uniform_buffer(ctx, state, group, slot, aligned_size) {
		return false
	}
	buffer := state.uniform_buffers[group][slot]
	mapped: d3d11.MAPPED_SUBRESOURCE
	hr := state.immediate.Map(state.immediate, cast(^d3d11.IResource)buffer, 0, .WRITE_DISCARD, {}, &mapped)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to map uniform buffer")
		return false
	}
	mem.copy(mapped.pData, slice.mapped, byte_size)
	if aligned_size > u32(byte_size) {
		padding := int(aligned_size) - byte_size
		padding_ptr := rawptr(uintptr(mapped.pData) + uintptr(byte_size))
		mem.zero(padding_ptr, padding)
	}
	state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)buffer, 0)

	buffers := [1]^d3d11.IBuffer{buffer}
	if pipeline_info.has_binding_metadata {
		compute_slot := pipeline_info.uniform_slots[compute_stage][group][slot]
		if compute_slot.active {
			state.immediate.CSSetConstantBuffers(state.immediate, compute_slot.native_slot, 1, &buffers[0])
			state.current_bindings[compute_stage].uniforms[group] |= slot_mask
		}
	} else {
		state.immediate.CSSetConstantBuffers(state.immediate, u32(slot), 1, &buffers[0])
		state.current_bindings[compute_stage].uniforms[0] |= slot_mask
	}
	return true
}

d3d11_draw :: proc(ctx: ^Context, base_element: i32, num_elements: i32, num_instances: i32) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.pipelines[state.current_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: draw requires an applied pipeline")
		return false
	}

	if !d3d11_validate_draw_bindings(ctx, state, &pipeline_info) {
		return false
	}

	if pipeline_info.has_index_buffer {
		if num_instances > 1 {
			state.immediate.DrawIndexedInstanced(
				state.immediate,
				u32(num_elements),
				u32(num_instances),
				u32(base_element),
				0,
				0,
			)
		} else {
			state.immediate.DrawIndexed(state.immediate, u32(num_elements), u32(base_element), 0)
		}
	} else {
		if num_instances > 1 {
			state.immediate.DrawInstanced(
				state.immediate,
				u32(num_elements),
				u32(num_instances),
				u32(base_element),
				0,
			)
		} else {
			state.immediate.Draw(state.immediate, u32(num_elements), u32(base_element))
		}
	}

	return true
}

d3d11_dispatch :: proc(ctx: ^Context, group_count_x, group_count_y, group_count_z: u32) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.compute_pipelines[state.current_compute_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: dispatch requires an applied compute pipeline")
		return false
	}

	if group_count_x > d3d11.CS_DISPATCH_MAX_THREAD_GROUPS_PER_DIMENSION ||
	   group_count_y > d3d11.CS_DISPATCH_MAX_THREAD_GROUPS_PER_DIMENSION ||
	   group_count_z > d3d11.CS_DISPATCH_MAX_THREAD_GROUPS_PER_DIMENSION {
		set_validation_error(ctx, "gfx.d3d11: dispatch thread group count exceeds D3D11 limits")
		return false
	}

	if !d3d11_validate_dispatch_bindings(ctx, state, &pipeline_info) {
		return false
	}

	state.immediate.Dispatch(state.immediate, group_count_x, group_count_y, group_count_z)
	return true
}

d3d11_draw_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: u32) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.pipelines[state.current_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: draw_indirect requires an applied pipeline")
		return false
	}

	if !d3d11_validate_draw_bindings(ctx, state, &pipeline_info) {
		return false
	}

	buffer_info, buffer_ok := state.buffers[indirect_buffer]
	if !buffer_ok || buffer_info.buffer == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: indirect buffer handle is unknown")
		return false
	}

	// D3D11 has no native multi-draw indirect; loop one DrawInstancedIndirect
	// per record. Implicit transitions handle the buffer state.
	for i in 0..<draw_count {
		arg_offset := u32(offset) + i * stride
		state.immediate.DrawInstancedIndirect(state.immediate, buffer_info.buffer, arg_offset)
	}
	return true
}

d3d11_draw_indexed_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int, draw_count: u32, stride: u32) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	pipeline_info, pipeline_ok := state.pipelines[state.current_pipeline]
	if !pipeline_ok {
		set_validation_error(ctx, "gfx.d3d11: draw_indexed_indirect requires an applied pipeline")
		return false
	}
	if !pipeline_info.has_index_buffer {
		set_validation_error(ctx, "gfx.d3d11: draw_indexed_indirect requires a pipeline with an index buffer")
		return false
	}

	if !d3d11_validate_draw_bindings(ctx, state, &pipeline_info) {
		return false
	}

	buffer_info, buffer_ok := state.buffers[indirect_buffer]
	if !buffer_ok || buffer_info.buffer == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: indirect buffer handle is unknown")
		return false
	}

	for i in 0..<draw_count {
		arg_offset := u32(offset) + i * stride
		state.immediate.DrawIndexedInstancedIndirect(state.immediate, buffer_info.buffer, arg_offset)
	}
	return true
}

d3d11_dispatch_indirect :: proc(ctx: ^Context, indirect_buffer: Buffer, offset: int) -> bool {
	panic("gfx.d3d11: dispatch_indirect is unimplemented (APE-7 declaration only; backend lands in APE-9)")
}

d3d11_end_pass :: proc(ctx: ^Context) -> bool {
	state := d3d11_state(ctx)
	if state != nil {
		if state.immediate != nil {
			state.immediate.OMSetRenderTargets(state.immediate, 0, nil, nil)
		}
		state.current_pipeline = Pipeline_Invalid
		state.current_compute_pipeline = Compute_Pipeline_Invalid
		state.current_vertex_buffers = 0
		state.current_index_buffer = false
		state.current_bindings = {}
		state.current_pass_color_formats = {}
		state.current_pass_has_color = false
		state.current_pass_depth_format = .Invalid
		state.current_pass_has_depth = false
	}
	return true
}

d3d11_end_compute_pass :: proc(ctx: ^Context) -> bool {
	state := d3d11_state(ctx)
	if state != nil {
		if state.immediate != nil {
			d3d11_clear_compute_resource_bindings(state)
			state.immediate.CSSetShader(state.immediate, nil, nil, 0)
		}
		state.current_pipeline = Pipeline_Invalid
		state.current_compute_pipeline = Compute_Pipeline_Invalid
		state.current_vertex_buffers = 0
		state.current_index_buffer = false
		state.current_bindings = {}
		state.current_pass_color_formats = {}
		state.current_pass_has_color = false
		state.current_pass_depth_format = .Invalid
		state.current_pass_has_depth = false
	}
	return true
}

// d3d11_barrier no-ops the public barrier verb on D3D11.
//
// D3D11 has no public concept of resource state or pipeline barrier — the
// runtime/driver handles transitions implicitly when a resource is bound.
// The schema is still the explicit one (gfx-barriers-note.md §9.6); the
// validator in barriers.odin runs ahead of this call and is the entire
// observable behavior in debug builds. The release-build call is a true
// no-op so user code costs nothing.
d3d11_barrier :: proc(ctx: ^Context, desc: Barrier_Desc) -> bool {
	return true
}

d3d11_commit :: proc(ctx: ^Context) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.swapchain == nil {
		set_backend_error(ctx, "gfx.d3d11: swapchain is not initialized")
		return false
	}

	hr := state.swapchain.Present(state.swapchain, state.sync_interval, {})
	if d3d11_failed(hr) {
		if !d3d11_drain_info_queue(ctx, state, "Present failure") {
			return false
		}
		d3d11_set_error_hr(ctx, state, "gfx.d3d11: Present failed", hr)
		return false
	}
	if !d3d11_drain_info_queue(ctx, state, "Present") {
		return false
	}

	return true
}

d3d11_clear_graphics_resource_bindings :: proc(state: ^D3D11_State) {
	if state == nil || state.immediate == nil {
		return
	}

	null_srvs: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	state.immediate.VSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	state.immediate.PSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
}

d3d11_clear_compute_resource_bindings :: proc(state: ^D3D11_State) {
	if state == nil || state.immediate == nil {
		return
	}

	null_srvs: [MAX_RESOURCE_VIEWS]^d3d11.IShaderResourceView
	null_uavs: [D3D11_MAX_UAV_SLOTS]^d3d11.IUnorderedAccessView
	state.immediate.CSSetShaderResources(state.immediate, 0, MAX_RESOURCE_VIEWS, &null_srvs[0])
	state.immediate.CSSetUnorderedAccessViews(state.immediate, 0, D3D11_MAX_UAV_SLOTS, &null_uavs[0], nil)
}

d3d11_ensure_uniform_buffer :: proc(ctx: ^Context, state: ^D3D11_State, group: u32, slot: int, size: u32) -> bool {
	if state.uniform_buffers[group][slot] != nil && state.uniform_buffer_sizes[group][slot] >= size {
		return true
	}

	if state.uniform_buffers[group][slot] != nil {
		state.uniform_buffers[group][slot].Release(state.uniform_buffers[group][slot])
		state.uniform_buffers[group][slot] = nil
		state.uniform_buffer_sizes[group][slot] = 0
	}

	desc := d3d11.BUFFER_DESC {
		ByteWidth = size,
		Usage = .DYNAMIC,
		BindFlags = d3d11.BIND_FLAGS{.CONSTANT_BUFFER},
		CPUAccessFlags = d3d11.CPU_ACCESS_FLAGS{.WRITE},
		MiscFlags = {},
		StructureByteStride = 0,
	}

	hr := state.device.CreateBuffer(state.device, &desc, nil, &state.uniform_buffers[group][slot])
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to create uniform buffer")
		return false
	}
	label_storage: [64]u8
	label := fmt.bprintf(label_storage[:], "uniform buffer %d:%d", group, slot)
	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)state.uniform_buffers[group][slot], label)

	state.uniform_buffer_sizes[group][slot] = size
	return true
}

d3d11_uniform_buffer_size :: proc(size: int) -> u32 {
	if size <= 0 {
		return 0
	}

	aligned := ((size + 15) / 16) * 16
	return u32(aligned)
}

d3d11_validate_pipeline_pass_compatibility :: proc(ctx: ^Context, state: ^D3D11_State, pipeline_info: ^D3D11_Pipeline) -> bool {
	if pipeline_info.depth_only && state.current_pass_has_color {
		set_validation_error(ctx, "gfx.d3d11: depth-only pipeline cannot be applied to a pass with color attachments")
		return false
	}

	for slot in 0..<MAX_COLOR_ATTACHMENTS {
		pipeline_format := pipeline_info.color_formats[slot]
		pass_format := state.current_pass_color_formats[slot]

		if pass_format != .Invalid && pipeline_format == .Invalid {
			set_validation_errorf(ctx, "gfx.d3d11: active pass color attachment slot %d has no matching pipeline color format", slot)
			return false
		}
		if pipeline_format == .Invalid {
			continue
		}

		if pass_format == .Invalid {
			set_validation_errorf(ctx, "gfx.d3d11: pipeline requires color attachment slot %d", slot)
			return false
		}
		if pipeline_format != pass_format {
			set_validation_errorf(ctx, "gfx.d3d11: pipeline color format mismatch at slot %d", slot)
			return false
		}
	}

	if pipeline_info.depth_enabled {
		if !state.current_pass_has_depth {
			set_validation_error(ctx, "gfx.d3d11: depth-enabled pipeline requires a depth attachment")
			return false
		}
		if pipeline_info.depth_format != state.current_pass_depth_format {
			set_validation_error(ctx, "gfx.d3d11: pipeline depth format does not match the active pass")
			return false
		}
	}

	return true
}

d3d11_validate_draw_bindings :: proc(ctx: ^Context, state: ^D3D11_State, pipeline_info: ^D3D11_Pipeline) -> bool {
	missing_vertex_buffers := pipeline_info.required_vertex_buffers & ~state.current_vertex_buffers
	if missing_vertex_buffers != 0 {
		set_validation_errorf(ctx, "gfx.d3d11: missing required vertex buffer slot %d", d3d11_first_binding_slot(missing_vertex_buffers))
		return false
	}

	if pipeline_info.has_index_buffer && !state.current_index_buffer {
		set_validation_error(ctx, "gfx.d3d11: indexed pipeline requires an index buffer")
		return false
	}

	if !pipeline_info.has_binding_metadata {
		return true
	}

	for stage in 0..<2 {
		required := pipeline_info.required[stage]
		current := state.current_bindings[stage]

		for group in 0..<MAX_BINDING_GROUPS {
			missing_uniforms := required.uniforms[group] & ~current.uniforms[group]
			if missing_uniforms != 0 {
				set_validation_errorf(
					ctx,
					"gfx.d3d11: missing required %s uniform group %d slot %d",
					d3d11_stage_name(stage),
					group,
					d3d11_first_binding_slot(missing_uniforms),
				)
				return false
			}

			missing_views := required.views[group] & ~current.views[group]
			if missing_views != 0 {
				set_validation_errorf(
					ctx,
					"gfx.d3d11: missing required %s resource view group %d slot %d",
					d3d11_stage_name(stage),
					group,
					d3d11_first_binding_slot(missing_views),
				)
				return false
			}

			missing_samplers := required.samplers[group] & ~current.samplers[group]
			if missing_samplers != 0 {
				set_validation_errorf(
					ctx,
					"gfx.d3d11: missing required %s sampler group %d slot %d",
					d3d11_stage_name(stage),
					group,
					d3d11_first_binding_slot(missing_samplers),
				)
				return false
			}
		}
	}

	return true
}

d3d11_validate_resource_view_binding :: proc(
	ctx: ^Context,
	view_info: ^D3D11_View,
	binding_slot: D3D11_Binding_Slot,
	logical_group: u32,
	logical_slot: u32,
	allow_storage: bool,
) -> bool {
	expected_kind := binding_slot.view_kind
	if !d3d11_resource_view_kind_supported(expected_kind) {
		set_unsupported_errorf(ctx, "gfx.d3d11: resource view group %d slot %d has unsupported reflected view kind", logical_group, logical_slot)
		return false
	}

	if view_info.kind != expected_kind {
		set_validation_errorf(
			ctx,
			"gfx.d3d11: resource view group %d slot %d expects %s view, got %s view",
			logical_group,
			logical_slot,
			d3d11_view_kind_name(expected_kind),
			d3d11_view_kind_name(view_info.kind),
		)
		return false
	}

	switch expected_kind {
	case .Sampled:
		if view_info.srv == nil {
			set_validation_errorf(ctx, "gfx.d3d11: sampled resource view group %d slot %d has no shader resource view", logical_group, logical_slot)
			return false
		}
		return true
	case .Storage_Image, .Storage_Buffer:
		if view_info.uav == nil {
			set_validation_errorf(ctx, "gfx.d3d11: storage resource view group %d slot %d has no unordered access view", logical_group, logical_slot)
			return false
		}
		if !allow_storage {
			set_unsupported_errorf(ctx, "gfx.d3d11: storage resource view group %d slot %d is reflected but storage bindings are not implemented for graphics passes yet", logical_group, logical_slot)
			return false
		}
		if expected_kind == .Storage_Image &&
		   binding_slot.storage_image_format != .Invalid &&
		   view_info.format != binding_slot.storage_image_format {
			set_validation_errorf(
				ctx,
				"gfx.d3d11: storage image resource view group %d slot %d expects format %s, got %s",
				logical_group,
				logical_slot,
				d3d11_pixel_format_name(binding_slot.storage_image_format),
				d3d11_pixel_format_name(view_info.format),
			)
			return false
		}
		if expected_kind == .Storage_Buffer {
			if binding_slot.storage_buffer_stride > 0 && view_info.storage_stride != binding_slot.storage_buffer_stride {
				set_validation_errorf(
					ctx,
					"gfx.d3d11: storage buffer resource view group %d slot %d expects stride %d, got %d",
					logical_group,
					logical_slot,
					binding_slot.storage_buffer_stride,
					view_info.storage_stride,
				)
				return false
			}
			if binding_slot.access == .Read && view_info.srv == nil {
				set_validation_errorf(ctx, "gfx.d3d11: storage buffer resource view group %d slot %d has no shader resource view", logical_group, logical_slot)
				return false
			}
			if binding_slot.access != .Read && view_info.uav == nil {
				set_validation_errorf(ctx, "gfx.d3d11: storage buffer resource view group %d slot %d has no unordered access view", logical_group, logical_slot)
				return false
			}
		}
		return true
	case .Color_Attachment, .Depth_Stencil_Attachment:
	}

	return false
}

d3d11_resource_view_kind_supported :: proc(kind: View_Kind) -> bool {
	switch kind {
	case .Sampled, .Storage_Image, .Storage_Buffer:
		return true
	case .Color_Attachment, .Depth_Stencil_Attachment:
		return false
	}

	return false
}

d3d11_validate_uniform_upload :: proc(ctx: ^Context, pipeline_info: ^D3D11_Pipeline, group: u32, slot: int, size: int) -> bool {
	if !pipeline_info.has_binding_metadata {
		if group != 0 {
			set_validation_errorf(ctx, "gfx.d3d11: uniform group %d requires shader binding metadata", group)
			return false
		}
		return true
	}

	slot_mask := d3d11_slot_mask(u32(slot))
	used := false
	expected_size: u32
	for stage in 0..<2 {
		if pipeline_info.required[stage].uniforms[group] & slot_mask == 0 {
			continue
		}

		used = true
		reflected_size := pipeline_info.uniform_slots[stage][group][slot].size
		if reflected_size == 0 {
			continue
		}
		if expected_size != 0 && expected_size != reflected_size {
			set_validation_errorf(ctx, "gfx.d3d11: uniform group %d slot %d has conflicting reflected sizes across stages", group, slot)
			return false
		}
		expected_size = reflected_size
	}

	if !used {
		set_validation_errorf(ctx, "gfx.d3d11: uniform group %d slot %d is not used by the current pipeline", group, slot)
		return false
	}
	if expected_size != 0 && u32(size) != expected_size {
		set_validation_errorf(ctx, "gfx.d3d11: uniform group %d slot %d data size %d does not match reflected size %d", group, slot, size, expected_size)
		return false
	}

	return true
}

d3d11_validate_compute_uniform_upload :: proc(ctx: ^Context, pipeline_info: ^D3D11_Compute_Pipeline, group: u32, slot: int, size: int) -> bool {
	if !pipeline_info.has_binding_metadata {
		if group != 0 {
			set_validation_errorf(ctx, "gfx.d3d11: uniform group %d requires shader binding metadata", group)
			return false
		}
		return true
	}

	compute_stage := int(Shader_Stage.Compute)
	binding_slot := pipeline_info.uniform_slots[compute_stage][group][slot]
	if !binding_slot.active {
		set_validation_errorf(ctx, "gfx.d3d11: uniform group %d slot %d is not used by the current compute pipeline", group, slot)
		return false
	}
	if binding_slot.size != 0 && u32(size) != binding_slot.size {
		set_validation_errorf(ctx, "gfx.d3d11: uniform group %d slot %d data size %d does not match reflected size %d", group, slot, size, binding_slot.size)
		return false
	}

	return true
}

d3d11_validate_dispatch_bindings :: proc(ctx: ^Context, state: ^D3D11_State, pipeline_info: ^D3D11_Compute_Pipeline) -> bool {
	if !pipeline_info.has_binding_metadata {
		return true
	}

	stage := int(Shader_Stage.Compute)
	required := pipeline_info.required[stage]
	current := state.current_bindings[stage]

	for group in 0..<MAX_BINDING_GROUPS {
		missing_uniforms := required.uniforms[group] & ~current.uniforms[group]
		if missing_uniforms != 0 {
			set_validation_errorf(
				ctx,
				"gfx.d3d11: missing required compute uniform group %d slot %d",
				group,
				d3d11_first_binding_slot(missing_uniforms),
			)
			return false
		}

		missing_views := required.views[group] & ~current.views[group]
		if missing_views != 0 {
			set_validation_errorf(
				ctx,
				"gfx.d3d11: missing required compute resource view group %d slot %d",
				group,
				d3d11_first_binding_slot(missing_views),
			)
			return false
		}

		missing_samplers := required.samplers[group] & ~current.samplers[group]
		if missing_samplers != 0 {
			set_validation_errorf(
				ctx,
				"gfx.d3d11: missing required compute sampler group %d slot %d",
				group,
				d3d11_first_binding_slot(missing_samplers),
			)
			return false
		}
	}

	return true
}

d3d11_slot_mask :: proc(slot: u32) -> u32 {
	return u32(1) << slot
}

d3d11_binding_count :: proc(mask: u32) -> u32 {
	count: u32
	remaining := mask
	for remaining != 0 {
		count += 1
		remaining >>= 1
	}
	return count
}

d3d11_binding_span :: proc(mask: u32) -> u32 {
	span: u32
	for slot in 0..<32 {
		slot_u32 := u32(slot)
		if mask & d3d11_slot_mask(slot_u32) != 0 {
			span = slot_u32 + 1
		}
	}
	return span
}

d3d11_first_binding_slot :: proc(mask: u32) -> u32 {
	for slot in 0..<32 {
		slot_u32 := u32(slot)
		if mask & d3d11_slot_mask(slot_u32) != 0 {
			return slot_u32
		}
	}
	return 0
}
