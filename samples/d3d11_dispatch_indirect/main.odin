package main

import "core:fmt"
import "core:os"
import app "ape:app"
import gfx "ape:gfx"
import shader_assets "ape:shader"
import dispatch_shader "ape:assets/shaders/generated/dispatch_indirect_fill"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)

THREAD_COUNT :: 16

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		os.exit(1)
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width         = 320,
		height        = 240,
		title         = "Ape D3D11 Dispatch Indirect",
		no_client_api = true,
	})
	if !window_ok {
		fmt.eprintln("window creation failed")
		os.exit(1)
	}
	defer app.destroy_window(&window)

	fb_width, fb_height := app.framebuffer_size(&window)
	ctx, gfx_ok := gfx.init({
		backend          = .D3D11,
		width            = fb_width,
		height           = fb_height,
		native_window    = app.native_window_handle(&window),
		swapchain_format = .BGRA8,
		vsync            = false,
		debug            = true,
		label            = "ape d3d11 dispatch indirect",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	shader_package, package_ok := shader_assets.load("build/shaders/dispatch_indirect_fill.ashader")
	if !package_ok {
		fmt.eprintln("failed to load compute shader package")
		os.exit(1)
	}
	defer shader_assets.unload(&shader_package)

	shader_desc, shader_desc_ok := shader_assets.shader_desc(&shader_package, .D3D11_DXBC, "dispatch_indirect_fill shader")
	if !shader_desc_ok {
		fmt.eprintln("failed to build compute shader desc")
		os.exit(1)
	}

	shader, shader_ok := gfx.create_shader(&ctx, shader_desc)
	if !shader_ok {
		fmt.eprintln("shader creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, shader)

	group_layout, group_layout_ok := gfx.create_binding_group_layout(&ctx, dispatch_shader.binding_group_layout_desc(dispatch_shader.GROUP_0, label = "dispatch_indirect bindings"))
	if !group_layout_ok {
		fmt.eprintln("binding group layout creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, group_layout)

	pipeline_layout, pipeline_layout_ok := gfx.create_pipeline_layout(&ctx, {
		label = "dispatch_indirect pipeline layout",
		group_layouts = {
			dispatch_shader.GROUP_0 = group_layout,
		},
	})
	if !pipeline_layout_ok {
		fmt.eprintln("pipeline layout creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, pipeline_layout)

	pipeline, pipeline_ok := gfx.create_compute_pipeline(&ctx, {
		label           = "dispatch_indirect pipeline",
		shader          = shader,
		pipeline_layout = pipeline_layout,
	})
	if !pipeline_ok {
		fmt.eprintln("compute pipeline creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, pipeline)

	make_storage_buffer :: proc(ctx: ^gfx.Context, label: string) -> (gfx.Buffer, gfx.View) {
		buffer, buffer_ok := gfx.create_buffer(ctx, {
			label          = label,
			usage          = {.Storage},
			size           = THREAD_COUNT * size_of(u32),
			storage_stride = size_of(u32),
		})
		if !buffer_ok {
			fmt.eprintln("storage buffer creation failed: ", gfx.last_error(ctx))
			os.exit(1)
		}
		view, view_ok := gfx.create_view(ctx, {
			label          = label,
			storage_buffer = {buffer = buffer},
		})
		if !view_ok {
			fmt.eprintln("storage view creation failed: ", gfx.last_error(ctx))
			os.exit(1)
		}
		return buffer, view
	}

	direct_buffer, direct_view := make_storage_buffer(&ctx, "direct dispatch output")
	defer gfx.destroy(&ctx, direct_view)
	defer gfx.destroy(&ctx, direct_buffer)

	indirect_buffer, indirect_view := make_storage_buffer(&ctx, "indirect dispatch output")
	defer gfx.destroy(&ctx, indirect_view)
	defer gfx.destroy(&ctx, indirect_buffer)

	// THREAD_COUNT threads / numthreads(4,1,1) = 4 thread groups along X.
	indirect_args := [?]gfx.Dispatch_Indirect_Args {
		{
			thread_group_count_x = THREAD_COUNT / dispatch_shader.COMPUTE_THREAD_GROUP_SIZE_X,
			thread_group_count_y = 1,
			thread_group_count_z = 1,
		},
	}
	indirect_args_buffer, indirect_args_buffer_ok := gfx.create_buffer(&ctx, {
		label = "dispatch indirect args",
		usage = {.Indirect, .Immutable},
		data  = gfx.range(indirect_args[:]),
	})
	if !indirect_args_buffer_ok {
		fmt.eprintln("indirect args buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, indirect_args_buffer)

	// Direct dispatch baseline.
	if !gfx.begin_compute_pass(&ctx, {label = "direct dispatch"}) {
		fmt.eprintln("begin_compute_pass (direct) failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if !gfx.apply_compute_pipeline(&ctx, pipeline) {
		fmt.eprintln("apply_compute_pipeline failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	direct_bindings: gfx.Bindings
	dispatch_shader.set_view_output_buffer(&direct_bindings, direct_view)
	if !gfx.apply_bindings(&ctx, direct_bindings) {
		fmt.eprintln("apply_bindings (direct) failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if !dispatch_shader.dispatch_threads(&ctx, THREAD_COUNT) {
		fmt.eprintln("direct dispatch failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if !gfx.end_compute_pass(&ctx) {
		fmt.eprintln("end_compute_pass (direct) failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	// Indirect dispatch — same shader, same thread count, args sourced from a buffer.
	if !gfx.begin_compute_pass(&ctx, {label = "indirect dispatch"}) {
		fmt.eprintln("begin_compute_pass (indirect) failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if !gfx.apply_compute_pipeline(&ctx, pipeline) {
		fmt.eprintln("apply_compute_pipeline failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	indirect_bindings: gfx.Bindings
	dispatch_shader.set_view_output_buffer(&indirect_bindings, indirect_view)
	if !gfx.apply_bindings(&ctx, indirect_bindings) {
		fmt.eprintln("apply_bindings (indirect) failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if !gfx.dispatch_indirect(&ctx, indirect_args_buffer) {
		fmt.eprintln("dispatch_indirect failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if !gfx.end_compute_pass(&ctx) {
		fmt.eprintln("end_compute_pass (indirect) failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	direct_values: [THREAD_COUNT]u32
	if !gfx.read_buffer(&ctx, {buffer = direct_buffer, data = gfx.range(direct_values[:])}) {
		fmt.eprintln("read_buffer (direct) failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	indirect_values: [THREAD_COUNT]u32
	if !gfx.read_buffer(&ctx, {buffer = indirect_buffer, data = gfx.range(indirect_values[:])}) {
		fmt.eprintln("read_buffer (indirect) failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	for i in 0..<THREAD_COUNT {
		expected := u32(i + 1)
		if direct_values[i] != expected {
			fmt.eprintf("direct dispatch returned wrong value at %d: got %d, expected %d\n", i, direct_values[i], expected)
			os.exit(1)
		}
		if indirect_values[i] != expected {
			fmt.eprintf("indirect dispatch returned wrong value at %d: got %d, expected %d\n", i, indirect_values[i], expected)
			os.exit(1)
		}
	}

	if !gfx.commit(&ctx) {
		fmt.eprintln("commit failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	fmt.println("D3D11 dispatch_indirect produced same result as direct dispatch")
	_ = AUTO_EXIT_FRAMES
}
