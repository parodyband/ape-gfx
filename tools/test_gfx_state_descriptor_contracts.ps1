param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\gfx_state_descriptor_contracts"
$OutPath = Join-Path $TestDir "gfx_state_descriptor_contracts.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import gfx "ape:gfx"

fail :: proc(message: string) {
	fmt.eprintln(message)
	os.exit(1)
}

expect_error_info :: proc(ctx: ^gfx.Context, expected_code: gfx.Error_Code, expected_message: string) {
	info := gfx.last_error_info(ctx)
	if info.code != expected_code || info.message != expected_message {
		fmt.eprintln("expected error code: ", expected_code)
		fmt.eprintln("actual error code:   ", info.code)
		fmt.eprintln("expected message:    ", expected_message)
		fmt.eprintln("actual message:      ", info.message)
		os.exit(1)
	}
}

graphics_shader_desc :: proc(bytecode: []u8) -> gfx.Shader_Desc {
	desc: gfx.Shader_Desc
	desc.stages[int(gfx.Shader_Stage.Vertex)] = {
		stage = .Vertex,
		entry = "vs_main",
		bytecode = gfx.range(bytecode),
	}
	desc.stages[int(gfx.Shader_Stage.Fragment)] = {
		stage = .Fragment,
		entry = "fs_main",
		bytecode = gfx.range(bytecode),
	}
	desc.has_vertex_input_metadata = true
	desc.vertex_inputs[0] = {
		active = true,
		semantic = "POSITION",
		semantic_index = 0,
		format = .Float32x3,
	}
	return desc
}

graphics_shader_desc_with_texture_bindings :: proc(bytecode: []u8) -> gfx.Shader_Desc {
	desc := graphics_shader_desc(bytecode)
	desc.has_binding_metadata = true
	desc.bindings[0] = {
		active = true,
		stage = .Fragment,
		kind = .Resource_View,
		slot = 0,
		native_slot = 0,
		native_space = 0,
		name = "ape_texture",
		view_kind = .Sampled,
		access = .Read,
	}
	desc.bindings[1] = {
		active = true,
		stage = .Fragment,
		kind = .Sampler,
		slot = 0,
		native_slot = 0,
		native_space = 0,
		name = "ape_sampler",
	}
	return desc
}

main :: proc() {
	ctx, ok := gfx.init({backend = .Null, label = "state descriptor contracts"})
	if !ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	sampler, sampler_ok := gfx.create_sampler(&ctx, {
		label = "valid zero-default sampler",
	})
	if !sampler_ok || !gfx.sampler_valid(sampler) {
		fmt.eprintln("valid sampler failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, sampler)

	bad_sampler, bad_sampler_ok := gfx.create_sampler(&ctx, {
		label = "bad sampler",
		min_filter = gfx.Filter(99),
	})
	if bad_sampler_ok || gfx.sampler_valid(bad_sampler) {
		fail("sampler with invalid filter unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_sampler: min_filter is invalid")

	group_layout: gfx.Binding_Group_Layout_Desc
	group_layout.label = "valid generated-style binding group layout"
	group_layout.entries[0] = {
		active = true,
		stages = {.Fragment},
		kind = .Resource_View,
		slot = 0,
		name = "ape_texture",
		resource_view = {
			view_kind = .Sampled,
			access = .Read,
		},
	}
	group_layout.entries[1] = {
		active = true,
		stages = {.Fragment},
		kind = .Sampler,
		slot = 0,
		name = "ape_sampler",
	}
	group_layout.native_bindings[0] = {
		active = true,
		target = .D3D11,
		stage = .Fragment,
		kind = .Resource_View,
		slot = 0,
		native_slot = 0,
		native_space = 0,
	}
	group_layout.native_bindings[1] = {
		active = true,
		target = .D3D11,
		stage = .Fragment,
		kind = .Sampler,
		slot = 0,
		native_slot = 0,
		native_space = 0,
	}
	if !gfx.validate_binding_group_layout_desc(&ctx, group_layout) {
		fmt.eprintln("valid binding group layout failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	duplicate_group_layout := group_layout
	duplicate_group_layout.entries[2] = group_layout.entries[0]
	if gfx.validate_binding_group_layout_desc(&ctx, duplicate_group_layout) {
		fail("binding group layout with duplicate resource view unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.validate_binding_group_layout_desc: duplicate resource view entry at slot 0")

	missing_entry_layout := group_layout
	missing_entry_layout.native_bindings[2] = {
		active = true,
		target = .D3D11,
		stage = .Fragment,
		kind = .Resource_View,
		slot = 4,
		native_slot = 4,
		native_space = 0,
	}
	if gfx.validate_binding_group_layout_desc(&ctx, missing_entry_layout) {
		fail("binding group layout with missing logical entry unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.validate_binding_group_layout_desc: native binding 2 references missing resource view entry slot 4")

	bytecode := [?]u8{1, 2, 3, 4}

	empty_shader, empty_shader_ok := gfx.create_shader(&ctx, {})
	if empty_shader_ok || gfx.shader_valid(empty_shader) {
		fail("empty shader unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_shader: at least one stage bytecode range is required")

	incomplete_desc: gfx.Shader_Desc
	incomplete_desc.stages[int(gfx.Shader_Stage.Vertex)] = {
		stage = .Vertex,
		bytecode = gfx.range(bytecode[:]),
	}
	incomplete_shader, incomplete_shader_ok := gfx.create_shader(&ctx, incomplete_desc)
	if incomplete_shader_ok || gfx.shader_valid(incomplete_shader) {
		fail("incomplete graphics shader unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_shader: graphics shaders require both vertex and fragment stages")

	mixed_desc := incomplete_desc
	mixed_desc.stages[int(gfx.Shader_Stage.Compute)] = {
		stage = .Compute,
		bytecode = gfx.range(bytecode[:]),
	}
	mixed_shader, mixed_shader_ok := gfx.create_shader(&ctx, mixed_desc)
	if mixed_shader_ok || gfx.shader_valid(mixed_shader) {
		fail("mixed graphics/compute shader unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_shader: compute stages cannot be combined with graphics stages")

	binding_without_flag := graphics_shader_desc(bytecode[:])
	binding_without_flag.bindings[0] = {
		active = true,
		stage = .Vertex,
		kind = .Uniform_Block,
		slot = 0,
		native_slot = 0,
		size = 16,
	}
	binding_shader, binding_shader_ok := gfx.create_shader(&ctx, binding_without_flag)
	if binding_shader_ok || gfx.shader_valid(binding_shader) {
		fail("binding metadata without flag unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_shader: active binding metadata at index 0 requires has_binding_metadata")

	zero_uniform := graphics_shader_desc(bytecode[:])
	zero_uniform.has_binding_metadata = true
	zero_uniform.bindings[0] = {
		active = true,
		stage = .Vertex,
		kind = .Uniform_Block,
		slot = 0,
		native_slot = 0,
	}
	zero_uniform_shader, zero_uniform_shader_ok := gfx.create_shader(&ctx, zero_uniform)
	if zero_uniform_shader_ok || gfx.shader_valid(zero_uniform_shader) {
		fail("zero-sized uniform metadata unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_shader: uniform binding metadata index 0 requires nonzero size")

	shader_desc := graphics_shader_desc_with_texture_bindings(bytecode[:])
	shader, shader_ok := gfx.create_shader(&ctx, shader_desc)
	if !shader_ok || !gfx.shader_valid(shader) {
		fmt.eprintln("valid graphics shader failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, shader)

	layout: gfx.Layout_Desc
	layout.buffers[0] = {stride = 12}
	layout.attrs[0] = {
		semantic = cstring("POSITION"),
		semantic_index = 0,
		format = .Float32x3,
		buffer_slot = 0,
		offset = 0,
	}

	pipeline, pipeline_ok := gfx.create_pipeline(&ctx, {
		label = "valid reflected pipeline",
		shader = shader,
		primitive_type = .Triangles,
		index_type = .None,
		layout = layout,
	})
	if !pipeline_ok || !gfx.pipeline_valid(pipeline) {
		fmt.eprintln("valid pipeline failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, pipeline)

	sparse_layout := layout
	sparse_layout.attrs[0] = {}
	sparse_layout.attrs[7] = {
		semantic = cstring("POSITION"),
		semantic_index = 0,
		format = .Float32x3,
		buffer_slot = 0,
		offset = 0,
	}
	sparse_layout_pipeline, sparse_layout_pipeline_ok := gfx.create_pipeline(&ctx, {
		label = "valid sparse reflected layout",
		shader = shader,
		primitive_type = .Triangles,
		index_type = .None,
		layout = sparse_layout,
	})
	if !sparse_layout_pipeline_ok || !gfx.pipeline_valid(sparse_layout_pipeline) {
		fmt.eprintln("sparse layout pipeline failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, sparse_layout_pipeline)

	missing_stride_layout := sparse_layout
	missing_stride_layout.buffers[0] = {}
	missing_stride_pipeline, missing_stride_pipeline_ok := gfx.create_pipeline(&ctx, {
		label = "sparse layout missing stride",
		shader = shader,
		primitive_type = .Triangles,
		index_type = .None,
		layout = missing_stride_layout,
	})
	if missing_stride_pipeline_ok || gfx.pipeline_valid(missing_stride_pipeline) {
		fail("pipeline with sparse layout missing stride unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_pipeline: vertex attribute 7 references buffer slot 0 with zero stride")

	gapped_color_layout := layout
	gapped_color_pipeline, gapped_color_pipeline_ok := gfx.create_pipeline(&ctx, {
		label = "gapped color formats",
		shader = shader,
		primitive_type = .Triangles,
		index_type = .None,
		layout = gapped_color_layout,
		color_formats = {
			1 = .RGBA8,
		},
	})
	if gapped_color_pipeline_ok || gfx.pipeline_valid(gapped_color_pipeline) {
		fail("pipeline with gapped color formats unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_pipeline: color formats must be contiguous from slot 0; slot 0 is missing")

	bad_layout := layout
	bad_layout.attrs[0].format = .Float32x2
	bad_pipeline, bad_pipeline_ok := gfx.create_pipeline(&ctx, {
		label = "bad reflected layout",
		shader = shader,
		primitive_type = .Triangles,
		index_type = .None,
		layout = bad_layout,
	})
	if bad_pipeline_ok || gfx.pipeline_valid(bad_pipeline) {
		fail("pipeline with mismatched reflected layout unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_pipeline: pipeline vertex input POSITION0 format does not match shader reflection")

	bad_primitive, bad_primitive_ok := gfx.create_pipeline(&ctx, {
		label = "bad primitive",
		shader = shader,
		primitive_type = gfx.Primitive_Type(99),
		index_type = .None,
		layout = layout,
	})
	if bad_primitive_ok || gfx.pipeline_valid(bad_primitive) {
		fail("pipeline with invalid primitive unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_pipeline: primitive_type is invalid")

	bad_compute_pipeline, bad_compute_pipeline_ok := gfx.create_compute_pipeline(&ctx, {
		label = "graphics shader as compute",
		shader = shader,
	})
	if bad_compute_pipeline_ok || gfx.compute_pipeline_valid(bad_compute_pipeline) {
		fail("compute pipeline with graphics shader unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_compute_pipeline: shader must contain a compute stage")

	action := gfx.default_pass_action()
	action.colors[0].load_action = gfx.Load_Action(99)
	if gfx.begin_pass(&ctx, {label = "bad pass action", action = action}) {
		fail("pass with invalid action unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.begin_pass: color action slot 0 has an invalid load_action")

	attachment_image, attachment_image_ok := gfx.create_image(&ctx, {
		label = "attachment for pass slot tests",
		usage = {.Color_Attachment},
		width = 4,
		height = 4,
		format = .RGBA8,
	})
	if !attachment_image_ok || !gfx.image_valid(attachment_image) {
		fmt.eprintln("attachment image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, attachment_image)

	attachment_view, attachment_view_ok := gfx.create_view(&ctx, {
		label = "attachment view for pass slot tests",
		color_attachment = {image = attachment_image},
	})
	if !attachment_view_ok || !gfx.view_valid(attachment_view) {
		fmt.eprintln("attachment view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, attachment_view)

	gapped_pass: gfx.Pass_Desc
	gapped_pass.label = "gapped color attachment pass"
	gapped_pass.color_attachments[1] = attachment_view
	if gfx.begin_pass(&ctx, gapped_pass) {
		fail("pass with gapped color attachments unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.begin_pass: color attachments must be contiguous from slot 0; slot 0 is missing")

	vertex_data := [?]f32{0, 1, 2}
	vertex_buffer, vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "binding validation vertex buffer",
		usage = {.Vertex, .Immutable},
		data = gfx.range(vertex_data[:]),
	})
	if !vertex_buffer_ok || !gfx.buffer_valid(vertex_buffer) {
		fmt.eprintln("vertex buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, vertex_buffer)

	texture_image, texture_image_ok := gfx.create_image(&ctx, {
		label = "sparse binding texture",
		usage = {.Texture},
		width = 4,
		height = 4,
		format = .RGBA8,
	})
	if !texture_image_ok || !gfx.image_valid(texture_image) {
		fmt.eprintln("texture image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, texture_image)

	sampled_view, sampled_view_ok := gfx.create_view(&ctx, {
		label = "sparse binding sampled view",
		texture = {image = texture_image},
	})
	if !sampled_view_ok || !gfx.view_valid(sampled_view) {
		fmt.eprintln("sampled view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, sampled_view)

	if !gfx.begin_pass(&ctx, {label = "binding validation pass"}) {
		fmt.eprintln("valid pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	group_base_bindings: gfx.Bindings
	group_base_bindings.vertex_buffers[0] = {buffer = vertex_buffer}

	valid_group: gfx.Binding_Group_Desc
	valid_group.views[0] = sampled_view
	valid_group.samplers[0] = sampler
	if gfx.apply_binding_group(&ctx, group_layout, valid_group, group_base_bindings) {
		fail("binding group without applied pipeline unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.apply_binding_group: requires an applied graphics pipeline")

	if !gfx.apply_pipeline(&ctx, pipeline) {
		fmt.eprintln("apply_pipeline failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	if !gfx.apply_binding_group(&ctx, group_layout, valid_group, group_base_bindings) {
		fmt.eprintln("valid binding group failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	wrong_slot_layout := group_layout
	wrong_slot_layout.entries[0].slot = 1
	wrong_slot_layout.native_bindings[0].slot = 1
	wrong_slot_layout.native_bindings[0].native_slot = 1
	wrong_slot_group := valid_group
	wrong_slot_group.views[0] = gfx.View_Invalid
	wrong_slot_group.views[1] = sampled_view
	if gfx.apply_binding_group(&ctx, wrong_slot_layout, wrong_slot_group, group_base_bindings) {
		fail("binding group layout for unused pipeline slot unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.apply_binding_group: layout resource view slot 1 for fragment is not used by current pipeline")

	missing_required_layout := group_layout
	missing_required_layout.entries[1] = {}
	missing_required_layout.native_bindings[1] = {}
	missing_required_group := valid_group
	missing_required_group.samplers[0] = gfx.Sampler_Invalid
	if gfx.apply_binding_group(&ctx, missing_required_layout, missing_required_group, group_base_bindings) {
		fail("binding group layout missing current pipeline sampler unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.apply_binding_group: layout is missing current pipeline fragment sampler slot 0")

	missing_sampler_group := valid_group
	missing_sampler_group.samplers[0] = gfx.Sampler_Invalid
	if gfx.apply_binding_group(&ctx, group_layout, missing_sampler_group, group_base_bindings) {
		fail("binding group with missing sampler unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.apply_binding_group: sampler slot 0 requires a sampler")

	wrong_view_kind_group := valid_group
	wrong_view_kind_group.views[0] = attachment_view
	if gfx.apply_binding_group(&ctx, group_layout, wrong_view_kind_group, group_base_bindings) {
		fail("binding group with wrong view kind unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.apply_binding_group: resource view slot 0 requires a sampled view")

	extra_view_group := valid_group
	extra_view_group.views[5] = sampled_view
	if gfx.apply_binding_group(&ctx, group_layout, extra_view_group, group_base_bindings) {
		fail("binding group with extra resource view unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.apply_binding_group: resource view slot 5 is not declared by layout")

	base_with_resource := group_base_bindings
	base_with_resource.views[0] = sampled_view
	if gfx.apply_binding_group(&ctx, group_layout, valid_group, base_with_resource) {
		fail("binding group with shader resources in base bindings unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.apply_binding_group: base bindings must not contain resource views or samplers")

	sparse_bindings: gfx.Bindings
	sparse_bindings.views[2] = sampled_view
	sparse_bindings.samplers[3] = sampler
	if !gfx.apply_bindings(&ctx, sparse_bindings) {
		fmt.eprintln("sparse resource bindings failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	bindings: gfx.Bindings
	bindings.vertex_buffers[0] = {buffer = vertex_buffer, offset = -1}
	if gfx.apply_bindings(&ctx, bindings) {
		fail("bindings with negative vertex buffer offset unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.apply_bindings: vertex buffer slot 0 offset must be non-negative")

	if !gfx.end_pass(&ctx) {
		fmt.eprintln("end_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	fmt.println("gfx state descriptor contract validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
