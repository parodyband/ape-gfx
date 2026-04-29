#+private
package gfx

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import win32 "core:sys/windows"

d3d11_create_pipeline :: proc(ctx: ^Context, handle: Pipeline, desc: Pipeline_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	shader_info, shader_ok := state.shaders[desc.shader]
	if !shader_ok {
		set_invalid_handle_error(ctx, "gfx.d3d11: pipeline shader handle is unknown")
		return false
	}
	if shader_info.vertex == nil || shader_info.pixel == nil {
		set_validation_error(ctx, "gfx.d3d11: graphics pipeline requires vertex and fragment shaders")
		return false
	}

	pipeline_info := D3D11_Pipeline {
		shader = desc.shader,
		topology = d3d11_primitive_topology(desc.primitive_type),
		index_format = d3d11_index_format(desc.index_type),
		has_index_buffer = desc.index_type != .None,
		required = shader_info.required,
		uniform_slots = shader_info.uniform_slots,
		view_slots = shader_info.view_slots,
		sampler_slots = shader_info.sampler_slots,
		has_binding_metadata = shader_info.has_binding_metadata,
		depth_format = desc.depth.format,
		depth_enabled = desc.depth.enabled,
		depth_only = desc.depth_only,
	}

	for slot in 0..<MAX_COLOR_ATTACHMENTS {
		pipeline_info.color_formats[slot] = desc.color_formats[slot]
	}
	if desc.depth_only {
		if !desc.depth.enabled {
			d3d11_release_pipeline(&pipeline_info)
			set_validation_error(ctx, "gfx.d3d11: depth-only pipeline requires depth to be enabled")
			return false
		}
		for format in pipeline_info.color_formats {
			if format != .Invalid {
				d3d11_release_pipeline(&pipeline_info)
				set_validation_error(ctx, "gfx.d3d11: depth-only pipeline cannot declare color formats")
				return false
			}
		}
	} else if pipeline_info.color_formats[0] == .Invalid {
		pipeline_info.color_formats[0] = ctx.desc.swapchain_format
	}
	if pipeline_info.depth_enabled && pipeline_info.depth_format == .Invalid {
		d3d11_release_pipeline(&pipeline_info)
		set_validation_error(ctx, "gfx.d3d11: depth-enabled pipeline requires a depth format")
		return false
	}

	for i in 0..<MAX_VERTEX_BUFFERS {
		pipeline_info.vertex_strides[i] = desc.layout.buffers[i].stride
	}

	if !d3d11_validate_pipeline_vertex_inputs(ctx, shader_info, desc.layout) {
		d3d11_release_pipeline(&pipeline_info)
		return false
	}

	input_elements: [MAX_VERTEX_ATTRIBUTES]d3d11.INPUT_ELEMENT_DESC
	input_count: u32
	for attr in desc.layout.attrs {
		if attr.format == .Invalid || attr.semantic == nil {
			continue
		}

		if attr.buffer_slot >= MAX_VERTEX_BUFFERS {
			d3d11_release_pipeline(&pipeline_info)
			set_validation_error(ctx, "gfx.d3d11: vertex attribute buffer slot is out of range")
			return false
		}

		if desc.layout.buffers[int(attr.buffer_slot)].stride == 0 {
			d3d11_release_pipeline(&pipeline_info)
			set_validation_errorf(ctx, "gfx.d3d11: vertex buffer slot %d has zero stride", attr.buffer_slot)
			return false
		}

		input_elements[int(input_count)] = d3d11.INPUT_ELEMENT_DESC {
			SemanticName = attr.semantic,
			SemanticIndex = attr.semantic_index,
			Format = d3d11_vertex_format(attr.format),
			InputSlot = attr.buffer_slot,
			AlignedByteOffset = attr.offset,
			InputSlotClass = d3d11_input_class(desc.layout.buffers[int(attr.buffer_slot)].step_func),
			InstanceDataStepRate = desc.layout.buffers[int(attr.buffer_slot)].step_rate,
		}
		pipeline_info.required_vertex_buffers |= d3d11_slot_mask(attr.buffer_slot)
		input_count += 1
	}

	if input_count > 0 {
		if len(shader_info.vertex_bytecode) == 0 {
			set_validation_error(ctx, "gfx.d3d11: vertex shader bytecode signature is unavailable")
			return false
		}

		hr := state.device.CreateInputLayout(
			state.device,
			raw_data(input_elements[:]),
			input_count,
			raw_data(shader_info.vertex_bytecode),
			d3d11.SIZE_T(len(shader_info.vertex_bytecode)),
			&pipeline_info.input_layout,
		)
		if d3d11_failed(hr) {
			d3d11_release_pipeline(&pipeline_info)
			set_backend_error(ctx, "gfx.d3d11: CreateInputLayout failed")
			return false
		}
		d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)pipeline_info.input_layout, desc.label, "input layout")
	}

	if !d3d11_create_pipeline_states(ctx, state, &pipeline_info, desc) {
		d3d11_release_pipeline(&pipeline_info)
		return false
	}
	d3d11_set_pipeline_debug_names(&pipeline_info, desc.label)

	state.pipelines[handle] = pipeline_info
	return true
}

d3d11_destroy_pipeline :: proc(ctx: ^Context, handle: Pipeline) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if pipeline_info, ok := state.pipelines[handle]; ok {
		d3d11_release_pipeline(&pipeline_info)
		delete_key(&state.pipelines, handle)
		if state.current_pipeline == handle {
			state.current_pipeline = Pipeline_Invalid
		}
	}
}

d3d11_create_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline, desc: Compute_Pipeline_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	shader_info, shader_ok := state.shaders[desc.shader]
	if !shader_ok {
		set_invalid_handle_error(ctx, "gfx.d3d11: compute pipeline shader handle is unknown")
		return false
	}
	if shader_info.compute == nil {
		set_validation_error(ctx, "gfx.d3d11: compute pipeline requires a compute shader")
		return false
	}

	state.compute_pipelines[handle] = D3D11_Compute_Pipeline {
		shader = desc.shader,
		required = shader_info.required,
		uniform_slots = shader_info.uniform_slots,
		view_slots = shader_info.view_slots,
		sampler_slots = shader_info.sampler_slots,
		has_binding_metadata = shader_info.has_binding_metadata,
	}
	return true
}

d3d11_destroy_compute_pipeline :: proc(ctx: ^Context, handle: Compute_Pipeline) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if _, ok := state.compute_pipelines[handle]; ok {
		delete_key(&state.compute_pipelines, handle)
		if state.current_compute_pipeline == handle {
			state.current_compute_pipeline = Compute_Pipeline_Invalid
		}
	}
}

d3d11_create_pipeline_states :: proc(ctx: ^Context, state: ^D3D11_State, pipeline_info: ^D3D11_Pipeline, desc: Pipeline_Desc) -> bool {
	raster_desc := d3d11.RASTERIZER_DESC {
		FillMode = d3d11_fill_mode(desc.raster.fill_mode),
		CullMode = d3d11_cull_mode(desc.raster.cull_mode),
		FrontCounterClockwise = d3d11_bool(desc.raster.winding == .Counter_Clockwise),
		DepthBias = 0,
		DepthBiasClamp = 0,
		SlopeScaledDepthBias = 0,
		DepthClipEnable = win32.TRUE,
		ScissorEnable = win32.FALSE,
		MultisampleEnable = win32.FALSE,
		AntialiasedLineEnable = win32.FALSE,
	}
	hr := state.device.CreateRasterizerState(state.device, &raster_desc, &pipeline_info.raster_state)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: CreateRasterizerState failed")
		return false
	}

	depth_desc := d3d11.DEPTH_STENCIL_DESC {
		DepthEnable = d3d11_bool(desc.depth.enabled),
		DepthWriteMask = d3d11_depth_write_mask(desc.depth.write_enabled),
		DepthFunc = d3d11_compare_func(desc.depth.compare),
		StencilEnable = win32.FALSE,
		StencilReadMask = 0xff,
		StencilWriteMask = 0xff,
		FrontFace = d3d11_default_stencil_op_desc(),
		BackFace = d3d11_default_stencil_op_desc(),
	}
	hr = state.device.CreateDepthStencilState(state.device, &depth_desc, &pipeline_info.depth_stencil_state)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: CreateDepthStencilState failed")
		return false
	}

	blend_desc: d3d11.BLEND_DESC
	blend_desc.AlphaToCoverageEnable = win32.FALSE
	blend_desc.IndependentBlendEnable = win32.FALSE
	for i in 0..<8 {
		blend_desc.RenderTarget[i] = d3d11_render_target_blend_desc(desc.colors[i])
	}

	hr = state.device.CreateBlendState(state.device, &blend_desc, &pipeline_info.blend_state)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: CreateBlendState failed")
		return false
	}

	return true
}

d3d11_release_pipeline :: proc(pipeline_info: ^D3D11_Pipeline) {
	if pipeline_info == nil {
		return
	}

	if pipeline_info.input_layout != nil {
		pipeline_info.input_layout.Release(pipeline_info.input_layout)
		pipeline_info.input_layout = nil
	}
	if pipeline_info.raster_state != nil {
		pipeline_info.raster_state.Release(pipeline_info.raster_state)
		pipeline_info.raster_state = nil
	}
	if pipeline_info.depth_stencil_state != nil {
		pipeline_info.depth_stencil_state.Release(pipeline_info.depth_stencil_state)
		pipeline_info.depth_stencil_state = nil
	}
	if pipeline_info.blend_state != nil {
		pipeline_info.blend_state.Release(pipeline_info.blend_state)
		pipeline_info.blend_state = nil
	}
}

d3d11_validate_pipeline_vertex_inputs :: proc(ctx: ^Context, shader_info: D3D11_Shader, layout: Layout_Desc) -> bool {
	if !shader_info.has_vertex_input_metadata {
		return true
	}

	for input in shader_info.vertex_inputs {
		if !input.active {
			continue
		}

		attr, attr_ok := d3d11_find_layout_attr(layout, input.semantic, input.semantic_index)
		if !attr_ok {
			set_validation_errorf(ctx, "gfx.d3d11: pipeline layout is missing shader vertex input %s%d", input.semantic, input.semantic_index)
			return false
		}
		if attr.format != input.format {
			set_validation_errorf(ctx, "gfx.d3d11: pipeline vertex input %s%d format does not match shader reflection", input.semantic, input.semantic_index)
			return false
		}
	}

	for attr in layout.attrs {
		if !vertex_attr_desc_active(attr) {
			continue
		}
		if !d3d11_shader_has_vertex_input(shader_info, string(attr.semantic), attr.semantic_index) {
			set_validation_errorf(ctx, "gfx.d3d11: pipeline layout declares unused shader vertex input %s%d", string(attr.semantic), attr.semantic_index)
			return false
		}
	}

	return true
}

d3d11_find_layout_attr :: proc(layout: Layout_Desc, semantic: string, semantic_index: u32) -> (Vertex_Attribute_Desc, bool) {
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

d3d11_shader_has_vertex_input :: proc(shader_info: D3D11_Shader, semantic: string, semantic_index: u32) -> bool {
	for input in shader_info.vertex_inputs {
		if input.active && input.semantic == semantic && input.semantic_index == semantic_index {
			return true
		}
	}

	return false
}

d3d11_bool :: proc(value: bool) -> d3d11.BOOL {
	if value {
		return win32.TRUE
	}

	return win32.FALSE
}

d3d11_fill_mode :: proc(fill_mode: Fill_Mode) -> d3d11.FILL_MODE {
	switch fill_mode {
	case .Solid:
		return .SOLID
	case .Wireframe:
		return .WIREFRAME
	}

	return .SOLID
}

d3d11_cull_mode :: proc(cull_mode: Cull_Mode) -> d3d11.CULL_MODE {
	switch cull_mode {
	case .None:
		return .NONE
	case .Front:
		return .FRONT
	case .Back:
		return .BACK
	}

	return .NONE
}

d3d11_compare_func :: proc(compare: Compare_Func) -> d3d11.COMPARISON_FUNC {
	switch compare {
	case .Always:
		return .ALWAYS
	case .Never:
		return .NEVER
	case .Less:
		return .LESS
	case .Less_Equal:
		return .LESS_EQUAL
	case .Equal:
		return .EQUAL
	case .Greater_Equal:
		return .GREATER_EQUAL
	case .Greater:
		return .GREATER
	case .Not_Equal:
		return .NOT_EQUAL
	}

	return .ALWAYS
}

d3d11_depth_write_mask :: proc(write_enabled: bool) -> d3d11.DEPTH_WRITE_MASK {
	if write_enabled {
		return .ALL
	}

	return .ZERO
}

d3d11_default_stencil_op_desc :: proc() -> d3d11.DEPTH_STENCILOP_DESC {
	return d3d11.DEPTH_STENCILOP_DESC {
		StencilFailOp = .KEEP,
		StencilDepthFailOp = .KEEP,
		StencilPassOp = .KEEP,
		StencilFunc = .ALWAYS,
	}
}

d3d11_render_target_blend_desc :: proc(color: Color_State) -> d3d11.RENDER_TARGET_BLEND_DESC {
	blend := color.blend
	return d3d11.RENDER_TARGET_BLEND_DESC {
		BlendEnable = d3d11_bool(blend.enabled),
		SrcBlend = d3d11_blend_factor(blend.src_factor, .ONE),
		DestBlend = d3d11_blend_factor(blend.dst_factor, .ZERO),
		BlendOp = d3d11_blend_op(blend.op),
		SrcBlendAlpha = d3d11_blend_factor(blend.src_alpha_factor, .ONE),
		DestBlendAlpha = d3d11_blend_factor(blend.dst_alpha_factor, .ZERO),
		BlendOpAlpha = d3d11_blend_op(blend.alpha_op),
		RenderTargetWriteMask = d3d11_color_write_mask(color.write_mask),
	}
}

d3d11_blend_factor :: proc(factor: Blend_Factor, fallback: d3d11.BLEND) -> d3d11.BLEND {
	switch factor {
	case .Default:
		return fallback
	case .Zero:
		return .ZERO
	case .One:
		return .ONE
	case .Src_Color:
		return .SRC_COLOR
	case .One_Minus_Src_Color:
		return .INV_SRC_COLOR
	case .Src_Alpha:
		return .SRC_ALPHA
	case .One_Minus_Src_Alpha:
		return .INV_SRC_ALPHA
	case .Dst_Color:
		return .DEST_COLOR
	case .One_Minus_Dst_Color:
		return .INV_DEST_COLOR
	case .Dst_Alpha:
		return .DEST_ALPHA
	case .One_Minus_Dst_Alpha:
		return .INV_DEST_ALPHA
	case .Blend_Color:
		return .BLEND_FACTOR
	case .One_Minus_Blend_Color:
		return .INV_BLEND_FACTOR
	case .Src_Alpha_Saturated:
		return .SRC_ALPHA_SAT
	}

	return fallback
}

d3d11_blend_op :: proc(op: Blend_Op) -> d3d11.BLEND_OP {
	switch op {
	case .Default, .Add:
		return .ADD
	case .Subtract:
		return .SUBTRACT
	case .Reverse_Subtract:
		return .REV_SUBTRACT
	case .Min:
		return .MIN
	case .Max:
		return .MAX
	}

	return .ADD
}

d3d11_color_write_mask :: proc(mask: u8) -> u8 {
	if mask == 0 {
		return COLOR_MASK_RGBA
	}

	return mask & COLOR_MASK_RGBA
}

d3d11_primitive_topology :: proc(primitive: Primitive_Type) -> d3d11.PRIMITIVE_TOPOLOGY {
	switch primitive {
	case .Triangles:
		return .TRIANGLELIST
	case .Lines:
		return .LINELIST
	case .Points:
		return .POINTLIST
	}

	return .TRIANGLELIST
}

d3d11_index_format :: proc(index_type: Index_Type) -> dxgi.FORMAT {
	switch index_type {
	case .Uint16:
		return .R16_UINT
	case .Uint32:
		return .R32_UINT
	case .None:
		return .UNKNOWN
	}

	return .UNKNOWN
}

d3d11_vertex_format :: proc(format: Vertex_Format) -> dxgi.FORMAT {
	switch format {
	case .Float32:
		return .R32_FLOAT
	case .Float32x2:
		return .R32G32_FLOAT
	case .Float32x3:
		return .R32G32B32_FLOAT
	case .Float32x4:
		return .R32G32B32A32_FLOAT
	case .Uint8x4_Norm:
		return .R8G8B8A8_UNORM
	case .Invalid:
		return .UNKNOWN
	}

	return .UNKNOWN
}

d3d11_input_class :: proc(step_func: Vertex_Step_Function) -> d3d11.INPUT_CLASSIFICATION {
	switch step_func {
	case .Per_Vertex:
		return .VERTEX_DATA
	case .Per_Instance:
		return .INSTANCE_DATA
	}

	return .VERTEX_DATA
}
