package main

import "core:fmt"
import "core:time"
import ape_math "ape:samples/ape_math"
import gfx_app "ape:gfx_app"
import app "ape:app"
import cube_shader "ape:assets/shaders/generated/cube"
import gfx "ape:gfx"
import textured_quad_shader "ape:assets/shaders/generated/textured_quad"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
OFFSCREEN_SIZE :: 768
ROTATION_RADIANS_PER_SECOND :: f32(0.45)
DISPLAY_HALF_EXTENT :: f32(0.80)

Cube_Vertex :: struct {
	position: [3]f32,
	color: [3]f32,
}

Texture_Vertex :: struct {
	position: [3]f32,
	uv: [2]f32,
}

Cube_Uniforms :: struct {
	ape_mvp: ape_math.Mat4,
}

#assert(size_of(Cube_Uniforms) == cube_shader.SIZE_FrameUniforms)
#assert(offset_of(Cube_Uniforms, ape_mvp) == cube_shader.OFFSET_FrameUniforms_ape_mvp)
#assert(u32(size_of(Cube_Vertex)) == cube_shader.VERTEX_STRIDE)
#assert(offset_of(Cube_Vertex, position) == cube_shader.ATTR_POSITION_OFFSET)
#assert(offset_of(Cube_Vertex, color) == cube_shader.ATTR_COLOR_OFFSET)
#assert(u32(size_of(Texture_Vertex)) == textured_quad_shader.VERTEX_STRIDE)
#assert(offset_of(Texture_Vertex, position) == textured_quad_shader.ATTR_POSITION_OFFSET)
#assert(offset_of(Texture_Vertex, uv) == textured_quad_shader.ATTR_TEXCOORD_OFFSET)

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		return
	}
	defer app.shutdown()

	window, ok := app.create_window({
		width = 1280,
		height = 720,
		title = "Ape D3D11 GFX Lab",
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
		label = "ape d3d11 gfx lab",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.shutdown(&ctx)

	offscreen_target, offscreen_target_ok := gfx.create_render_target(&ctx, {
		label = "lab offscreen target",
		width = OFFSCREEN_SIZE,
		height = OFFSCREEN_SIZE,
		color_format = .RGBA8,
		depth_format = .D32F,
		sampled_color = true,
	})
	if !offscreen_target_ok {
		fmt.eprintln("offscreen target creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy_render_target(&ctx, &offscreen_target)

	sampler, sampler_ok := gfx.create_sampler(&ctx, {
		label = "lab offscreen sampler",
		min_filter = .Linear,
		mag_filter = .Linear,
		mip_filter = .Nearest,
		wrap_u = .Clamp_To_Edge,
		wrap_v = .Clamp_To_Edge,
		wrap_w = .Clamp_To_Edge,
	})
	if !sampler_ok {
		fmt.eprintln("sampler creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, sampler)

	cube_vertices := [?]Cube_Vertex {
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
	cube_indices := [?]u16 {
		 0,  1,  2,  0,  2,  3,
		 4,  5,  6,  4,  6,  7,
		 8,  9, 10,  8, 10, 11,
		12, 13, 14, 12, 14, 15,
		16, 17, 18, 16, 18, 19,
		20, 21, 22, 20, 22, 23,
	}

	cube_vertex_buffer, cube_vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "lab cube vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(cube_vertices[:]),
	})
	if !cube_vertex_buffer_ok {
		fmt.eprintln("cube vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, cube_vertex_buffer)

	cube_index_buffer, cube_index_buffer_ok := gfx.create_buffer(&ctx, {
		label = "lab cube indices",
		usage = {.Index, .Immutable},
		data = gfx.range(cube_indices[:]),
	})
	if !cube_index_buffer_ok {
		fmt.eprintln("cube index buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, cube_index_buffer)

	texture_vertices := make_texture_vertices(fb_width, fb_height)
	texture_indices := [?]u16{0, 1, 2, 0, 2, 3}

	texture_vertex_buffer, texture_vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "lab display quad vertices",
		usage = {.Vertex, .Dynamic_Update},
		data = gfx.range(texture_vertices[:]),
	})
	if !texture_vertex_buffer_ok {
		fmt.eprintln("texture vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture_vertex_buffer)

	texture_index_buffer, texture_index_buffer_ok := gfx.create_buffer(&ctx, {
		label = "lab display quad indices",
		usage = {.Index, .Immutable},
		data = gfx.range(texture_indices[:]),
	})
	if !texture_index_buffer_ok {
		fmt.eprintln("texture index buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture_index_buffer)

	cube_program_desc := gfx_app.Shader_Program_Desc {
		package_path = "build/shaders/cube.ashader",
		shader_label = "lab cube shader",
		pipeline_desc = {
			label = "lab cube pipeline",
			primitive_type = .Triangles,
			index_type = .Uint16,
			layout = cube_shader.layout_desc(),
			color_formats = {0 = .RGBA8},
			depth = {
				format = .D32F,
				enabled = true,
				write_enabled = true,
				compare = .Less_Equal,
			},
			raster = {
				fill_mode = .Solid,
				cull_mode = .Back,
				winding = .Clockwise,
			},
		},
		binding_group_layout_desc = cube_shader.binding_group_layout_desc,
	}
	cube_program: gfx_app.Reloadable_Shader_Program
	if !gfx_app.reloadable_shader_program_init(&ctx, &cube_program, cube_program_desc, {
		shader_name = "cube",
		source_path = "assets/shaders/cube.slang",
		package_path = "build/shaders/cube.ashader",
	}) {
		return
	}
	defer gfx_app.reloadable_shader_program_destroy(&ctx, &cube_program)

	texture_program_desc := gfx_app.Shader_Program_Desc {
		package_path = "build/shaders/textured_quad.ashader",
		shader_label = "lab display shader",
		pipeline_desc = {
			label = "lab display pipeline",
			primitive_type = .Triangles,
			index_type = .Uint16,
			layout = textured_quad_shader.layout_desc(),
		},
		binding_group_layout_desc = textured_quad_shader.binding_group_layout_desc,
	}
	texture_program: gfx_app.Reloadable_Shader_Program
	if !gfx_app.reloadable_shader_program_init(&ctx, &texture_program, texture_program_desc, {
		shader_name = "textured_quad",
		source_path = "assets/shaders/textured_quad.slang",
		package_path = "build/shaders/textured_quad.ashader",
	}) {
		return
	}
	defer gfx_app.reloadable_shader_program_destroy(&ctx, &texture_program)

	texture_group_layout := gfx_app.reloadable_shader_program_binding_group_layout(&texture_program, textured_quad_shader.GROUP_0)

	cube_bindings: gfx.Bindings
	cube_bindings.vertex_buffers[0] = {buffer = cube_vertex_buffer, offset = 0}
	cube_bindings.index_buffer = {buffer = cube_index_buffer, offset = 0}

	texture_bindings: gfx.Bindings
	texture_bindings.vertex_buffers[0] = {buffer = texture_vertex_buffer, offset = 0}
	texture_bindings.index_buffer = {buffer = texture_index_buffer, offset = 0}

	texture_group_desc: gfx.Binding_Group_Desc
	texture_group_desc.layout = texture_group_layout
	textured_quad_shader.set_group_view_material_ape_texture(&texture_group_desc, offscreen_target.color_sample)
	textured_quad_shader.set_group_sampler_material_ape_sampler(&texture_group_desc, sampler)
	texture_group, texture_group_ok := gfx.create_binding_group(&ctx, texture_group_desc)
	if !texture_group_ok {
		fmt.eprintln("texture binding group creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture_group)

	render_width := fb_width
	render_height := fb_height
	projection := ape_math.cube_projection(OFFSCREEN_SIZE, OFFSCREEN_SIZE)
	view := ape_math.translation(0, 0, 4.25)

	start_tick := time.tick_now()
	frame := 0
	for !app.should_close(&window) {
		app.poll_events()

		resize, resize_ok := gfx_app.resize_swapchain(&ctx, &window, &render_width, &render_height)
		if !resize_ok {
			fmt.eprintln("resize failed: ", gfx.last_error(&ctx))
			return
		}
		if !resize.active {
			continue
		}
		if resize.resized {
			texture_vertices = make_texture_vertices(render_width, render_height)
			if !gfx.update_buffer(&ctx, {buffer = texture_vertex_buffer, data = gfx.range(texture_vertices[:])}) {
				fmt.eprintln("texture vertex buffer update failed: ", gfx.last_error(&ctx))
				return
			}
		}

		gfx_app.reloadable_shader_program_poll(&ctx, &cube_program)
		gfx_app.reloadable_shader_program_poll(&ctx, &texture_program)

		offscreen_action := gfx.Pass_Action{colors = {0 = {clear_value = {r = 0.035, g = 0.040, b = 0.052, a = 1}}}}

		if !gfx.begin_pass(&ctx, gfx.render_target_pass_desc(offscreen_target, "lab offscreen cube pass", offscreen_action)) {
			fmt.eprintln("offscreen begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, gfx_app.reloadable_shader_program_pipeline(&cube_program)) {
			fmt.eprintln("offscreen apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_bindings(&ctx, cube_bindings) {
			fmt.eprintln("offscreen apply_bindings failed: ", gfx.last_error(&ctx))
			return
		}

		elapsed_seconds := f32(time.duration_seconds(time.tick_since(start_tick)))
		angle := elapsed_seconds * ROTATION_RADIANS_PER_SECOND
		model := ape_math.mul(ape_math.rotation_y(angle), ape_math.rotation_x(angle * 0.68))
		view_model := ape_math.mul(view, model)
		cube_uniforms := Cube_Uniforms {
			ape_mvp = ape_math.mul(projection, view_model),
		}
		if !cube_shader.apply_uniform_FrameUniforms(&ctx, &cube_uniforms) {
			fmt.eprintln("offscreen apply_uniform failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.draw(&ctx, 0, i32(len(cube_indices))) {
			fmt.eprintln("offscreen draw failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.end_pass(&ctx) {
			fmt.eprintln("offscreen end_pass failed: ", gfx.last_error(&ctx))
			return
		}

		if !gfx.begin_pass(&ctx, {
			label = "lab swapchain display pass",
			action = {colors = {0 = {clear_value = {r = 0.010, g = 0.012, b = 0.016, a = 1}}}},
		}) {
			fmt.eprintln("swapchain begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, gfx_app.reloadable_shader_program_pipeline(&texture_program)) {
			fmt.eprintln("display apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_binding_group(&ctx, texture_group, texture_bindings) {
			fmt.eprintln("display apply_binding_group failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.draw(&ctx, 0, i32(len(texture_indices))) {
			fmt.eprintln("display draw failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.end_pass(&ctx) {
			fmt.eprintln("swapchain end_pass failed: ", gfx.last_error(&ctx))
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

make_texture_vertices :: proc(render_width, render_height: i32) -> [4]Texture_Vertex {
	half_width, half_height := gfx_app.aspect_fit_half_extents(render_width, render_height, OFFSCREEN_SIZE, OFFSCREEN_SIZE, DISPLAY_HALF_EXTENT)
	return [4]Texture_Vertex {
		{position = {-half_width, -half_height, 0}, uv = {0, 1}},
		{position = {-half_width,  half_height, 0}, uv = {0, 0}},
		{position = { half_width,  half_height, 0}, uv = {1, 0}},
		{position = { half_width, -half_height, 0}, uv = {1, 1}},
	}
}
