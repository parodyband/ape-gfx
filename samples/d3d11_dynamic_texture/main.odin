package main

import "core:fmt"
import gfx_app "ape:gfx_app"
import app "ape:app"
import gfx "ape:gfx"
import textured_quad_shader "ape:assets/shaders/generated/textured_quad"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
TEXTURE_SIZE :: 128
MIP_COUNT :: 4
QUAD_HALF_EXTENT :: f32(0.78)

Vertex :: struct {
	position: [3]f32,
	uv: [2]f32,
}

#assert(u32(size_of(Vertex)) == textured_quad_shader.VERTEX_STRIDE)
#assert(offset_of(Vertex, position) == textured_quad_shader.ATTR_POSITION_OFFSET)
#assert(offset_of(Vertex, uv) == textured_quad_shader.ATTR_TEXCOORD_OFFSET)

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		return
	}
	defer app.shutdown()

	window, ok := app.create_window({
		width = 1280,
		height = 720,
		title = "Ape D3D11 Dynamic Texture",
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
		label = "ape d3d11 dynamic texture",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.shutdown(&ctx)

	vertices := make_quad_vertices(fb_width, fb_height)
	indices := [?]u16{0, 1, 2, 0, 2, 3}

	vertex_buffer, vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "dynamic texture quad vertices",
		usage = {.Vertex, .Dynamic_Update},
		data = gfx.range(vertices[:]),
	})
	if !vertex_buffer_ok {
		fmt.eprintln("vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, vertex_buffer)

	index_buffer, index_buffer_ok := gfx.create_buffer(&ctx, {
		label = "dynamic texture quad indices",
		usage = {.Index, .Immutable},
		data = gfx.range(indices[:]),
	})
	if !index_buffer_ok {
		fmt.eprintln("index buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, index_buffer)

	mip_pixels := [MIP_COUNT][][4]u8 {
		make([][4]u8, 128 * 128),
		make([][4]u8, 64 * 64),
		make([][4]u8, 32 * 32),
		make([][4]u8, 16 * 16),
	}
	defer delete(mip_pixels[0])
	defer delete(mip_pixels[1])
	defer delete(mip_pixels[2])
	defer delete(mip_pixels[3])

	texture, texture_ok := gfx.create_image(&ctx, {
		label = "dynamic mip texture",
		kind = .Image_2D,
		usage = {.Texture, .Dynamic_Update},
		width = TEXTURE_SIZE,
		height = TEXTURE_SIZE,
		mip_count = MIP_COUNT,
		format = .RGBA8,
	})
	if !texture_ok {
		fmt.eprintln("texture creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture)

	texture_view, texture_view_ok := gfx.create_view(&ctx, {
		label = "dynamic mip texture view",
		texture = {
			image = texture,
			format = .RGBA8,
		},
	})
	if !texture_view_ok {
		fmt.eprintln("texture view creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture_view)

	sampler, sampler_ok := gfx.create_sampler(&ctx, {
		label = "dynamic texture sampler",
		min_filter = .Linear,
		mag_filter = .Linear,
		mip_filter = .Linear,
		wrap_u = .Clamp_To_Edge,
		wrap_v = .Clamp_To_Edge,
		wrap_w = .Clamp_To_Edge,
	})
	if !sampler_ok {
		fmt.eprintln("sampler creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, sampler)

	layout := textured_quad_shader.layout_desc()

	program_desc := gfx_app.Shader_Program_Desc {
		package_path = "build/shaders/textured_quad.ashader",
		shader_label = "dynamic texture shader",
		pipeline_desc = {
			label = "dynamic texture pipeline",
			primitive_type = .Triangles,
			index_type = .Uint16,
			layout = layout,
		},
		binding_group_layout_desc = textured_quad_shader.binding_group_layout_desc,
	}
	program: gfx_app.Reloadable_Shader_Program
	if !gfx_app.reloadable_shader_program_init(&ctx, &program, program_desc, {
		shader_name = "textured_quad",
		source_path = "assets/shaders/textured_quad.slang",
		package_path = "build/shaders/textured_quad.ashader",
	}) {
		return
	}
	defer gfx_app.reloadable_shader_program_destroy(&ctx, &program)

	bindings: gfx.Bindings
	bindings.vertex_buffers[0] = {buffer = vertex_buffer, offset = 0}
	bindings.index_buffer = {buffer = index_buffer, offset = 0}
	textured_quad_shader.set_view_material_ape_texture(&bindings, texture_view)
	textured_quad_shader.set_sampler_material_ape_sampler(&bindings, sampler)

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
			vertices = make_quad_vertices(render_width, render_height)
			if !gfx.update_buffer(&ctx, {buffer = vertex_buffer, data = gfx.range(vertices[:])}) {
				fmt.eprintln("vertex buffer update failed: ", gfx.last_error(&ctx))
				return
			}
		}

		if !update_dynamic_texture(&ctx, texture, mip_pixels, frame) {
			fmt.eprintln("texture update failed: ", gfx.last_error(&ctx))
			return
		}

		gfx_app.reloadable_shader_program_poll(&ctx, &program)

		action := gfx.default_pass_action()
		action.colors[0].clear_value = gfx.Color{r = 0.020, g = 0.020, b = 0.026, a = 1}

		if !gfx.begin_pass(&ctx, {label = "main dynamic texture", action = action}) {
			fmt.eprintln("begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, gfx_app.reloadable_shader_program_pipeline(&program)) {
			fmt.eprintln("apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_bindings(&ctx, bindings) {
			fmt.eprintln("apply_bindings failed: ", gfx.last_error(&ctx))
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

update_dynamic_texture :: proc(ctx: ^gfx.Context, texture: gfx.Image, mip_pixels: [MIP_COUNT][][4]u8, frame: int) -> bool {
	width := TEXTURE_SIZE
	height := TEXTURE_SIZE

	for mip in 0..<MIP_COUNT {
		pixels := mip_pixels[mip]
		fill_dynamic_pixels(pixels, width, height, frame, mip)

		if !gfx.update_image(ctx, {
			image = texture,
			mip_level = i32(mip),
			array_layer = 0,
			width = i32(width),
			height = i32(height),
			data = gfx.range(pixels),
		}) {
			return false
		}

		width = max(width / 2, 1)
		height = max(height / 2, 1)
	}

	return true
}

fill_dynamic_pixels :: proc(pixels: [][4]u8, width, height, frame, mip: int) {
	phase := (frame / 4 + mip * 19) & 255
	mip_divisor := 1
	for _ in 0..<mip {
		mip_divisor *= 2
	}
	cell_size := max(4, 16 / mip_divisor)

	for y in 0..<height {
		for x in 0..<width {
			check := ((x / cell_size) + (y / cell_size) + frame / 12) & 1
			index := y * width + x
			if check == 0 {
				pixels[index] = {
					byte(32 + mip * 38),
					byte(96 + phase),
					byte(220 - mip * 32),
					255,
				}
			} else {
				pixels[index] = {
					byte(240 - mip * 24),
					byte(80 + ((x + phase) & 127)),
					byte(48 + ((y * 2 + phase) & 127)),
					255,
				}
			}
		}
	}
}

byte :: proc(value: int) -> u8 {
	return u8(value & 255)
}

make_quad_vertices :: proc(render_width, render_height: i32) -> [4]Vertex {
	half_width, half_height := gfx_app.aspect_fit_half_extents(render_width, render_height, TEXTURE_SIZE, TEXTURE_SIZE, QUAD_HALF_EXTENT)
	return [4]Vertex {
		{position = {-half_width, -half_height, 0}, uv = {0, 1}},
		{position = {-half_width,  half_height, 0}, uv = {0, 0}},
		{position = { half_width,  half_height, 0}, uv = {1, 0}},
		{position = { half_width, -half_height, 0}, uv = {1, 1}},
	}
}
