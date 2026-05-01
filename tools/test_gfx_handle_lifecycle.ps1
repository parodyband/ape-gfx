param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\gfx_handle_lifecycle"
$OutPath = Join-Path $TestDir "gfx_handle_lifecycle.exe"
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

expect_error :: proc(ctx: ^gfx.Context, expected: string) {
	actual := gfx.last_error(ctx)
	if actual != expected {
		fmt.eprintln("expected error: ", expected)
		fmt.eprintln("actual error:   ", actual)
		os.exit(1)
	}
}

expect_error_code :: proc(ctx: ^gfx.Context, expected: gfx.Error_Code) {
	actual := gfx.last_error_code(ctx)
	if actual != expected {
		fmt.eprintln("expected error code: ", expected)
		fmt.eprintln("actual error code:   ", actual)
		os.exit(1)
	}
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
	return desc
}

main :: proc() {
	ctx_a, ok_a := gfx.init({backend = .Null, label = "handle lifecycle a"})
	if !ok_a {
		fmt.eprintln("ctx_a init failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx_a)

	ctx_b, ok_b := gfx.init({backend = .Null, label = "handle lifecycle b"})
	if !ok_b {
		fmt.eprintln("ctx_b init failed: ", gfx.last_error(&ctx_b))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx_b)

	direct, direct_ok := gfx.create_buffer(&ctx_a, {
		label = "direct create",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !direct_ok || !gfx.buffer_valid(direct) {
		fmt.eprintln("direct buffer creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}
	gfx.destroy(&ctx_a, direct)

	invalid, invalid_ok := gfx.create_buffer(&ctx_a, {
		label = "invalid direct create",
		usage = {.Vertex},
	})
	if invalid_ok || gfx.buffer_valid(invalid) {
		fail("invalid direct create unexpectedly succeeded")
	}
	expect_error(&ctx_a, "gfx.create_buffer: size must be positive or inferred from initial data")
	expect_error_code(&ctx_a, .Validation)

	first, first_ok := gfx.create_buffer(&ctx_a, {
		label = "first",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !first_ok {
		fmt.eprintln("first buffer creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	gfx.destroy(&ctx_a, first)
	gfx.destroy(&ctx_a, first)
	expect_error_info(&ctx_a, .Stale_Handle, "gfx.destroy_buffer: buffer handle is stale or destroyed")

	second, second_ok := gfx.create_buffer(&ctx_a, {
		label = "second",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !second_ok {
		fmt.eprintln("second buffer creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}
	if second == first {
		fail("reused buffer slot did not advance the generation")
	}

	gfx.destroy(&ctx_b, second)
	expect_error(&ctx_b, "gfx.destroy_buffer: buffer handle belongs to a different context")
	expect_error_code(&ctx_b, .Wrong_Context)

	gfx.destroy(&ctx_a, second)

	pixels := [?]u8{255, 255, 255, 255}
	image, image_ok := gfx.create_image(&ctx_a, {
		label = "guard image",
		usage = {.Texture, .Immutable},
		width = 1, height = 1,
		format = .RGBA8,
		mips = {0 = {data = gfx.range(pixels[:])}},
	})
	if !image_ok {
		fmt.eprintln("guard image creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	view, view_ok := gfx.create_view(&ctx_a, {
		label = "guard view",
		texture = {image = image},
	})
	if !view_ok {
		fmt.eprintln("guard view creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	sampler, sampler_ok := gfx.create_sampler(&ctx_a, {label = "guard sampler"})
	if !sampler_ok {
		fmt.eprintln("guard sampler creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	group_layout_desc: gfx.Binding_Group_Layout_Desc
	group_layout_desc.entries[0] = {
		active = true,
		stages = {.Fragment},
		kind = .Resource_View,
		slot = 0,
		name = "guard_texture",
		resource_view = {view_kind = .Sampled, access = .Read},
	}
	group_layout_desc.entries[1] = {
		active = true,
		stages = {.Fragment},
		kind = .Sampler,
		slot = 0,
		name = "guard_sampler",
	}
	group_layout, group_layout_ok := gfx.create_binding_group_layout(&ctx_a, group_layout_desc)
	if !group_layout_ok {
		fmt.eprintln("guard binding group layout creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	pipeline_layout, pipeline_layout_ok := gfx.create_pipeline_layout(&ctx_a, {
		group_layouts = {0 = group_layout},
	})
	if !pipeline_layout_ok {
		fmt.eprintln("guard pipeline layout creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	binding_group, binding_group_ok := gfx.create_binding_group(&ctx_a, {
		layout = group_layout,
		views = {0 = view},
		samplers = {0 = sampler},
	})
	if !binding_group_ok {
		fmt.eprintln("guard binding group creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	gfx.destroy(&ctx_a, view)
	expect_error_info(&ctx_a, .Validation, "gfx.destroy_view: view is still used by a binding group")
	gfx.destroy(&ctx_a, sampler)
	expect_error_info(&ctx_a, .Validation, "gfx.destroy_sampler: sampler is still used by a binding group")
	gfx.destroy(&ctx_a, image)
	expect_error_info(&ctx_a, .Validation, "gfx.destroy_image: image is still referenced by a view")
	gfx.destroy(&ctx_a, group_layout)
	expect_error_info(&ctx_a, .Validation, "gfx.destroy_binding_group_layout: layout is still used by a binding group")

	gfx.destroy(&ctx_a, binding_group)
	gfx.destroy(&ctx_a, group_layout)
	expect_error_info(&ctx_a, .Validation, "gfx.destroy_binding_group_layout: layout is still used by a pipeline layout")

	gfx.destroy(&ctx_a, pipeline_layout)
	gfx.destroy(&ctx_a, group_layout)
	gfx.destroy(&ctx_a, view)
	gfx.destroy(&ctx_a, sampler)
	gfx.destroy(&ctx_a, image)

	bytecode := [?]u8{1, 2, 3, 4}
	shader, shader_ok := gfx.create_shader(&ctx_a, graphics_shader_desc(bytecode[:]))
	if !shader_ok {
		fmt.eprintln("guard shader creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}
	pipeline, pipeline_ok := gfx.create_pipeline(&ctx_a, {
		label = "guard pipeline",
		shader = shader,
		primitive_type = .Triangles,
	})
	if !pipeline_ok {
		fmt.eprintln("guard pipeline creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	gfx.destroy(&ctx_a, shader)
	expect_error_info(&ctx_a, .Validation, "gfx.destroy_shader: shader is still used by a pipeline")

	bound_buffer, bound_buffer_ok := gfx.create_buffer(&ctx_a, {
		label = "bound vertex buffer",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !bound_buffer_ok {
		fmt.eprintln("bound buffer creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	if !gfx.begin_pass(&ctx_a, {}) {
		fmt.eprintln("guard pass begin failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}
	if !gfx.apply_pipeline(&ctx_a, pipeline) {
		fmt.eprintln("guard pipeline apply failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}
	bindings: gfx.Bindings
	bindings.vertex_buffers[0] = {buffer = bound_buffer}
	if !gfx.apply_bindings(&ctx_a, bindings) {
		fmt.eprintln("guard bindings apply failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	gfx.destroy(&ctx_a, bound_buffer)
	expect_error_info(&ctx_a, .Validation, "gfx.destroy_buffer: buffer is currently bound")
	gfx.destroy(&ctx_a, pipeline)
	expect_error_info(&ctx_a, .Validation, "gfx.destroy_pipeline: pipeline is currently bound")
	if !gfx.end_pass(&ctx_a) {
		fmt.eprintln("guard pass end failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	gfx.destroy(&ctx_a, bound_buffer)
	gfx.destroy(&ctx_a, pipeline)
	gfx.destroy(&ctx_a, shader)

	ctx_leak, leak_ok := gfx.init({backend = .Null, label = "handle lifecycle leak"})
	if !leak_ok {
		fmt.eprintln("ctx_leak init failed: ", gfx.last_error(&ctx_leak))
		os.exit(1)
	}

	leaked, leaked_ok := gfx.create_buffer(&ctx_leak, {
		label = "leaked",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !leaked_ok {
		fmt.eprintln("leaked buffer creation failed: ", gfx.last_error(&ctx_leak))
		os.exit(1)
	}

	gfx.shutdown(&ctx_leak)
	expect_error(&ctx_leak, "gfx.shutdown: leaked resources: buffers=1 images=0 views=0 samplers=0 shaders=0 pipelines=0 compute_pipelines=0 binding_group_layouts=0 pipeline_layouts=0 binding_groups=0 transient_allocators=0")
	expect_error_code(&ctx_leak, .Resource_Leak)

	fmt.println("gfx handle lifecycle validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
