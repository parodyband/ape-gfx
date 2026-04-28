package main

import "core:fmt"
import "core:os"
import "core:time"
import ape_math "ape:samples/ape_math"
import ape_sample "ape:samples/ape_sample"
import app "ape:engine/app"
import gfx "ape:engine/gfx"
import textured_cube_shader "ape:assets/shaders/generated/textured_cube"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
ROTATION_RADIANS_PER_SECOND :: f32(0.5)

TEXTURE_MAGIC :: u32(0x58545041) // "APTX"
TEXTURE_VERSION :: u32(1)
TEXTURE_HEADER_SIZE :: 16

Vertex :: struct {
	position: [3]f32,
	uv: [2]f32,
}

Frame_Uniforms :: struct {
	ape_mvp: ape_math.Mat4,
}

#assert(size_of(Frame_Uniforms) == textured_cube_shader.SIZE_FrameUniforms)
#assert(offset_of(Frame_Uniforms, ape_mvp) == textured_cube_shader.OFFSET_FrameUniforms_ape_mvp)
#assert(u32(size_of(Vertex)) == textured_cube_shader.VERTEX_STRIDE)
#assert(offset_of(Vertex, position) == textured_cube_shader.ATTR_POSITION_OFFSET)
#assert(offset_of(Vertex, uv) == textured_cube_shader.ATTR_TEXCOORD_OFFSET)

Texture_Asset :: struct {
	bytes: []u8,
	pixels: []u8,
	width: i32,
	height: i32,
}

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		return
	}
	defer app.shutdown()

	window, ok := app.create_window({
		width = 1280,
		height = 720,
		title = "Ape D3D11 Textured Cube",
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
		label = "ape d3d11 textured cube",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.shutdown(&ctx)

	vertices := [?]Vertex {
		{position = {-1, -1, -1}, uv = {0, 1}},
		{position = {-1,  1, -1}, uv = {0, 0}},
		{position = { 1,  1, -1}, uv = {1, 0}},
		{position = { 1, -1, -1}, uv = {1, 1}},

		{position = { 1, -1,  1}, uv = {0, 1}},
		{position = { 1,  1,  1}, uv = {0, 0}},
		{position = {-1,  1,  1}, uv = {1, 0}},
		{position = {-1, -1,  1}, uv = {1, 1}},

		{position = {-1,  1, -1}, uv = {0, 1}},
		{position = {-1,  1,  1}, uv = {0, 0}},
		{position = { 1,  1,  1}, uv = {1, 0}},
		{position = { 1,  1, -1}, uv = {1, 1}},

		{position = {-1, -1,  1}, uv = {0, 1}},
		{position = {-1, -1, -1}, uv = {0, 0}},
		{position = { 1, -1, -1}, uv = {1, 0}},
		{position = { 1, -1,  1}, uv = {1, 1}},

		{position = {-1, -1,  1}, uv = {0, 1}},
		{position = {-1,  1,  1}, uv = {0, 0}},
		{position = {-1,  1, -1}, uv = {1, 0}},
		{position = {-1, -1, -1}, uv = {1, 1}},

		{position = { 1, -1, -1}, uv = {0, 1}},
		{position = { 1,  1, -1}, uv = {0, 0}},
		{position = { 1,  1,  1}, uv = {1, 0}},
		{position = { 1, -1,  1}, uv = {1, 1}},
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
		label = "textured cube vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(vertices[:]),
	})
	if !vertex_buffer_ok {
		fmt.eprintln("vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, vertex_buffer)

	index_buffer, index_buffer_ok := gfx.create_buffer(&ctx, {
		label = "textured cube indices",
		usage = {.Index, .Immutable},
		data = gfx.range(indices[:]),
	})
	if !index_buffer_ok {
		fmt.eprintln("index buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, index_buffer)

	texture_asset, texture_asset_ok := load_texture_asset("build/textures/texture.aptex")
	if !texture_asset_ok {
		fmt.eprintln("failed to load build/textures/texture.aptex; run tools/convert_texture_rgba8.ps1 first")
		return
	}
	defer unload_texture_asset(&texture_asset)

	texture, texture_ok := gfx.create_image(&ctx, {
		label = "jpg converted texture",
		kind = .Image_2D,
		usage = {.Texture, .Immutable},
		width = texture_asset.width,
		height = texture_asset.height,
		mip_count = 1,
		array_count = 1,
		sample_count = 1,
		format = .RGBA8,
		data = gfx.range(texture_asset.pixels),
	})
	if !texture_ok {
		fmt.eprintln("texture creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, texture)

	texture_view, texture_view_ok := gfx.create_view(&ctx, {
		label = "jpg converted texture view",
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
		label = "texture linear sampler",
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

	layout := textured_cube_shader.layout_desc()

	program_desc := ape_sample.Shader_Program_Desc {
		package_path = "build/shaders/textured_cube.ashader",
		shader_label = "textured cube shader",
		pipeline_desc = {
			label = "textured cube pipeline",
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
		shader_name = "textured_cube",
		source_path = "assets/shaders/textured_cube.slang",
		package_path = "build/shaders/textured_cube.ashader",
	}) {
		return
	}
	defer ape_sample.reloadable_shader_program_destroy(&ctx, &program)

	bindings: gfx.Bindings
	bindings.vertex_buffers[0] = {buffer = vertex_buffer, offset = 0}
	bindings.index_buffer = {buffer = index_buffer, offset = 0}
	textured_cube_shader.set_view_ape_texture(&bindings, texture_view)
	textured_cube_shader.set_sampler_ape_sampler(&bindings, sampler)

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

		if !gfx.begin_pass(&ctx, {label = "main textured cube", action = action}) {
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
		if !textured_cube_shader.apply_uniform_FrameUniforms(&ctx, &uniforms) {
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

load_texture_asset :: proc(path: string) -> (Texture_Asset, bool) {
	bytes, ok := os.read_entire_file(path)
	if !ok {
		return {}, false
	}

	if len(bytes) < TEXTURE_HEADER_SIZE {
		delete(bytes)
		return {}, false
	}

	if read_u32(bytes, 0) != TEXTURE_MAGIC || read_u32(bytes, 4) != TEXTURE_VERSION {
		delete(bytes)
		return {}, false
	}

	width := read_u32(bytes, 8)
	height := read_u32(bytes, 12)
	if width == 0 || height == 0 {
		delete(bytes)
		return {}, false
	}

	data_size := int(width) * int(height) * 4
	if len(bytes) < TEXTURE_HEADER_SIZE + data_size {
		delete(bytes)
		return {}, false
	}

	pixels := bytes[TEXTURE_HEADER_SIZE:TEXTURE_HEADER_SIZE + data_size]
	return Texture_Asset {
		bytes = bytes,
		pixels = pixels,
		width = i32(width),
		height = i32(height),
	}, true
}

unload_texture_asset :: proc(asset: ^Texture_Asset) {
	if asset == nil {
		return
	}

	if asset.bytes != nil {
		delete(asset.bytes)
	}
	asset^ = {}
}

read_u32 :: proc(bytes: []u8, offset: int) -> u32 {
	return u32(bytes[offset]) |
	       (u32(bytes[offset + 1]) << 8) |
	       (u32(bytes[offset + 2]) << 16) |
	       (u32(bytes[offset + 3]) << 24)
}
