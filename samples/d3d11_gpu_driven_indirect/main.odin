// AAA roadmap item 15 / APE-11: prove GPU-driven-style indirect submission
// without a renderer. A compute pass writes a `gfx.Draw_Indirect_Args` record
// into a raw `{.Indirect, .Storage}` buffer; a render pass consumes that
// buffer with `gfx.draw_indirect`. The visible output is an animated row of
// quads whose count is decided on the GPU each frame.
package main

import "core:fmt"
import "core:os"
import app "ape:app"
import gfx "ape:gfx"
import shader_assets "ape:shader"
import args_shader "ape:assets/shaders/generated/gpu_driven_indirect_args"
import triangle_shader "ape:assets/shaders/generated/triangle"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)

MAX_QUADS         :: 8
VERTICES_PER_QUAD :: 6

Vertex :: struct {
	position: [3]f32,
	color:    [3]f32,
}

Compute_Uniforms :: struct {
	quad_count:        u32,
	vertices_per_quad: u32,
	pad0:              u32,
	pad1:              u32,
}

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		os.exit(1)
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width         = 1280,
		height        = 360,
		title         = "Ape D3D11 GPU-Driven Indirect",
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
		vsync            = true,
		debug            = true,
		label            = "ape d3d11 gpu driven indirect",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	// Pre-bake MAX_QUADS quads in a horizontal row. The compute shader will
	// pick how many of them the draw consumes by writing vertex_count.
	vertices: [MAX_QUADS * VERTICES_PER_QUAD]Vertex
	{
		half_w := f32(0.06)
		half_h := f32(0.32)
		spacing := f32(1.6) / f32(MAX_QUADS)
		for i in 0..<MAX_QUADS {
			cx := -0.8 + spacing * (f32(i) + 0.5)
			t := f32(i) / f32(MAX_QUADS - 1)
			color := [3]f32{0.95 - 0.6 * t, 0.25 + 0.5 * t, 0.35 + 0.55 * (1.0 - t)}
			x0 := cx - half_w
			x1 := cx + half_w
			y0 := -half_h
			y1 :=  half_h
			base := i * VERTICES_PER_QUAD
			vertices[base + 0] = {position = {x0, y0, 0}, color = color}
			vertices[base + 1] = {position = {x1, y0, 0}, color = color}
			vertices[base + 2] = {position = {x1, y1, 0}, color = color}
			vertices[base + 3] = {position = {x0, y0, 0}, color = color}
			vertices[base + 4] = {position = {x1, y1, 0}, color = color}
			vertices[base + 5] = {position = {x0, y1, 0}, color = color}
		}
	}

	vertex_buffer, vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "gpu-driven indirect quads",
		usage = {.Vertex, .Immutable},
		data  = gfx.range(vertices[:]),
	})
	if !vertex_buffer_ok {
		fmt.eprintln("vertex buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, vertex_buffer)

	// {.Indirect, .Storage} with storage_stride=0 → raw byte-address buffer
	// the compute shader can write and the draw can consume as indirect args.
	indirect_buffer, indirect_buffer_ok := gfx.create_buffer(&ctx, {
		label          = "gpu-driven indirect args",
		usage          = {.Indirect, .Storage},
		size           = gfx.DRAW_INDIRECT_ARGS_STRIDE,
		storage_stride = 0,
	})
	if !indirect_buffer_ok {
		fmt.eprintln("indirect buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, indirect_buffer)

	indirect_view, indirect_view_ok := gfx.create_view(&ctx, {
		label          = "gpu-driven indirect args view",
		storage_buffer = {buffer = indirect_buffer},
	})
	if !indirect_view_ok {
		fmt.eprintln("indirect view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, indirect_view)

	// Compute pipeline: writes Draw_Indirect_Args.
	args_package, args_package_ok := shader_assets.load("build/shaders/gpu_driven_indirect_args.ashader")
	if !args_package_ok {
		fmt.eprintln("compute shader package load failed")
		os.exit(1)
	}
	defer shader_assets.unload(&args_package)

	args_shader_desc, args_shader_desc_ok := shader_assets.shader_desc(&args_package, .D3D11_DXBC, "gpu_driven_indirect_args shader")
	if !args_shader_desc_ok {
		fmt.eprintln("compute shader desc lookup failed")
		os.exit(1)
	}
	args_shader_handle, args_shader_handle_ok := gfx.create_shader(&ctx, args_shader_desc)
	if !args_shader_handle_ok {
		fmt.eprintln("compute shader creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, args_shader_handle)

	args_group_layout, args_group_layout_ok := gfx.create_binding_group_layout(&ctx, args_shader.binding_group_layout_desc(args_shader.GROUP_0, label = "args bindings"))
	if !args_group_layout_ok {
		fmt.eprintln("compute group layout creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, args_group_layout)

	args_pipeline_layout, args_pipeline_layout_ok := gfx.create_pipeline_layout(&ctx, {
		label = "args pipeline layout",
		group_layouts = {
			args_shader.GROUP_0 = args_group_layout,
		},
	})
	if !args_pipeline_layout_ok {
		fmt.eprintln("compute pipeline layout creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, args_pipeline_layout)

	args_pipeline, args_pipeline_ok := gfx.create_compute_pipeline(&ctx, {
		label           = "args pipeline",
		shader          = args_shader_handle,
		pipeline_layout = args_pipeline_layout,
	})
	if !args_pipeline_ok {
		fmt.eprintln("compute pipeline creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, args_pipeline)

	// Render pipeline: triangle shader from samples/d3d11_triangle.
	triangle_package, triangle_package_ok := shader_assets.load("build/shaders/triangle.ashader")
	if !triangle_package_ok {
		fmt.eprintln("triangle shader package load failed")
		os.exit(1)
	}
	defer shader_assets.unload(&triangle_package)

	triangle_shader_desc, triangle_shader_desc_ok := shader_assets.shader_desc(&triangle_package, .D3D11_DXBC, "triangle shader")
	if !triangle_shader_desc_ok {
		fmt.eprintln("triangle shader desc lookup failed")
		os.exit(1)
	}
	triangle_shader_handle, triangle_shader_handle_ok := gfx.create_shader(&ctx, triangle_shader_desc)
	if !triangle_shader_handle_ok {
		fmt.eprintln("triangle shader creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, triangle_shader_handle)

	triangle_group_layout, triangle_group_layout_ok := gfx.create_binding_group_layout(&ctx, triangle_shader.binding_group_layout_desc(triangle_shader.GROUP_0, label = "triangle bindings"))
	if !triangle_group_layout_ok {
		fmt.eprintln("render group layout creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, triangle_group_layout)

	triangle_pipeline_layout, triangle_pipeline_layout_ok := gfx.create_pipeline_layout(&ctx, {
		label = "triangle pipeline layout",
		group_layouts = {
			triangle_shader.GROUP_0 = triangle_group_layout,
		},
	})
	if !triangle_pipeline_layout_ok {
		fmt.eprintln("render pipeline layout creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, triangle_pipeline_layout)

	render_pipeline, render_pipeline_ok := gfx.create_pipeline(&ctx, {
		label           = "gpu-driven indirect pipeline",
		shader          = triangle_shader_handle,
		pipeline_layout = triangle_pipeline_layout,
		primitive_type  = .Triangles,
		index_type      = .None,
		layout          = triangle_shader.layout_desc(),
	})
	if !render_pipeline_ok {
		fmt.eprintln("render pipeline creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, render_pipeline)

	render_bindings: gfx.Bindings
	render_bindings.vertex_buffers[0] = {buffer = vertex_buffer}

	compute_bindings: gfx.Bindings
	args_shader.set_view_indirect_args(&compute_bindings, indirect_view)

	render_width := fb_width
	render_height := fb_height
	frame := 0

	for !app.should_close(&window) {
		app.poll_events()

		fb_width, fb_height = app.framebuffer_size(&window)
		if fb_width <= 0 || fb_height <= 0 {
			continue
		}
		if fb_width != render_width || fb_height != render_height {
			_ = gfx.resize(&ctx, fb_width, fb_height)
			render_width = fb_width
			render_height = fb_height
		}

		quad_count := u32(1 + (frame / 30) % MAX_QUADS)
		uniforms := Compute_Uniforms{
			quad_count        = quad_count,
			vertices_per_quad = VERTICES_PER_QUAD,
		}

		_ = gfx.begin_compute_pass(&ctx, {label = "gpu-driven indirect args"})
		_ = gfx.apply_compute_pipeline(&ctx, args_pipeline)
		_ = gfx.apply_bindings(&ctx, compute_bindings)
		_ = args_shader.apply_uniform_ComputeUniforms(&ctx, &uniforms)
		_ = gfx.dispatch(&ctx, 1, 1, 1)
		_ = gfx.end_compute_pass(&ctx)

		_ = gfx.begin_pass(&ctx, {
			label  = "gpu-driven indirect draw",
			action = {colors = {0 = {clear_value = {r = 0.025, g = 0.03, b = 0.045, a = 1}}}},
		})
		_ = gfx.apply_pipeline(&ctx, render_pipeline)
		_ = gfx.apply_bindings(&ctx, render_bindings)
		_ = triangle_shader.apply_uniform_FrameUniforms(&ctx, &triangle_shader.FrameUniforms{ape_frame = {0, 0, 1, 0}})
		_ = gfx.draw_indirect(&ctx, indirect_buffer)
		_ = gfx.end_pass(&ctx)
		_ = gfx.commit(&ctx)

		frame += 1
		when AUTO_EXIT_FRAMES > 0 {
			if frame >= AUTO_EXIT_FRAMES {
				break
			}
		}
	}
}
