package main

import "core:fmt"
import app "ape:engine/app"
import gfx "ape:engine/gfx"
import ape_sample "ape:samples/ape_sample"
import triangle_shader "ape:assets/shaders/generated/triangle"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
REFERENCE_ASPECT :: f32(16.0 / 9.0)

Vertex :: struct {
	position: [3]f32,
	color: [3]f32,
}

Frame_Uniforms :: struct {
	ape_frame: [4]f32,
}

#assert(size_of(Frame_Uniforms) == triangle_shader.SIZE_FrameUniforms)
#assert(offset_of(Frame_Uniforms, ape_frame) == triangle_shader.OFFSET_FrameUniforms_ape_frame)
#assert(u32(size_of(Vertex)) == triangle_shader.VERTEX_STRIDE)
#assert(offset_of(Vertex, position) == triangle_shader.ATTR_POSITION_OFFSET)
#assert(offset_of(Vertex, color) == triangle_shader.ATTR_COLOR_OFFSET)

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		return
	}
	defer app.shutdown()

	window, ok := app.create_window({
		width = 1280,
		height = 720,
		title = "Ape D3D11 Triangle",
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
		label = "ape d3d11 triangle",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.shutdown(&ctx)

	vertices := make_triangle_vertices(fb_width, fb_height)

	vertex_buffer, vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "triangle vertices",
		usage = {.Vertex, .Dynamic_Update},
		data = gfx.range(vertices[:]),
	})
	if !vertex_buffer_ok {
		fmt.eprintln("vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, vertex_buffer)

	layout := triangle_shader.layout_desc()

	program_desc := ape_sample.Shader_Program_Desc {
		package_path = "build/shaders/triangle.ashader",
		shader_label = "triangle shader",
		pipeline_desc = {
			label = "triangle pipeline",
			primitive_type = .Triangles,
			index_type = .None,
			layout = layout,
		},
	}
	program: ape_sample.Reloadable_Shader_Program
	if !ape_sample.reloadable_shader_program_init(&ctx, &program, program_desc, {
		shader_name = "triangle",
		source_path = "assets/shaders/triangle.slang",
		package_path = "build/shaders/triangle.ashader",
	}) {
		return
	}
	defer ape_sample.reloadable_shader_program_destroy(&ctx, &program)

	bindings: gfx.Bindings
	bindings.vertex_buffers[0] = {buffer = vertex_buffer, offset = 0}

	render_width := fb_width
	render_height := fb_height
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
			vertices = make_triangle_vertices(render_width, render_height)
			if !gfx.update_buffer(&ctx, {buffer = vertex_buffer, data = gfx.range(vertices[:])}) {
				fmt.eprintln("vertex buffer update failed: ", gfx.last_error(&ctx))
				return
			}
		}

		ape_sample.reloadable_shader_program_poll(&ctx, &program)

		action := gfx.default_pass_action()
		action.colors[0].clear_value = gfx.Color{r = 0.025, g = 0.03, b = 0.045, a = 1}

		if !gfx.begin_pass(&ctx, {label = "main triangle", action = action}) {
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

		t := triangle_wave(frame, 180)
		x_scale := ape_sample.reference_aspect_x_scale(render_width, render_height, REFERENCE_ASPECT)
		uniforms := Frame_Uniforms {
			ape_frame = {
				(t * 2.0 - 1.0) * 0.22 * x_scale,
				0.0,
				0.80 + t * 0.20,
				0.0,
			},
		}
		if !triangle_shader.apply_uniform_FrameUniforms(&ctx, &uniforms) {
			fmt.eprintln("apply_uniform failed: ", gfx.last_error(&ctx))
			return
		}

		if !gfx.draw(&ctx, 0, 3) {
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

triangle_wave :: proc(frame: int, period: int) -> f32 {
	if period <= 1 {
		return 0
	}

	phase := f32(frame % period) / f32(period - 1)
	if phase <= 0.5 {
		return phase * 2.0
	}

	return (1.0 - phase) * 2.0
}

make_triangle_vertices :: proc(render_width, render_height: i32) -> [3]Vertex {
	x_scale := ape_sample.reference_aspect_x_scale(render_width, render_height, REFERENCE_ASPECT)
	return [3]Vertex {
		{position = {0.0, 0.55, 0.0}, color = {1.0, 0.18, 0.12}},
		{position = {0.52 * x_scale, -0.42, 0.0}, color = {0.12, 0.78, 0.32}},
		{position = {-0.52 * x_scale, -0.42, 0.0}, color = {0.18, 0.35, 1.0}},
	}
}
