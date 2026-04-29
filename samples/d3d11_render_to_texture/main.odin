package main

import "core:fmt"
import gfx_app "ape:gfx_app"
import app "ape:app"
import gfx "ape:gfx"
import textured_quad_shader "ape:assets/shaders/generated/textured_quad"
import triangle_shader "ape:assets/shaders/generated/triangle"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
RENDER_TARGET_SIZE :: 512
DISPLAY_HALF_EXTENT :: f32(0.78)

Color_Vertex :: struct {
	position: [3]f32,
	color: [3]f32,
}

Texture_Vertex :: struct {
	position: [3]f32,
	uv: [2]f32,
}

Frame_Uniforms :: struct {
	ape_frame: [4]f32,
}

#assert(size_of(Frame_Uniforms) == triangle_shader.SIZE_FrameUniforms)
#assert(offset_of(Frame_Uniforms, ape_frame) == triangle_shader.OFFSET_FrameUniforms_ape_frame)
#assert(u32(size_of(Color_Vertex)) == triangle_shader.VERTEX_STRIDE)
#assert(offset_of(Color_Vertex, position) == triangle_shader.ATTR_POSITION_OFFSET)
#assert(offset_of(Color_Vertex, color) == triangle_shader.ATTR_COLOR_OFFSET)
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
		title = "Ape D3D11 Render To Texture",
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
		label = "ape d3d11 render to texture",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.shutdown(&ctx)

	offscreen_image, offscreen_image_ok := gfx.create_image(&ctx, {
		label = "offscreen color image",
		kind = .Image_2D,
		usage = {.Texture, .Color_Attachment},
		width = RENDER_TARGET_SIZE,
		height = RENDER_TARGET_SIZE,
		format = .RGBA8,
	})
	if !offscreen_image_ok {
		fmt.eprintln("offscreen image creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, offscreen_image)

	offscreen_color_view, offscreen_color_view_ok := gfx.create_view(&ctx, {
		label = "offscreen color attachment",
		color_attachment = {
			image = offscreen_image,
			format = .RGBA8,
		},
	})
	if !offscreen_color_view_ok {
		fmt.eprintln("offscreen color view creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, offscreen_color_view)

	offscreen_sample_view, offscreen_sample_view_ok := gfx.create_view(&ctx, {
		label = "offscreen sampled view",
		texture = {
			image = offscreen_image,
			format = .RGBA8,
		},
	})
	if !offscreen_sample_view_ok {
		fmt.eprintln("offscreen sampled view creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, offscreen_sample_view)

	sampler, sampler_ok := gfx.create_sampler(&ctx, {
		label = "offscreen linear sampler",
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

	color_vertices := [?]Color_Vertex {
		{position = { 0.0,  0.72, 0}, color = {1.00, 0.16, 0.12}},
		{position = { 0.72, -0.62, 0}, color = {0.10, 0.74, 1.00}},
		{position = {-0.72, -0.62, 0}, color = {0.18, 0.92, 0.32}},
	}
	color_vertex_buffer, color_vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "offscreen triangle vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(color_vertices[:]),
	})
	if !color_vertex_buffer_ok {
		fmt.eprintln("color vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, color_vertex_buffer)

	texture_vertices := make_texture_vertices(fb_width, fb_height)
	texture_indices := [?]u16{0, 1, 2, 0, 2, 3}

	texture_vertex_buffer, texture_vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "resolved quad vertices",
		usage = {.Vertex, .Dynamic_Update},
		data = gfx.range(texture_vertices[:]),
	})
	if !texture_vertex_buffer_ok {
		fmt.eprintln("texture vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture_vertex_buffer)

	texture_index_buffer, texture_index_buffer_ok := gfx.create_buffer(&ctx, {
		label = "resolved quad indices",
		usage = {.Index, .Immutable},
		data = gfx.range(texture_indices[:]),
	})
	if !texture_index_buffer_ok {
		fmt.eprintln("texture index buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture_index_buffer)

	color_layout := triangle_shader.layout_desc()

	color_program_desc := gfx_app.Shader_Program_Desc {
		package_path = "build/shaders/triangle.ashader",
		shader_label = "offscreen triangle shader",
		pipeline_desc = {
			label = "offscreen color pipeline",
			primitive_type = .Triangles,
			index_type = .None,
			layout = color_layout,
			color_formats = {0 = .RGBA8},
		},
		binding_group_layout_desc = triangle_shader.binding_group_layout_desc,
	}
	color_program: gfx_app.Reloadable_Shader_Program
	if !gfx_app.reloadable_shader_program_init(&ctx, &color_program, color_program_desc, {
		shader_name = "triangle",
		source_path = "assets/shaders/triangle.slang",
		package_path = "build/shaders/triangle.ashader",
	}) {
		return
	}
	defer gfx_app.reloadable_shader_program_destroy(&ctx, &color_program)

	texture_layout := textured_quad_shader.layout_desc()

	texture_program_desc := gfx_app.Shader_Program_Desc {
		package_path = "build/shaders/textured_quad.ashader",
		shader_label = "texture resolve shader",
		pipeline_desc = {
			label = "texture resolve pipeline",
			primitive_type = .Triangles,
			index_type = .Uint16,
			layout = texture_layout,
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

	color_bindings: gfx.Bindings
	color_bindings.vertex_buffers[0] = {buffer = color_vertex_buffer, offset = 0}

	texture_bindings: gfx.Bindings
	texture_bindings.vertex_buffers[0] = {buffer = texture_vertex_buffer, offset = 0}
	texture_bindings.index_buffer = {buffer = texture_index_buffer, offset = 0}
	textured_quad_shader.set_view_material_ape_texture(&texture_bindings, offscreen_sample_view)
	textured_quad_shader.set_sampler_material_ape_sampler(&texture_bindings, sampler)

	render_width := fb_width
	render_height := fb_height
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

		gfx_app.reloadable_shader_program_poll(&ctx, &color_program)
		gfx_app.reloadable_shader_program_poll(&ctx, &texture_program)

		offscreen_action := gfx.default_pass_action()
		offscreen_action.colors[0].clear_value = gfx.Color{r = 0.04, g = 0.045, b = 0.06, a = 1}

		if !gfx.begin_pass(&ctx, {
			label = "offscreen color pass",
			color_attachments = {0 = offscreen_color_view},
			action = offscreen_action,
		}) {
			fmt.eprintln("offscreen begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, gfx_app.reloadable_shader_program_pipeline(&color_program)) {
			fmt.eprintln("offscreen apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_bindings(&ctx, color_bindings) {
			fmt.eprintln("offscreen apply_bindings failed: ", gfx.last_error(&ctx))
			return
		}
		color_uniforms := Frame_Uniforms{ape_frame = {0, 0, 1, 0}}
		if !triangle_shader.apply_uniform_FrameUniforms(&ctx, &color_uniforms) {
			fmt.eprintln("offscreen apply_uniform failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.draw(&ctx, 0, i32(len(color_vertices))) {
			fmt.eprintln("offscreen draw failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.end_pass(&ctx) {
			fmt.eprintln("offscreen end_pass failed: ", gfx.last_error(&ctx))
			return
		}

		swapchain_action := gfx.default_pass_action()
		swapchain_action.colors[0].clear_value = gfx.Color{r = 0.015, g = 0.018, b = 0.024, a = 1}

		if !gfx.begin_pass(&ctx, {label = "main resolve pass", action = swapchain_action}) {
			fmt.eprintln("swapchain begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, gfx_app.reloadable_shader_program_pipeline(&texture_program)) {
			fmt.eprintln("resolve apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_bindings(&ctx, texture_bindings) {
			fmt.eprintln("resolve apply_bindings failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.draw(&ctx, 0, i32(len(texture_indices))) {
			fmt.eprintln("resolve draw failed: ", gfx.last_error(&ctx))
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
	half_width, half_height := gfx_app.aspect_fit_half_extents(render_width, render_height, RENDER_TARGET_SIZE, RENDER_TARGET_SIZE, DISPLAY_HALF_EXTENT)
	return [4]Texture_Vertex {
		{position = {-half_width, -half_height, 0}, uv = {0, 1}},
		{position = {-half_width,  half_height, 0}, uv = {0, 0}},
		{position = { half_width,  half_height, 0}, uv = {1, 0}},
		{position = { half_width, -half_height, 0}, uv = {1, 1}},
	}
}
