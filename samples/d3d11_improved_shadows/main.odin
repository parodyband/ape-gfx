package main

import "core:fmt"
import "core:math"
import "core:os"
import ape_math "ape:samples/ape_math"
import ape_sample "ape:samples/ape_sample"
import app "ape:engine/app"
import gfx "ape:engine/gfx"
import improved_shadows_shader "ape:assets/shaders/generated/improved_shadows"
import shadow_depth_shader "ape:assets/shaders/generated/shadow_depth"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
SHADOW_MAP_SIZE :: 1024

TEXTURE_MAGIC :: u32(0x58545041) // "APTX"
TEXTURE_VERSION :: u32(1)
TEXTURE_HEADER_SIZE :: 16

Vec3 :: [3]f32

Scene_Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
}

Object_Uniforms :: struct {
	model:           ape_math.Mat4,
	light_view_proj: ape_math.Mat4,
}

Frame_Uniforms :: struct {
	view_proj:       ape_math.Mat4,
	light_pos:       [4]f32,
	view_pos:        [4]f32,
	shadow_map_size: [4]f32,
}

Texture_Asset :: struct {
	bytes:  []u8,
	pixels: []u8,
	width:  i32,
	height: i32,
}

#assert(size_of(Object_Uniforms) == shadow_depth_shader.SIZE_ObjectUniforms)
#assert(size_of(Object_Uniforms) == improved_shadows_shader.SIZE_ObjectUniforms)
#assert(size_of(Frame_Uniforms) == improved_shadows_shader.SIZE_FrameUniforms)
#assert(offset_of(Scene_Vertex, position) == shadow_depth_shader.ATTR_POSITION_OFFSET)
#assert(u32(size_of(Scene_Vertex)) == improved_shadows_shader.VERTEX_STRIDE)
#assert(offset_of(Scene_Vertex, position) == improved_shadows_shader.ATTR_POSITION_OFFSET)
#assert(offset_of(Scene_Vertex, normal) == improved_shadows_shader.ATTR_NORMAL_OFFSET)
#assert(offset_of(Scene_Vertex, uv) == improved_shadows_shader.ATTR_TEXCOORD_OFFSET)

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		return
	}
	defer app.shutdown()

	window, ok := app.create_window({
		width = 1280,
		height = 720,
		title = "Ape D3D11 Improved Shadows",
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
		label = "ape d3d11 improved shadows",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.shutdown(&ctx)

	shadow_image, shadow_image_ok := gfx.create_image(&ctx, {
		label = "improved shadows depth image",
		kind = .Image_2D,
		usage = {.Texture, .Depth_Stencil_Attachment},
		width = SHADOW_MAP_SIZE,
		height = SHADOW_MAP_SIZE,
		mip_count = 1,
		array_count = 1,
		sample_count = 1,
		format = .D32F,
	})
	if !shadow_image_ok {
		fmt.eprintln("shadow image creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, shadow_image)

	shadow_depth_view, shadow_depth_view_ok := gfx.create_view(&ctx, {
		label = "improved shadows depth attachment",
		depth_stencil_attachment = {
			image = shadow_image,
			format = .D32F,
		},
	})
	if !shadow_depth_view_ok {
		fmt.eprintln("shadow depth view creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, shadow_depth_view)

	shadow_sample_view, shadow_sample_view_ok := gfx.create_view(&ctx, {
		label = "improved shadows sampled depth",
		texture = {
			image = shadow_image,
			format = .D32F,
		},
	})
	if !shadow_sample_view_ok {
		fmt.eprintln("shadow sampled view creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, shadow_sample_view)

	texture_asset, texture_asset_ok := load_texture_asset("build/textures/texture.aptex")
	if !texture_asset_ok {
		fmt.eprintln("failed to load build/textures/texture.aptex; run tools/convert_texture_rgba8.ps1 first")
		return
	}
	defer unload_texture_asset(&texture_asset)

	diffuse_texture, diffuse_texture_ok := gfx.create_image(&ctx, {
		label = "improved shadows diffuse texture",
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
	if !diffuse_texture_ok {
		fmt.eprintln("diffuse texture creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, diffuse_texture)

	diffuse_texture_view, diffuse_texture_view_ok := gfx.create_view(&ctx, {
		label = "improved shadows diffuse texture view",
		texture = {
			image = diffuse_texture,
			format = .RGBA8,
		},
	})
	if !diffuse_texture_view_ok {
		fmt.eprintln("diffuse texture view creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, diffuse_texture_view)

	diffuse_sampler, diffuse_sampler_ok := gfx.create_sampler(&ctx, {
		label = "improved shadows diffuse sampler",
		min_filter = .Linear,
		mag_filter = .Linear,
		mip_filter = .Nearest,
		wrap_u = .Repeat,
		wrap_v = .Repeat,
		wrap_w = .Repeat,
	})
	if !diffuse_sampler_ok {
		fmt.eprintln("diffuse sampler creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, diffuse_sampler)

	shadow_sampler, shadow_sampler_ok := gfx.create_sampler(&ctx, {
		label = "improved shadows nearest shadow sampler",
		min_filter = .Nearest,
		mag_filter = .Nearest,
		mip_filter = .Nearest,
		wrap_u = .Clamp_To_Edge,
		wrap_v = .Clamp_To_Edge,
		wrap_w = .Clamp_To_Edge,
	})
	if !shadow_sampler_ok {
		fmt.eprintln("shadow sampler creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, shadow_sampler)

	plane_vertices, plane_indices := make_plane_mesh()
	cube_vertices, cube_indices := make_cube_mesh()

	plane_vertex_buffer, plane_vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "improved shadows plane vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(plane_vertices[:]),
	})
	if !plane_vertex_buffer_ok {
		fmt.eprintln("plane vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, plane_vertex_buffer)

	plane_index_buffer, plane_index_buffer_ok := gfx.create_buffer(&ctx, {
		label = "improved shadows plane indices",
		usage = {.Index, .Immutable},
		data = gfx.range(plane_indices[:]),
	})
	if !plane_index_buffer_ok {
		fmt.eprintln("plane index buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, plane_index_buffer)

	cube_vertex_buffer, cube_vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "improved shadows cube vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(cube_vertices[:]),
	})
	if !cube_vertex_buffer_ok {
		fmt.eprintln("cube vertex buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, cube_vertex_buffer)

	cube_index_buffer, cube_index_buffer_ok := gfx.create_buffer(&ctx, {
		label = "improved shadows cube indices",
		usage = {.Index, .Immutable},
		data = gfx.range(cube_indices[:]),
	})
	if !cube_index_buffer_ok {
		fmt.eprintln("cube index buffer creation failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.destroy(&ctx, cube_index_buffer)

	shadow_depth_layout := shadow_depth_shader.layout_desc()
	shadow_depth_layout.buffers[0].stride = u32(size_of(Scene_Vertex))

	shadow_depth_program_desc := ape_sample.Shader_Program_Desc {
		package_path = "build/shaders/shadow_depth.ashader",
		shader_label = "improved shadows depth shader",
		pipeline_desc = {
			label = "improved shadows depth pipeline",
			primitive_type = .Triangles,
			index_type = .Uint16,
			layout = shadow_depth_layout,
			depth_only = true,
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
	shadow_depth_program: ape_sample.Reloadable_Shader_Program
	if !ape_sample.reloadable_shader_program_init(&ctx, &shadow_depth_program, shadow_depth_program_desc, {
		shader_name = "shadow_depth",
		source_path = "assets/shaders/shadow_depth.slang",
		package_path = "build/shaders/shadow_depth.ashader",
	}) {
		return
	}
	defer ape_sample.reloadable_shader_program_destroy(&ctx, &shadow_depth_program)

	improved_shadows_program_desc := ape_sample.Shader_Program_Desc {
		package_path = "build/shaders/improved_shadows.ashader",
		shader_label = "improved shadows shader",
		pipeline_desc = {
			label = "improved shadows pipeline",
			primitive_type = .Triangles,
			index_type = .Uint16,
			layout = improved_shadows_shader.layout_desc(),
			color_formats = {0 = .BGRA8},
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
	improved_shadows_program: ape_sample.Reloadable_Shader_Program
	if !ape_sample.reloadable_shader_program_init(&ctx, &improved_shadows_program, improved_shadows_program_desc, {
		shader_name = "improved_shadows",
		source_path = "assets/shaders/improved_shadows.slang",
		package_path = "build/shaders/improved_shadows.ashader",
	}) {
		return
	}
	defer ape_sample.reloadable_shader_program_destroy(&ctx, &improved_shadows_program)

	depth_plane_bindings: gfx.Bindings
	depth_plane_bindings.vertex_buffers[0] = {buffer = plane_vertex_buffer, offset = 0}
	depth_plane_bindings.index_buffer = {buffer = plane_index_buffer, offset = 0}

	depth_cube_bindings: gfx.Bindings
	depth_cube_bindings.vertex_buffers[0] = {buffer = cube_vertex_buffer, offset = 0}
	depth_cube_bindings.index_buffer = {buffer = cube_index_buffer, offset = 0}

	lit_plane_bindings := depth_plane_bindings
	improved_shadows_shader.set_view_diffuse_texture(&lit_plane_bindings, diffuse_texture_view)
	improved_shadows_shader.set_view_shadow_map(&lit_plane_bindings, shadow_sample_view)
	improved_shadows_shader.set_sampler_diffuse_sampler(&lit_plane_bindings, diffuse_sampler)
	improved_shadows_shader.set_sampler_shadow_sampler(&lit_plane_bindings, shadow_sampler)

	lit_cube_bindings := depth_cube_bindings
	improved_shadows_shader.set_view_diffuse_texture(&lit_cube_bindings, diffuse_texture_view)
	improved_shadows_shader.set_view_shadow_map(&lit_cube_bindings, shadow_sample_view)
	improved_shadows_shader.set_sampler_diffuse_sampler(&lit_cube_bindings, diffuse_sampler)
	improved_shadows_shader.set_sampler_shadow_sampler(&lit_cube_bindings, shadow_sampler)

	light_pos := Vec3{-2, 4, -1}
	camera_pos := Vec3{0, 3.2, -7.2}
	light_projection := orthographic_lh(-10, 10, -10, 10, 1, 7.5)
	light_view := look_at_lh(light_pos, Vec3{0, 0, 0}, Vec3{0, 1, 0})
	light_view_proj := ape_math.mul(light_projection, light_view)
	cube_models := make_cube_models()

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

		ape_sample.reloadable_shader_program_poll(&ctx, &shadow_depth_program)
		ape_sample.reloadable_shader_program_poll(&ctx, &improved_shadows_program)

		shadow_action := gfx.default_pass_action()
		shadow_action.depth.clear_value = 1

		if !gfx.begin_pass(&ctx, {
			label = "improved shadows shadow map pass",
			depth_stencil_attachment = shadow_depth_view,
			action = shadow_action,
		}) {
			fmt.eprintln("shadow begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, ape_sample.reloadable_shader_program_pipeline(&shadow_depth_program)) {
			fmt.eprintln("shadow apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !draw_shadow_scene(&ctx, depth_plane_bindings, depth_cube_bindings, light_view_proj, cube_models[:], i32(len(plane_indices)), i32(len(cube_indices))) {
			return
		}
		if !gfx.end_pass(&ctx) {
			fmt.eprintln("shadow end_pass failed: ", gfx.last_error(&ctx))
			return
		}

		view := look_at_lh(camera_pos, Vec3{0, 0.45, 0.35}, Vec3{0, 1, 0})
		projection := ape_math.cube_projection(render_width, render_height)
		frame_uniforms := Frame_Uniforms {
			view_proj = ape_math.mul(projection, view),
			light_pos = {light_pos[0], light_pos[1], light_pos[2], 0},
			view_pos = {camera_pos[0], camera_pos[1], camera_pos[2], 0},
			shadow_map_size = {SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, 0, 0},
		}

		swapchain_action := gfx.default_pass_action()
		swapchain_action.colors[0].clear_value = gfx.Color{r = 0.018, g = 0.020, b = 0.026, a = 1}
		swapchain_action.depth.clear_value = 1

		if !gfx.begin_pass(&ctx, {label = "improved shadows lit pass", action = swapchain_action}) {
			fmt.eprintln("lit begin_pass failed: ", gfx.last_error(&ctx))
			return
		}
		if !gfx.apply_pipeline(&ctx, ape_sample.reloadable_shader_program_pipeline(&improved_shadows_program)) {
			fmt.eprintln("lit apply_pipeline failed: ", gfx.last_error(&ctx))
			return
		}
		if !improved_shadows_shader.apply_uniform_FrameUniforms(&ctx, &frame_uniforms) {
			fmt.eprintln("lit frame uniform upload failed: ", gfx.last_error(&ctx))
			return
		}
		if !draw_lit_scene(&ctx, lit_plane_bindings, lit_cube_bindings, light_view_proj, cube_models[:], i32(len(plane_indices)), i32(len(cube_indices))) {
			return
		}
		if !gfx.end_pass(&ctx) {
			fmt.eprintln("lit end_pass failed: ", gfx.last_error(&ctx))
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

draw_shadow_scene :: proc(
	ctx: ^gfx.Context,
	plane_bindings: gfx.Bindings,
	cube_bindings: gfx.Bindings,
	light_view_proj: ape_math.Mat4,
	cube_models: []ape_math.Mat4,
	plane_index_count: i32,
	cube_index_count: i32,
) -> bool {
	if !gfx.apply_bindings(ctx, plane_bindings) {
		fmt.eprintln("shadow plane apply_bindings failed: ", gfx.last_error(ctx))
		return false
	}

	plane_uniforms := Object_Uniforms {
		model = mat4_identity(),
		light_view_proj = light_view_proj,
	}
	if !shadow_depth_shader.apply_uniform_ObjectUniforms(ctx, &plane_uniforms) {
		fmt.eprintln("shadow plane uniform upload failed: ", gfx.last_error(ctx))
		return false
	}
	if !gfx.draw(ctx, 0, plane_index_count) {
		fmt.eprintln("shadow plane draw failed: ", gfx.last_error(ctx))
		return false
	}

	if !gfx.apply_bindings(ctx, cube_bindings) {
		fmt.eprintln("shadow cube apply_bindings failed: ", gfx.last_error(ctx))
		return false
	}
	for model in cube_models {
		cube_uniforms := Object_Uniforms {
			model = model,
			light_view_proj = light_view_proj,
		}
		if !shadow_depth_shader.apply_uniform_ObjectUniforms(ctx, &cube_uniforms) {
			fmt.eprintln("shadow cube uniform upload failed: ", gfx.last_error(ctx))
			return false
		}
		if !gfx.draw(ctx, 0, cube_index_count) {
			fmt.eprintln("shadow cube draw failed: ", gfx.last_error(ctx))
			return false
		}
	}

	return true
}

draw_lit_scene :: proc(
	ctx: ^gfx.Context,
	plane_bindings: gfx.Bindings,
	cube_bindings: gfx.Bindings,
	light_view_proj: ape_math.Mat4,
	cube_models: []ape_math.Mat4,
	plane_index_count: i32,
	cube_index_count: i32,
) -> bool {
	if !gfx.apply_bindings(ctx, plane_bindings) {
		fmt.eprintln("lit plane apply_bindings failed: ", gfx.last_error(ctx))
		return false
	}

	plane_uniforms := Object_Uniforms {
		model = mat4_identity(),
		light_view_proj = light_view_proj,
	}
	if !improved_shadows_shader.apply_uniform_ObjectUniforms(ctx, &plane_uniforms) {
		fmt.eprintln("lit plane object uniform upload failed: ", gfx.last_error(ctx))
		return false
	}
	if !gfx.draw(ctx, 0, plane_index_count) {
		fmt.eprintln("lit plane draw failed: ", gfx.last_error(ctx))
		return false
	}

	if !gfx.apply_bindings(ctx, cube_bindings) {
		fmt.eprintln("lit cube apply_bindings failed: ", gfx.last_error(ctx))
		return false
	}
	for model in cube_models {
		cube_uniforms := Object_Uniforms {
			model = model,
			light_view_proj = light_view_proj,
		}
		if !improved_shadows_shader.apply_uniform_ObjectUniforms(ctx, &cube_uniforms) {
			fmt.eprintln("lit cube object uniform upload failed: ", gfx.last_error(ctx))
			return false
		}
		if !gfx.draw(ctx, 0, cube_index_count) {
			fmt.eprintln("lit cube draw failed: ", gfx.last_error(ctx))
			return false
		}
	}

	return true
}

make_cube_models :: proc() -> [3]ape_math.Mat4 {
	return [3]ape_math.Mat4 {
		ape_math.mul(ape_math.translation(0, 1.5, 0), scale(0.5, 0.5, 0.5)),
		ape_math.mul(ape_math.translation(2, 0, 1), scale(0.5, 0.5, 0.5)),
		ape_math.mul(
			ape_math.mul(
				ape_math.translation(-1, 0, 2),
				ape_math.mul(ape_math.rotation_y(math.to_radians_f32(60)), ape_math.rotation_x(math.to_radians_f32(35))),
			),
			scale(0.25, 0.25, 0.25),
		),
	}
}

make_plane_mesh :: proc() -> ([4]Scene_Vertex, [6]u16) {
	vertices := [4]Scene_Vertex {
		{position = { 25, -0.5,  25}, normal = {0, 1, 0}, uv = {16,  0}},
		{position = {-25, -0.5,  25}, normal = {0, 1, 0}, uv = { 0,  0}},
		{position = {-25, -0.5, -25}, normal = {0, 1, 0}, uv = { 0, 16}},
		{position = { 25, -0.5, -25}, normal = {0, 1, 0}, uv = {16, 16}},
	}
	indices := [6]u16{0, 1, 2, 0, 2, 3}
	return vertices, indices
}

make_cube_mesh :: proc() -> ([24]Scene_Vertex, [36]u16) {
	vertices := [24]Scene_Vertex {
		{position = {-1, -1, -1}, normal = { 0,  0, -1}, uv = {0, 1}},
		{position = {-1,  1, -1}, normal = { 0,  0, -1}, uv = {0, 0}},
		{position = { 1,  1, -1}, normal = { 0,  0, -1}, uv = {1, 0}},
		{position = { 1, -1, -1}, normal = { 0,  0, -1}, uv = {1, 1}},

		{position = { 1, -1,  1}, normal = { 0,  0,  1}, uv = {0, 1}},
		{position = { 1,  1,  1}, normal = { 0,  0,  1}, uv = {0, 0}},
		{position = {-1,  1,  1}, normal = { 0,  0,  1}, uv = {1, 0}},
		{position = {-1, -1,  1}, normal = { 0,  0,  1}, uv = {1, 1}},

		{position = {-1,  1, -1}, normal = { 0,  1,  0}, uv = {0, 1}},
		{position = {-1,  1,  1}, normal = { 0,  1,  0}, uv = {0, 0}},
		{position = { 1,  1,  1}, normal = { 0,  1,  0}, uv = {1, 0}},
		{position = { 1,  1, -1}, normal = { 0,  1,  0}, uv = {1, 1}},

		{position = {-1, -1,  1}, normal = { 0, -1,  0}, uv = {0, 1}},
		{position = {-1, -1, -1}, normal = { 0, -1,  0}, uv = {0, 0}},
		{position = { 1, -1, -1}, normal = { 0, -1,  0}, uv = {1, 0}},
		{position = { 1, -1,  1}, normal = { 0, -1,  0}, uv = {1, 1}},

		{position = {-1, -1,  1}, normal = {-1,  0,  0}, uv = {0, 1}},
		{position = {-1,  1,  1}, normal = {-1,  0,  0}, uv = {0, 0}},
		{position = {-1,  1, -1}, normal = {-1,  0,  0}, uv = {1, 0}},
		{position = {-1, -1, -1}, normal = {-1,  0,  0}, uv = {1, 1}},

		{position = { 1, -1, -1}, normal = { 1,  0,  0}, uv = {0, 1}},
		{position = { 1,  1, -1}, normal = { 1,  0,  0}, uv = {0, 0}},
		{position = { 1,  1,  1}, normal = { 1,  0,  0}, uv = {1, 0}},
		{position = { 1, -1,  1}, normal = { 1,  0,  0}, uv = {1, 1}},
	}
	indices := [36]u16 {
		 0,  1,  2,  0,  2,  3,
		 4,  5,  6,  4,  6,  7,
		 8,  9, 10,  8, 10, 11,
		12, 13, 14, 12, 14, 15,
		16, 17, 18, 16, 18, 19,
		20, 21, 22, 20, 22, 23,
	}
	return vertices, indices
}

mat4_identity :: proc() -> ape_math.Mat4 {
	return ape_math.Mat4 {
		{1, 0, 0, 0},
		{0, 1, 0, 0},
		{0, 0, 1, 0},
		{0, 0, 0, 1},
	}
}

scale :: proc(x, y, z: f32) -> ape_math.Mat4 {
	return ape_math.Mat4 {
		{x, 0, 0, 0},
		{0, y, 0, 0},
		{0, 0, z, 0},
		{0, 0, 0, 1},
	}
}

orthographic_lh :: proc(left, right, bottom, top, near_z, far_z: f32) -> ape_math.Mat4 {
	return ape_math.Mat4 {
		{2 / (right - left), 0, 0, -(right + left) / (right - left)},
		{0, 2 / (top - bottom), 0, -(top + bottom) / (top - bottom)},
		{0, 0, 1 / (far_z - near_z), -near_z / (far_z - near_z)},
		{0, 0, 0, 1},
	}
}

look_at_lh :: proc(eye, target, up: Vec3) -> ape_math.Mat4 {
	z_axis := normalize3(sub3(target, eye))
	x_axis := normalize3(cross3(up, z_axis))
	y_axis := cross3(z_axis, x_axis)

	return ape_math.Mat4 {
		{x_axis[0], x_axis[1], x_axis[2], -dot3(x_axis, eye)},
		{y_axis[0], y_axis[1], y_axis[2], -dot3(y_axis, eye)},
		{z_axis[0], z_axis[1], z_axis[2], -dot3(z_axis, eye)},
		{0, 0, 0, 1},
	}
}

sub3 :: proc(a, b: Vec3) -> Vec3 {
	return Vec3{a[0] - b[0], a[1] - b[1], a[2] - b[2]}
}

dot3 :: proc(a, b: Vec3) -> f32 {
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

cross3 :: proc(a, b: Vec3) -> Vec3 {
	return Vec3 {
		a[1] * b[2] - a[2] * b[1],
		a[2] * b[0] - a[0] * b[2],
		a[0] * b[1] - a[1] * b[0],
	}
}

normalize3 :: proc(v: Vec3) -> Vec3 {
	length_sq := dot3(v, v)
	if length_sq <= 0 {
		return Vec3{}
	}

	inv_length := 1 / math.sqrt_f32(length_sq)
	return Vec3{v[0] * inv_length, v[1] * inv_length, v[2] * inv_length}
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
