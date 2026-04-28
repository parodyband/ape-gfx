package main

import "core:fmt"
import ape_sample "ape:samples/ape_sample"
import app "ape:engine/app"
import gfx "ape:engine/gfx"
import textured_quad_shader "ape:assets/shaders/generated/textured_quad"
import triangle_shader "ape:assets/shaders/generated/triangle"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
RENDER_TARGET_SIZE :: 512
MSAA_SAMPLE_COUNT :: 4
DISPLAY_HALF_EXTENT :: f32(0.82)

Color_Vertex :: struct {
	position: [3]f32,
	color: [3]f32,
}

Texture_Vertex :: struct {
	position: [3]f32,
	uv: [2]f32,
}

Frame_Uniforms :: struct {
	frame: [4]f32,
}

#assert(size_of(Frame_Uniforms) == triangle_shader.SIZE_FrameUniforms)
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
		title = "Ape D3D11 MSAA Resolve",
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
		label = "ape d3d11 msaa",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.shutdown(&ctx)

	features := gfx.query_features(&ctx)
	if !features.msaa_render_targets {
		fmt.eprintln("backend does not report MSAA render target support")
		return
	}

	msaa_image, msaa_image_ok := gfx.create_image(&ctx, {
		label = "msaa color image",
		kind = .Image_2D,
		usage = {.Color_Attachment},
		width = RENDER_TARGET_SIZE,
		height = RENDER_TARGET_SIZE,
		mip_count = 1,
		array_count = 1,
		sample_count = MSAA_SAMPLE_COUNT,
		format = .RGBA8,
	})
	if !msaa_image_ok {
		fmt.eprintln("msaa image creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, msaa_image)

	msaa_color_view, msaa_color_view_ok := gfx.create_view(&ctx, {
		label = "msaa color attachment",
		color_attachment = {
			image = msaa_image,
			format = .RGBA8,
		},
	})
	if !msaa_color_view_ok {
		fmt.eprintln("msaa color view creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, msaa_color_view)

	resolved_image, resolved_image_ok := gfx.create_image(&ctx, {
		label = "resolved color image",
		kind = .Image_2D,
		usage = {.Texture},
		width = RENDER_TARGET_SIZE,
		height = RENDER_TARGET_SIZE,
		mip_count = 1,
		array_count = 1,
		sample_count = 1,
		format = .RGBA8,
	})
	if !resolved_image_ok {
		fmt.eprintln("resolved image creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, resolved_image)

	resolved_sample_view, resolved_sample_view_ok := gfx.create_view(&ctx, {
		label = "resolved sampled view",
		texture = {
			image = resolved_image,
			format = .RGBA8,
		},
	})
	if !resolved_sample_view_ok {
		fmt.eprintln("resolved sample view creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, resolved_sample_view)

	sampler, sampler_ok := gfx.create_sampler(&ctx, {
		label = "resolved linear sampler",
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
		{position = {-0.74, -0.70, 0}, color = {1.00, 0.18, 0.12}},
		{position = {-0.40,  0.72, 0}, color = {0.18, 0.92, 0.35}},
		{position = {-0.05, -0.70, 0}, color = {0.16, 0.55, 1.00}},
		{position = { 0.05, -0.70, 0}, color = {1.00, 0.18, 0.12}},
		{position = { 0.40,  0.72, 0}, color = {0.18, 0.92, 0.35}},
		{position = { 0.74, -0.70, 0}, color = {0.16, 0.55, 1.00}},
	}
	color_vertex_buffer, color_vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "msaa triangle vertices",
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
		label = "msaa display quad vertices",
		usage = {.Vertex, .Dynamic_Update},
		data = gfx.range(texture_vertices[:]),
	})
	if !texture_vertex_buffer_ok {
		fmt.eprintln("texture vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture_vertex_buffer)

	texture_index_buffer, texture_index_buffer_ok := gfx.create_buffer(&ctx, {
		label = "msaa display quad indices",
		usage = {.Index, .Immutable},
		data = gfx.range(texture_indices[:]),
	})
	if !texture_index_buffer_ok {
		fmt.eprintln("texture index buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture_index_buffer)

	color_program_desc := ape_sample.Shader_Program_Desc {
		package_path = "build/shaders/triangle.ashader",
		shader_label = "msaa triangle shader",
		pipeline_desc = {
			label = "msaa offscreen pipeline",
			primitive_type = .Triangles,
			index_type = .None,
			layout = triangle_shader.layout_desc(),
			color_formats = {0 = .RGBA8},
		},
	}
	color_program: ape_sample.Reloadable_Shader_Program
	if !ape_sample.reloadable_shader_program_init(&ctx, &color_program, color_program_desc, {
		shader_name = "triangle",
		source_path = "assets/shaders/triangle.slang",
		package_path = "build/shaders/triangle.ashader",
	}) {
		return
	}
	defer ape_sample.reloadable_shader_program_destroy(&ctx, &color_program)

	texture_program_desc := ape_sample.Shader_Program_Desc {
		package_path = "build/shaders/textured_quad.ashader",
		shader_label = "msaa display shader",
		pipeline_desc = {
			label = "msaa display pipeline",
			primitive_type = .Triangles,
			index_type = .Uint16,
			layout = textured_quad_shader.layout_desc(),
		},
	}
	texture_program: ape_sample.Reloadable_Shader_Program
	if !ape_sample.reloadable_shader_program_init(&ctx, &texture_program, texture_program_desc, {
		shader_name = "textured_quad",
		source_path = "assets/shaders/textured_quad.slang",
		package_path = "build/shaders/textured_quad.ashader",
	}) {
		return
	}
	defer ape_sample.reloadable_shader_program_destroy(&ctx, &texture_program)

	color_bindings: gfx.Bindings
	color_bindings.vertex_buffers[0] = {buffer = color_vertex_buffer}

	texture_bindings: gfx.Bindings
	texture_bindings.vertex_buffers[0] = {buffer = texture_vertex_buffer}
	texture_bindings.index_buffer = {buffer = texture_index_buffer}
	textured_quad_shader.set_view_ape_texture(&texture_bindings, resolved_sample_view)
	textured_quad_shader.set_sampler_ape_sampler(&texture_bindings, sampler)

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
			texture_vertices = make_texture_vertices(render_width, render_height)
			if !gfx.update_buffer(&ctx, {buffer = texture_vertex_buffer, data = gfx.range(texture_vertices[:])}) {
				fmt.eprintln("texture vertex buffer update failed: ", gfx.last_error(&ctx))
				return
			}
		}

		ape_sample.reloadable_shader_program_poll(&ctx, &color_program)
		ape_sample.reloadable_shader_program_poll(&ctx, &texture_program)

		offscreen_action := gfx.default_pass_action()
		offscreen_action.colors[0].clear_value = gfx.Color{r = 0.035, g = 0.04, b = 0.052, a = 1}

		if !gfx.begin_pass(&ctx, {
			label = "msaa offscreen pass",
			color_attachments = {0 = msaa_color_view},
			action = offscreen_action,
		}) {
			fmt.eprintln("offscreen begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, ape_sample.reloadable_shader_program_pipeline(&color_program)) {
			fmt.eprintln("offscreen apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_bindings(&ctx, color_bindings) {
			fmt.eprintln("offscreen apply_bindings failed: ", gfx.last_error(&ctx))
			return
		}
		color_uniforms := Frame_Uniforms{frame = {0, 0, 1, 0}}
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

		if !gfx.resolve_image(&ctx, {source = msaa_image, destination = resolved_image}) {
			fmt.eprintln("resolve_image failed: ", gfx.last_error(&ctx))
			return
		}

		swapchain_action := gfx.default_pass_action()
		swapchain_action.colors[0].clear_value = gfx.Color{r = 0.012, g = 0.014, b = 0.018, a = 1}
		if !gfx.begin_pass(&ctx, {label = "msaa display pass", action = swapchain_action}) {
			fmt.eprintln("display begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, ape_sample.reloadable_shader_program_pipeline(&texture_program)) {
			fmt.eprintln("display apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_bindings(&ctx, texture_bindings) {
			fmt.eprintln("display apply_bindings failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.draw(&ctx, 0, i32(len(texture_indices))) {
			fmt.eprintln("display draw failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.end_pass(&ctx) {
			fmt.eprintln("display end_pass failed: ", gfx.last_error(&ctx))
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
	half_width, half_height := ape_sample.aspect_fit_half_extents(render_width, render_height, RENDER_TARGET_SIZE, RENDER_TARGET_SIZE, DISPLAY_HALF_EXTENT)
	return [4]Texture_Vertex {
		{position = {-half_width, -half_height, 0}, uv = {0, 1}},
		{position = {-half_width,  half_height, 0}, uv = {0, 0}},
		{position = { half_width,  half_height, 0}, uv = {1, 0}},
		{position = { half_width, -half_height, 0}, uv = {1, 1}},
	}
}
