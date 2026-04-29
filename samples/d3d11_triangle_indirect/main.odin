package main

import app "ape:app"
import gfx "ape:gfx"
import shader_assets "ape:shader"
import triangle_shader "ape:assets/shaders/generated/triangle"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)

Vertex :: struct {
	position: [3]f32,
	color:    [3]f32,
}

main :: proc() {
	_ = app.init()
	defer app.shutdown()

	window, _ := app.create_window({
		width         = 1280,
		height        = 720,
		title         = "Ape D3D11 Triangle Indirect",
		no_client_api = true,
	})
	defer app.destroy_window(&window)

	fb_width, fb_height := app.framebuffer_size(&window)
	ctx, _ := gfx.init({
		backend          = .D3D11,
		width            = fb_width,
		height           = fb_height,
		native_window    = app.native_window_handle(&window),
		swapchain_format = .BGRA8,
		vsync            = true,
		debug            = true,
		label            = "ape d3d11 triangle indirect",
	})
	defer gfx.shutdown(&ctx)

	vertices := [?]Vertex {
		{position = { 0.0,   0.55, 0}, color = {1.0,  0.18, 0.12}},
		{position = { 0.52, -0.42, 0}, color = {0.12, 0.78, 0.32}},
		{position = {-0.52, -0.42, 0}, color = {0.18, 0.35, 1.0}},
	}

	vertex_buffer, _ := gfx.create_buffer(&ctx, {
		label = "triangle vertices",
		usage = {.Vertex, .Immutable},
		data  = gfx.range(vertices[:]),
	})
	defer gfx.destroy(&ctx, vertex_buffer)

	indirect_args := [?]gfx.Draw_Indirect_Args {
		{vertex_count = 3, instance_count = 1, first_vertex = 0, first_instance = 0},
	}
	indirect_buffer, _ := gfx.create_buffer(&ctx, {
		label = "triangle indirect args",
		usage = {.Indirect, .Immutable},
		data  = gfx.range(indirect_args[:]),
	})
	defer gfx.destroy(&ctx, indirect_buffer)

	shader_package, _ := shader_assets.load("build/shaders/triangle.ashader")
	defer shader_assets.unload(&shader_package)

	shader_desc, _ := shader_assets.shader_desc(&shader_package, .D3D11_DXBC, "triangle shader")
	shader, _ := gfx.create_shader(&ctx, shader_desc)
	defer gfx.destroy(&ctx, shader)

	group_layout, _ := gfx.create_binding_group_layout(&ctx, triangle_shader.binding_group_layout_desc(triangle_shader.GROUP_0, label = "triangle bindings"))
	defer gfx.destroy(&ctx, group_layout)

	pipeline_layout, _ := gfx.create_pipeline_layout(&ctx, {
		label = "triangle pipeline layout",
		group_layouts = {
			triangle_shader.GROUP_0 = group_layout,
		},
	})
	defer gfx.destroy(&ctx, pipeline_layout)

	pipeline, _ := gfx.create_pipeline(&ctx, {
		label          = "triangle pipeline",
		shader         = shader,
		pipeline_layout = pipeline_layout,
		primitive_type = .Triangles,
		index_type     = .None,
		layout         = triangle_shader.layout_desc(),
	})
	defer gfx.destroy(&ctx, pipeline)

	bindings: gfx.Bindings
	bindings.vertex_buffers[0] = {buffer = vertex_buffer}

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

		_ = gfx.begin_pass(&ctx, {
			label = "main triangle indirect",
			action = {colors = {0 = {clear_value = {r = 0.025, g = 0.03, b = 0.045, a = 1}}}},
		})
		_ = gfx.apply_pipeline(&ctx, pipeline)
		_ = gfx.apply_bindings(&ctx, bindings)
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
