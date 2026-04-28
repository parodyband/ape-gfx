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
import gfx "ape:engine/gfx"

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

	shader_desc := graphics_shader_desc(bytecode[:])
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

	if !gfx.begin_pass(&ctx, {label = "binding validation pass"}) {
		fmt.eprintln("valid pass failed: ", gfx.last_error(&ctx))
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
