param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_indirect_validation"
$OutPath = Join-Path $TestDir "d3d11_indirect_validation.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import "core:strings"
import app "ape:app"
import gfx "ape:gfx"
import shader_assets "ape:shader"
import dispatch_shader "ape:assets/shaders/generated/dispatch_indirect_fill"

fail :: proc(message: string) {
	fmt.eprintln(message)
	os.exit(1)
}

expect_validation_error :: proc(ctx: ^gfx.Context, fragment: string) {
	info := gfx.last_error_info(ctx)
	if info.code != .Validation {
		fmt.eprintln("expected Validation error, got: ", info.code, " message: ", info.message)
		os.exit(1)
	}
	if !strings.contains(info.message, fragment) {
		fmt.eprintln("expected validation error containing: ", fragment)
		fmt.eprintln("actual message:                       ", info.message)
		os.exit(1)
	}
}

main :: proc() {
	if !app.init() {
		fail("app init failed")
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 320,
		height = 240,
		title = "Ape D3D11 Indirect Validation",
		no_client_api = true,
	})
	if !window_ok {
		fail("window creation failed")
	}
	defer app.destroy_window(&window)

	fb_width, fb_height := app.framebuffer_size(&window)
	ctx, gfx_ok := gfx.init({
		backend = .D3D11,
		width = fb_width,
		height = fb_height,
		native_window = app.native_window_handle(&window),
		swapchain_format = .BGRA8,
		vsync = false,
		debug = true,
		label = "indirect validation test",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	// Indirect-tagged buffer, sized for several Draw_Indirect_Args records.
	draw_args := [4]gfx.Draw_Indirect_Args {
		{vertex_count = 3, instance_count = 1, first_vertex = 0, first_instance = 0},
		{vertex_count = 3, instance_count = 1, first_vertex = 0, first_instance = 0},
		{vertex_count = 3, instance_count = 1, first_vertex = 0, first_instance = 0},
		{vertex_count = 3, instance_count = 1, first_vertex = 0, first_instance = 0},
	}
	indirect_buffer, indirect_ok := gfx.create_buffer(&ctx, {
		label = "indirect args",
		usage = {.Indirect, .Immutable},
		data  = gfx.range(draw_args[:]),
	})
	if !indirect_ok {
		fail(fmt.tprintf("indirect buffer creation failed: %v", gfx.last_error(&ctx)))
	}
	defer gfx.destroy(&ctx, indirect_buffer)

	// A non-Indirect buffer — used to prove the usage-flag rule fires.
	non_indirect, non_indirect_ok := gfx.create_buffer(&ctx, {
		label = "indirect non-flag buffer",
		usage = {.Vertex, .Immutable},
		data  = gfx.range(draw_args[:]),
	})
	if !non_indirect_ok {
		fail(fmt.tprintf("non-indirect buffer creation failed: %v", gfx.last_error(&ctx)))
	}
	defer gfx.destroy(&ctx, non_indirect)

	// ---- draw_indirect rejection cases (require a render pass to be active) ----
	if gfx.draw_indirect(&ctx, indirect_buffer) {
		fail("draw_indirect outside a render pass unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "no pass in progress")

	if !gfx.begin_pass(&ctx, {
		label = "indirect validation pass",
		action = {colors = {0 = {clear_value = {r = 0, g = 0, b = 0, a = 1}}}},
	}) {
		fail(fmt.tprintf("begin_pass failed: %v", gfx.last_error(&ctx)))
	}

	// 1. Invalid handle.
	if gfx.draw_indirect(&ctx, gfx.Buffer_Invalid) {
		fail("draw_indirect with invalid handle unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "indirect buffer handle is invalid")

	// 2. Missing Indirect usage flag.
	if gfx.draw_indirect(&ctx, non_indirect) {
		fail("draw_indirect on non-Indirect buffer unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "Buffer_Usage_Flag.Indirect")

	// 3. Negative offset.
	if gfx.draw_indirect(&ctx, indirect_buffer, offset = -16) {
		fail("draw_indirect with negative offset unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "offset must be non-negative")

	// 4. Offset not aligned to 16 bytes.
	if gfx.draw_indirect(&ctx, indirect_buffer, offset = 4) {
		fail("draw_indirect with offset=4 unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "INDIRECT_ARGS_OFFSET_ALIGNMENT")

	// 5. draw_count = 0.
	if gfx.draw_indirect(&ctx, indirect_buffer, draw_count = 0) {
		fail("draw_indirect with draw_count=0 unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "draw_count must be positive")

	// 6. draw_count above MAX.
	if gfx.draw_indirect(&ctx, indirect_buffer, draw_count = u32(gfx.MAX_INDIRECT_DRAW_COUNT) + 1) {
		fail("draw_indirect above MAX_INDIRECT_DRAW_COUNT unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "MAX_INDIRECT_DRAW_COUNT")

	// 7. Stride other than 0/default.
	if gfx.draw_indirect(&ctx, indirect_buffer, stride = gfx.DRAW_INDIRECT_ARGS_STRIDE + 4) {
		fail("draw_indirect with mismatched stride unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "stride must be 0 or exactly")

	// 8. Multi-draw runs past the end of the buffer.
	if gfx.draw_indirect(
		&ctx,
		indirect_buffer,
		offset = gfx.DRAW_INDIRECT_ARGS_STRIDE,
		draw_count = 4,
		stride = gfx.DRAW_INDIRECT_ARGS_STRIDE,
	) {
		fail("draw_indirect overrunning buffer unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "exceeds buffer size")

	if !gfx.end_pass(&ctx) {
		fail(fmt.tprintf("end_pass failed: %v", gfx.last_error(&ctx)))
	}

	// ---- dispatch_indirect rejection + happy path ----
	shader_package, shader_ok := shader_assets.load("build/shaders/dispatch_indirect_fill.ashader")
	if !shader_ok {
		fail("dispatch_indirect_fill.ashader load failed (run compile_shaders.ps1 first)")
	}
	defer shader_assets.unload(&shader_package)

	shader_desc, shader_desc_ok := shader_assets.shader_desc(&shader_package, .D3D11_DXBC, "dispatch_indirect_fill shader")
	if !shader_desc_ok {
		fail("dispatch_indirect_fill shader_desc lookup failed")
	}
	shader, shader_create_ok := gfx.create_shader(&ctx, shader_desc)
	if !shader_create_ok {
		fail(fmt.tprintf("create_shader failed: %v", gfx.last_error(&ctx)))
	}
	defer gfx.destroy(&ctx, shader)

	group_layout, group_layout_ok := gfx.create_binding_group_layout(
		&ctx,
		dispatch_shader.binding_group_layout_desc(dispatch_shader.GROUP_0, label = "dispatch_indirect bindings"),
	)
	if !group_layout_ok {
		fail(fmt.tprintf("create_binding_group_layout failed: %v", gfx.last_error(&ctx)))
	}
	defer gfx.destroy(&ctx, group_layout)

	pipeline_layout, pipeline_layout_ok := gfx.create_pipeline_layout(&ctx, {
		label = "dispatch_indirect pipeline layout",
		group_layouts = {0 = group_layout},
	})
	if !pipeline_layout_ok {
		fail(fmt.tprintf("create_pipeline_layout failed: %v", gfx.last_error(&ctx)))
	}
	defer gfx.destroy(&ctx, pipeline_layout)

	pipeline, pipeline_ok := gfx.create_compute_pipeline(&ctx, {
		label           = "dispatch_indirect pipeline",
		shader          = shader,
		pipeline_layout = pipeline_layout,
	})
	if !pipeline_ok {
		fail(fmt.tprintf("create_compute_pipeline failed: %v", gfx.last_error(&ctx)))
	}
	defer gfx.destroy(&ctx, pipeline)

	THREAD_COUNT :: 16
	storage_buffer, storage_buffer_ok := gfx.create_buffer(&ctx, {
		label          = "dispatch_indirect storage",
		usage          = {.Storage},
		size           = THREAD_COUNT * size_of(u32),
		storage_stride = size_of(u32),
	})
	if !storage_buffer_ok {
		fail(fmt.tprintf("storage buffer create failed: %v", gfx.last_error(&ctx)))
	}
	defer gfx.destroy(&ctx, storage_buffer)

	storage_view, storage_view_ok := gfx.create_view(&ctx, {
		label          = "dispatch_indirect storage view",
		storage_buffer = {buffer = storage_buffer},
	})
	if !storage_view_ok {
		fail(fmt.tprintf("storage view create failed: %v", gfx.last_error(&ctx)))
	}
	defer gfx.destroy(&ctx, storage_view)

	dispatch_args := [2]gfx.Dispatch_Indirect_Args {
		{thread_group_count_x = THREAD_COUNT / dispatch_shader.COMPUTE_THREAD_GROUP_SIZE_X, thread_group_count_y = 1, thread_group_count_z = 1},
		{thread_group_count_x = THREAD_COUNT / dispatch_shader.COMPUTE_THREAD_GROUP_SIZE_X, thread_group_count_y = 1, thread_group_count_z = 1},
	}
	dispatch_buffer, dispatch_buffer_ok := gfx.create_buffer(&ctx, {
		label = "dispatch_indirect args",
		usage = {.Indirect, .Immutable},
		data  = gfx.range(dispatch_args[:]),
	})
	if !dispatch_buffer_ok {
		fail(fmt.tprintf("dispatch indirect buffer create failed: %v", gfx.last_error(&ctx)))
	}
	defer gfx.destroy(&ctx, dispatch_buffer)

	if !gfx.begin_compute_pass(&ctx, {label = "indirect validation compute"}) {
		fail(fmt.tprintf("begin_compute_pass failed: %v", gfx.last_error(&ctx)))
	}
	if !gfx.apply_compute_pipeline(&ctx, pipeline) {
		fail(fmt.tprintf("apply_compute_pipeline failed: %v", gfx.last_error(&ctx)))
	}
	bindings: gfx.Bindings
	dispatch_shader.set_view_output_buffer(&bindings, storage_view)
	if !gfx.apply_bindings(&ctx, bindings) {
		fail(fmt.tprintf("apply_bindings failed: %v", gfx.last_error(&ctx)))
	}

	// 9. Missing Indirect usage flag.
	if gfx.dispatch_indirect(&ctx, non_indirect) {
		fail("dispatch_indirect on non-Indirect buffer unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "Buffer_Usage_Flag.Indirect")

	// 10. Offset misalignment (12 is not a multiple of 16).
	if gfx.dispatch_indirect(&ctx, dispatch_buffer, offset = 12) {
		fail("dispatch_indirect with offset=12 unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "INDIRECT_ARGS_OFFSET_ALIGNMENT")

	// 11. Offset past end of buffer (buffer is 2 records * 12 = 24 bytes,
	//     but we sit at the next 16-byte slot for valid alignment).
	if gfx.dispatch_indirect(&ctx, dispatch_buffer, offset = 32) {
		fail("dispatch_indirect with offset past end unexpectedly succeeded")
	}
	expect_validation_error(&ctx, "exceeds buffer size")

	// 12. Valid dispatch_indirect — the first record fits at offset=0.
	if !gfx.dispatch_indirect(&ctx, dispatch_buffer) {
		fail(fmt.tprintf("dispatch_indirect (valid) failed: %v", gfx.last_error(&ctx)))
	}

	if !gfx.end_compute_pass(&ctx) {
		fail(fmt.tprintf("end_compute_pass failed: %v", gfx.last_error(&ctx)))
	}

	if !gfx.commit(&ctx) {
		fail(fmt.tprintf("commit failed: %v", gfx.last_error(&ctx)))
	}

	fmt.println("D3D11 indirect validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
