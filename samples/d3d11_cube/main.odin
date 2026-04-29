package main

import "core:fmt"
import "core:time"
import ape_math "ape:samples/ape_math"
import ape_sample "ape:samples/ape_sample"
import app "ape:app"
import cube_shader "ape:assets/shaders/generated/cube"
import gfx "ape:gfx"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
ROTATION_RADIANS_PER_SECOND :: f32(0.5)

Vertex :: struct {
	position: [3]f32,
	color: [3]f32,
}

Frame_Uniforms :: struct {
	ape_mvp: ape_math.Mat4,
}

#assert(size_of(Frame_Uniforms) == cube_shader.SIZE_FrameUniforms)
#assert(offset_of(Frame_Uniforms, ape_mvp) == cube_shader.OFFSET_FrameUniforms_ape_mvp)
#assert(u32(size_of(Vertex)) == cube_shader.VERTEX_STRIDE)
#assert(offset_of(Vertex, position) == cube_shader.ATTR_POSITION_OFFSET)
#assert(offset_of(Vertex, color) == cube_shader.ATTR_COLOR_OFFSET)

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		return
	}
	defer app.shutdown()

	window, ok := app.create_window({
		width = 1280,
		height = 720,
		title = "Ape D3D11 Cube",
		no_client_api = true,
	})
	if !ok {
		fmt.eprintln("window creation failed")
		return
	}
	defer app.destroy_window(&window)

	fb_width, fb_height := app.framebuffer_size(&window)
	ctx, gfx_ok := gfx.init({
		backend = .D3D11,
		width = fb_width,
		height = fb_height,
		native_window = app.native_window_handle(&window),
		swapchain_format = .BGRA8,
		vsync = true,
		debug = true,
		label = "ape d3d11 cube",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.shutdown(&ctx)

	vertices := [?]Vertex {
		{position = {-1, -1, -1}, color = {1.00, 0.20, 0.18}},
		{position = {-1,  1, -1}, color = {1.00, 0.20, 0.18}},
		{position = { 1,  1, -1}, color = {1.00, 0.20, 0.18}},
		{position = { 1, -1, -1}, color = {1.00, 0.20, 0.18}},

		{position = { 1, -1,  1}, color = {0.18, 0.44, 1.00}},
		{position = { 1,  1,  1}, color = {0.18, 0.44, 1.00}},
		{position = {-1,  1,  1}, color = {0.18, 0.44, 1.00}},
		{position = {-1, -1,  1}, color = {0.18, 0.44, 1.00}},

		{position = {-1,  1, -1}, color = {0.24, 0.82, 0.36}},
		{position = {-1,  1,  1}, color = {0.24, 0.82, 0.36}},
		{position = { 1,  1,  1}, color = {0.24, 0.82, 0.36}},
		{position = { 1,  1, -1}, color = {0.24, 0.82, 0.36}},

		{position = {-1, -1,  1}, color = {1.00, 0.76, 0.18}},
		{position = {-1, -1, -1}, color = {1.00, 0.76, 0.18}},
		{position = { 1, -1, -1}, color = {1.00, 0.76, 0.18}},
		{position = { 1, -1,  1}, color = {1.00, 0.76, 0.18}},

		{position = {-1, -1,  1}, color = {0.75, 0.32, 1.00}},
		{position = {-1,  1,  1}, color = {0.75, 0.32, 1.00}},
		{position = {-1,  1, -1}, color = {0.75, 0.32, 1.00}},
		{position = {-1, -1, -1}, color = {0.75, 0.32, 1.00}},

		{position = { 1, -1, -1}, color = {0.16, 0.86, 0.82}},
		{position = { 1,  1, -1}, color = {0.16, 0.86, 0.82}},
		{position = { 1,  1,  1}, color = {0.16, 0.86, 0.82}},
		{position = { 1, -1,  1}, color = {0.16, 0.86, 0.82}},
	}

	indices := [?]u16 {
		 0,  1,  2,  0,  2,  3,
		 4,  5,  6,  4,  6,  7,
		 8,  9, 10,  8, 10, 11,
		12, 13, 14, 12, 14, 15,
		16, 17, 18, 16, 18, 19,
		20, 21, 22, 20, 22, 23,
	}

	vertex_buffer, vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "cube vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(vertices[:]),
	})
	if !vertex_buffer_ok {
		fmt.eprintln("vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, vertex_buffer)

	index_buffer, index_buffer_ok := gfx.create_buffer(&ctx, {
		label = "cube indices",
		usage = {.Index, .Immutable},
		data = gfx.range(indices[:]),
	})
	if !index_buffer_ok {
		fmt.eprintln("index buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, index_buffer)

	layout := cube_shader.layout_desc()

	program_desc := ape_sample.Shader_Program_Desc {
		package_path = "build/shaders/cube.ashader",
		shader_label = "cube shader",
		pipeline_desc = {
			label = "cube pipeline",
			primitive_type = .Triangles,
			index_type = .Uint16,
			layout = layout,
			depth = {
				format = .D32F,
				enabled = true,
				write_enabled = true,
				compare = .Less_Equal,
			},
			raster = {
				fill_mode = .Solid,
				cull_mode = .None,
				winding = .Clockwise,
			},
		},
	}
	program: ape_sample.Reloadable_Shader_Program
	if !ape_sample.reloadable_shader_program_init(&ctx, &program, program_desc, {
		shader_name = "cube",
		source_path = "assets/shaders/cube.slang",
		package_path = "build/shaders/cube.ashader",
	}) {
		return
	}
	defer ape_sample.reloadable_shader_program_destroy(&ctx, &program)

	bindings: gfx.Bindings
	bindings.vertex_buffers[0] = {buffer = vertex_buffer, offset = 0}
	bindings.index_buffer = {buffer = index_buffer, offset = 0}

	render_width := fb_width
	render_height := fb_height
	projection := ape_math.cube_projection(render_width, render_height)
	view := ape_math.translation(0, 0, 4.5)

	start_tick := time.tick_now()
	frame := 0
	for !app.should_close(&window) {
		app.poll_events()

		resize, resize_ok := ape_sample.resize_swapchain(&ctx, &window, &render_width, &render_height)
		if !resize_ok {
			fmt.eprintln("resize failed: ", gfx.last_error(&ctx))
			return
		}
		if !resize.active {
			continue
		}
		if resize.resized {
			projection = ape_math.cube_projection(render_width, render_height)
		}

		ape_sample.reloadable_shader_program_poll(&ctx, &program)

		action := gfx.default_pass_action()
		action.colors[0].clear_value = gfx.Color{r = 0.018, g = 0.021, b = 0.030, a = 1}
		action.depth.clear_value = 1

		if !gfx.begin_pass(&ctx, {label = "main cube", action = action}) {
			fmt.eprintln("begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, ape_sample.reloadable_shader_program_pipeline(&program)) {
			fmt.eprintln("apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_bindings(&ctx, bindings) {
			fmt.eprintln("apply_bindings failed: ", gfx.last_error(&ctx))
			return
		}

		elapsed_seconds := f32(time.duration_seconds(time.tick_since(start_tick)))
		angle := elapsed_seconds * ROTATION_RADIANS_PER_SECOND
		model := ape_math.mul(ape_math.rotation_y(angle), ape_math.rotation_x(angle * 0.71))
		view_model := ape_math.mul(view, model)
		uniforms := Frame_Uniforms {
			ape_mvp = ape_math.mul(projection, view_model),
		}
		if !cube_shader.apply_uniform_FrameUniforms(&ctx, &uniforms) {
			fmt.eprintln("apply_uniform failed: ", gfx.last_error(&ctx))
			return
		}

		if !gfx.draw(&ctx, 0, i32(len(indices))) {
			fmt.eprintln("draw failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.end_pass(&ctx) {
			fmt.eprintln("end_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.commit(&ctx) {
			fmt.eprintln("commit failed: ", gfx.last_error(&ctx))
			return
		}

		frame += 1
		when AUTO_EXIT_FRAMES > 0 {
			if frame >= AUTO_EXIT_FRAMES {
				break
			}
		}
	}
}
