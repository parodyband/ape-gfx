package main

import "core:fmt"
import gfx_app "ape:gfx_app"
import app "ape:app"
import gfx "ape:gfx"
import mrt_shader "ape:assets/shaders/generated/mrt"
import textured_quad_shader "ape:assets/shaders/generated/textured_quad"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
RENDER_TARGET_SIZE :: 512
DISPLAY_HALF_WIDTH :: f32(0.43)
DISPLAY_HALF_HEIGHT :: f32(0.72)
DISPLAY_GAP :: f32(0.05)

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

#assert(size_of(Frame_Uniforms) == mrt_shader.SIZE_FrameUniforms)
#assert(offset_of(Frame_Uniforms, ape_frame) == mrt_shader.OFFSET_FrameUniforms_ape_frame)
#assert(u32(size_of(Color_Vertex)) == mrt_shader.VERTEX_STRIDE)
#assert(offset_of(Color_Vertex, position) == mrt_shader.ATTR_POSITION_OFFSET)
#assert(offset_of(Color_Vertex, color) == mrt_shader.ATTR_COLOR_OFFSET)
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
		title = "Ape D3D11 MRT",
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
		label = "ape d3d11 mrt",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.shutdown(&ctx)

	features := gfx.query_features(&ctx)
	if !features.multiple_render_targets {
		fmt.eprintln("backend does not report MRT support")
		return
	}

	target_warm, warm_ok := gfx.create_render_target(&ctx, {
		label = "mrt warm target",
		width = RENDER_TARGET_SIZE,
		height = RENDER_TARGET_SIZE,
		color_format = .RGBA8,
		sampled_color = true,
	})
	if !warm_ok {
		fmt.eprintln("warm render target creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy_render_target(&ctx, &target_warm)

	target_cool, cool_ok := gfx.create_render_target(&ctx, {
		label = "mrt cool target",
		width = RENDER_TARGET_SIZE,
		height = RENDER_TARGET_SIZE,
		color_format = .RGBA8,
		sampled_color = true,
	})
	if !cool_ok {
		fmt.eprintln("cool render target creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy_render_target(&ctx, &target_cool)

	sampler, sampler_ok := gfx.create_sampler(&ctx, {
		label = "mrt display sampler",
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
		{position = { 0.00,  0.76, 0}, color = {1.00, 0.18, 0.10}},
		{position = { 0.78, -0.68, 0}, color = {0.12, 0.82, 1.00}},
		{position = {-0.78, -0.68, 0}, color = {0.30, 1.00, 0.22}},
	}
	color_vertex_buffer, color_vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "mrt triangle vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(color_vertices[:]),
	})
	if !color_vertex_buffer_ok {
		fmt.eprintln("color vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, color_vertex_buffer)

	texture_vertices := make_texture_vertices(fb_width, fb_height)
	texture_indices := [?]u16{0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7}

	texture_vertex_buffer, texture_vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "mrt display quad vertices",
		usage = {.Vertex, .Dynamic_Update},
		data = gfx.range(texture_vertices[:]),
	})
	if !texture_vertex_buffer_ok {
		fmt.eprintln("texture vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture_vertex_buffer)

	texture_index_buffer, texture_index_buffer_ok := gfx.create_buffer(&ctx, {
		label = "mrt display quad indices",
		usage = {.Index, .Immutable},
		data = gfx.range(texture_indices[:]),
	})
	if !texture_index_buffer_ok {
		fmt.eprintln("texture index buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture_index_buffer)

	mrt_program_desc := gfx_app.Shader_Program_Desc {
		package_path = "build/shaders/mrt.ashader",
		shader_label = "mrt shader",
		pipeline_desc = {
			label = "mrt offscreen pipeline",
			primitive_type = .Triangles,
			index_type = .None,
			layout = mrt_shader.layout_desc(),
			color_formats = {0 = .RGBA8, 1 = .RGBA8},
		},
		binding_group_layout_desc = mrt_shader.binding_group_layout_desc,
	}
	mrt_program: gfx_app.Reloadable_Shader_Program
	if !gfx_app.reloadable_shader_program_init(&ctx, &mrt_program, mrt_program_desc, {
		shader_name = "mrt",
		source_path = "assets/shaders/mrt.slang",
		package_path = "build/shaders/mrt.ashader",
	}) {
		return
	}
	defer gfx_app.reloadable_shader_program_destroy(&ctx, &mrt_program)

	texture_program_desc := gfx_app.Shader_Program_Desc {
		package_path = "build/shaders/textured_quad.ashader",
		shader_label = "mrt display shader",
		pipeline_desc = {
			label = "mrt display pipeline",
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

	color_bindings: gfx.Bindings
	color_bindings.vertex_buffers[0] = {buffer = color_vertex_buffer}

	texture_bindings: gfx.Bindings
	texture_bindings.vertex_buffers[0] = {buffer = texture_vertex_buffer}
	texture_bindings.index_buffer = {buffer = texture_index_buffer}
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

		gfx_app.reloadable_shader_program_poll(&ctx, &mrt_program)
		gfx_app.reloadable_shader_program_poll(&ctx, &texture_program)

		if !gfx.begin_pass(&ctx, {
			label = "mrt offscreen pass",
			color_attachments = {0 = target_warm.color_attachment, 1 = target_cool.color_attachment},
			action = {colors = {
				0 = {clear_value = {r = 0.08, g = 0.035, b = 0.025, a = 1}},
				1 = {clear_value = {r = 0.02, g = 0.035, b = 0.08, a = 1}},
			}},
		}) {
			fmt.eprintln("mrt begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, gfx_app.reloadable_shader_program_pipeline(&mrt_program)) {
			fmt.eprintln("mrt apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_bindings(&ctx, color_bindings) {
			fmt.eprintln("mrt apply_bindings failed: ", gfx.last_error(&ctx))
			return
		}
		pulse := f32(0.82 + 0.18 * f32(frame % 120) / 119.0)
		frame_uniforms := Frame_Uniforms{ape_frame = {0, 0, pulse, 0}}
		if !mrt_shader.apply_uniform_FrameUniforms(&ctx, &frame_uniforms) {
			fmt.eprintln("mrt apply_uniform failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.draw(&ctx, 0, i32(len(color_vertices))) {
			fmt.eprintln("mrt draw failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.end_pass(&ctx) {
			fmt.eprintln("mrt end_pass failed: ", gfx.last_error(&ctx))
			return
		}

		// APE-16: barrier both MRT color images from Color_Target to Sampled
		// before the display pass binds them as sampled views. D3D11 no-ops;
		// Vulkan/D3D12 require these transitions per attachment.
		mrt_to_sampled := [?]gfx.Image_Transition {
			{image = target_warm.color_image, from = .Color_Target, to = .Sampled},
			{image = target_cool.color_image, from = .Color_Target, to = .Sampled},
		}
		if !gfx.barrier(&ctx, {image_transitions = mrt_to_sampled[:]}) {
			fmt.eprintln("mrt->sampled barrier failed: ", gfx.last_error(&ctx))
			return
		}

		if !gfx.begin_pass(&ctx, {
			label = "mrt display pass",
			action = {colors = {0 = {clear_value = {r = 0.012, g = 0.014, b = 0.018, a = 1}}}},
		}) {
			fmt.eprintln("display begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, gfx_app.reloadable_shader_program_pipeline(&texture_program)) {
			fmt.eprintln("display apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}

		textured_quad_shader.set_view_material_ape_texture(&texture_bindings, target_warm.color_sample)
		if !gfx.apply_bindings(&ctx, texture_bindings) {
			fmt.eprintln("display warm apply_bindings failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.draw(&ctx, 0, 6) {
			fmt.eprintln("display warm draw failed: ", gfx.last_error(&ctx))
			return
		}

		textured_quad_shader.set_view_material_ape_texture(&texture_bindings, target_cool.color_sample)
		if !gfx.apply_bindings(&ctx, texture_bindings) {
			fmt.eprintln("display cool apply_bindings failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.draw(&ctx, 6, 6) {
			fmt.eprintln("display cool draw failed: ", gfx.last_error(&ctx))
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

make_texture_vertices :: proc(render_width, render_height: i32) -> [8]Texture_Vertex {
	half_width, half_height := gfx_app.aspect_fit_half_extents_in_bounds(
		render_width,
		render_height,
		RENDER_TARGET_SIZE,
		RENDER_TARGET_SIZE,
		DISPLAY_HALF_WIDTH,
		DISPLAY_HALF_HEIGHT,
	)
	left_center := -(half_width + DISPLAY_GAP)
	right_center := half_width + DISPLAY_GAP

	return [8]Texture_Vertex {
		{position = {left_center - half_width, -half_height, 0}, uv = {0, 1}},
		{position = {left_center - half_width,  half_height, 0}, uv = {0, 0}},
		{position = {left_center + half_width,  half_height, 0}, uv = {1, 0}},
		{position = {left_center + half_width, -half_height, 0}, uv = {1, 1}},
		{position = {right_center - half_width, -half_height, 0}, uv = {0, 1}},
		{position = {right_center - half_width,  half_height, 0}, uv = {0, 0}},
		{position = {right_center + half_width,  half_height, 0}, uv = {1, 0}},
		{position = {right_center + half_width, -half_height, 0}, uv = {1, 1}},
	}
}
