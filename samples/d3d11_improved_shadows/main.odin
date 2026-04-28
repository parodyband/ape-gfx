package main

import "core:fmt"
import "core:math"
import ape_math "ape:samples/ape_math"
import ape_sample "ape:samples/ape_sample"
import app "ape:engine/app"
import gfx "ape:engine/gfx"
import improved_shadows_shader "ape:assets/shaders/generated/improved_shadows"
import shadow_depth_shader "ape:assets/shaders/generated/shadow_depth"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
SHADOW_MAP_SIZE :: 1024

Scene_Pass :: enum {
	Shadow,
	Lit,
}

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
		width = 800,
		height = 600,
		title = "Improved Shadows (Ape GFX)",
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

	light_pos := ape_math.Vec3{-2, 4, -1}
	camera_pos := ape_math.Vec3{0, 3.2, -7.2}
	light_projection := ape_math.orthographic_lh(-10, 10, -10, 10, 1, 7.5)
	light_view := ape_math.look_at_lh(light_pos, ape_math.Vec3{0, 0, 0}, ape_math.Vec3{0, 1, 0})
	light_view_proj := ape_math.mul(light_projection, light_view)
	cube_models := [?]ape_math.Mat4 {
		ape_math.mul(ape_math.translation(0, 1.5, 0), ape_math.scale(0.5, 0.5, 0.5)),
		ape_math.mul(ape_math.translation(2, 0, 1), ape_math.scale(0.5, 0.5, 0.5)),
		ape_math.mul(
			ape_math.mul(
				ape_math.translation(-1, 0, 2),
				ape_math.rotation_axis(math.to_radians_f32(60), ape_math.Vec3{1, 0, 1}),
			),
			ape_math.scale(0.25, 0.25, 0.25),
		),
	}

	cube_vertices := [?]Scene_Vertex {
		{position = {-1, -1, -1}, normal = { 0,  0, -1}, uv = {0, 0}},
		{position = { 1,  1, -1}, normal = { 0,  0, -1}, uv = {1, 1}},
		{position = { 1, -1, -1}, normal = { 0,  0, -1}, uv = {1, 0}},
		{position = { 1,  1, -1}, normal = { 0,  0, -1}, uv = {1, 1}},
		{position = {-1, -1, -1}, normal = { 0,  0, -1}, uv = {0, 0}},
		{position = {-1,  1, -1}, normal = { 0,  0, -1}, uv = {0, 1}},
		{position = {-1, -1,  1}, normal = { 0,  0,  1}, uv = {0, 0}},
		{position = { 1, -1,  1}, normal = { 0,  0,  1}, uv = {1, 0}},
		{position = { 1,  1,  1}, normal = { 0,  0,  1}, uv = {1, 1}},
		{position = { 1,  1,  1}, normal = { 0,  0,  1}, uv = {1, 1}},
		{position = {-1,  1,  1}, normal = { 0,  0,  1}, uv = {0, 1}},
		{position = {-1, -1,  1}, normal = { 0,  0,  1}, uv = {0, 0}},
		{position = {-1,  1,  1}, normal = {-1,  0,  0}, uv = {1, 0}},
		{position = {-1,  1, -1}, normal = {-1,  0,  0}, uv = {1, 1}},
		{position = {-1, -1, -1}, normal = {-1,  0,  0}, uv = {0, 1}},
		{position = {-1, -1, -1}, normal = {-1,  0,  0}, uv = {0, 1}},
		{position = {-1, -1,  1}, normal = {-1,  0,  0}, uv = {0, 0}},
		{position = {-1,  1,  1}, normal = {-1,  0,  0}, uv = {1, 0}},
		{position = { 1,  1,  1}, normal = { 1,  0,  0}, uv = {1, 0}},
		{position = { 1, -1, -1}, normal = { 1,  0,  0}, uv = {0, 1}},
		{position = { 1,  1, -1}, normal = { 1,  0,  0}, uv = {1, 1}},
		{position = { 1, -1, -1}, normal = { 1,  0,  0}, uv = {0, 1}},
		{position = { 1,  1,  1}, normal = { 1,  0,  0}, uv = {1, 0}},
		{position = { 1, -1,  1}, normal = { 1,  0,  0}, uv = {0, 0}},
		{position = {-1, -1, -1}, normal = { 0, -1,  0}, uv = {0, 1}},
		{position = { 1, -1, -1}, normal = { 0, -1,  0}, uv = {1, 1}},
		{position = { 1, -1,  1}, normal = { 0, -1,  0}, uv = {1, 0}},
		{position = { 1, -1,  1}, normal = { 0, -1,  0}, uv = {1, 0}},
		{position = {-1, -1,  1}, normal = { 0, -1,  0}, uv = {0, 0}},
		{position = {-1, -1, -1}, normal = { 0, -1,  0}, uv = {0, 1}},
		{position = {-1,  1, -1}, normal = { 0,  1,  0}, uv = {0, 1}},
		{position = { 1,  1,  1}, normal = { 0,  1,  0}, uv = {1, 0}},
		{position = { 1,  1, -1}, normal = { 0,  1,  0}, uv = {1, 1}},
		{position = { 1,  1,  1}, normal = { 0,  1,  0}, uv = {1, 0}},
		{position = {-1,  1, -1}, normal = { 0,  1,  0}, uv = {0, 1}},
		{position = {-1,  1,  1}, normal = { 0,  1,  0}, uv = {0, 0}},
	}
	plane_vertices := [?]Scene_Vertex {
		{position = { 25, -0.5,  25}, normal = {0, 1, 0}, uv = {25,  0}},
		{position = {-25, -0.5,  25}, normal = {0, 1, 0}, uv = { 0,  0}},
		{position = {-25, -0.5, -25}, normal = {0, 1, 0}, uv = { 0, 25}},
		{position = { 25, -0.5,  25}, normal = {0, 1, 0}, uv = {25,  0}},
		{position = {-25, -0.5, -25}, normal = {0, 1, 0}, uv = { 0, 25}},
		{position = { 25, -0.5, -25}, normal = {0, 1, 0}, uv = {25, 25}},
	}

	shadow_image, shadow_image_ok := gfx.create_image(&ctx, {
		label = "shadow map",
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
		log_gfx_error(&ctx, "shadow image creation failed")
		return
	}
	defer gfx.destroy(&ctx, shadow_image)

	shadow_depth_view, shadow_depth_view_ok := gfx.create_view(&ctx, {
		label = "shadow depth attachment",
		depth_stencil_attachment = {image = shadow_image, format = .D32F},
	})
	if !shadow_depth_view_ok {
		log_gfx_error(&ctx, "shadow depth view creation failed")
		return
	}
	defer gfx.destroy(&ctx, shadow_depth_view)

	shadow_sample_view, shadow_sample_view_ok := gfx.create_view(&ctx, {
		label = "shadow sampled depth",
		texture = {image = shadow_image, format = .D32F},
	})
	if !shadow_sample_view_ok {
		log_gfx_error(&ctx, "shadow sampled view creation failed")
		return
	}
	defer gfx.destroy(&ctx, shadow_sample_view)

	texture_asset, texture_asset_ok := ape_sample.load_texture_asset("build/textures/texture.aptex")
	if !texture_asset_ok {
		fmt.eprintln("failed to load build/textures/texture.aptex; run tools/convert_texture_rgba8.ps1 first")
		return
	}
	defer ape_sample.unload_texture_asset(&texture_asset)

	diffuse_texture, diffuse_texture_ok := gfx.create_image(&ctx, {
		label = "diffuse texture",
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
		log_gfx_error(&ctx, "diffuse texture creation failed")
		return
	}
	defer gfx.destroy(&ctx, diffuse_texture)

	diffuse_view, diffuse_view_ok := gfx.create_view(&ctx, {
		label = "diffuse texture view",
		texture = {image = diffuse_texture, format = .RGBA8},
	})
	if !diffuse_view_ok {
		log_gfx_error(&ctx, "diffuse texture view creation failed")
		return
	}
	defer gfx.destroy(&ctx, diffuse_view)

	diffuse_sampler, diffuse_sampler_ok := gfx.create_sampler(&ctx, {
		label = "diffuse sampler",
		min_filter = .Linear,
		mag_filter = .Linear,
		mip_filter = .Nearest,
		wrap_u = .Repeat,
		wrap_v = .Repeat,
		wrap_w = .Repeat,
	})
	if !diffuse_sampler_ok {
		log_gfx_error(&ctx, "diffuse sampler creation failed")
		return
	}
	defer gfx.destroy(&ctx, diffuse_sampler)

	shadow_sampler, shadow_sampler_ok := gfx.create_sampler(&ctx, {
		label = "shadow sampler",
		min_filter = .Nearest,
		mag_filter = .Nearest,
		mip_filter = .Nearest,
		wrap_u = .Clamp_To_Edge,
		wrap_v = .Clamp_To_Edge,
		wrap_w = .Clamp_To_Edge,
	})
	if !shadow_sampler_ok {
		log_gfx_error(&ctx, "shadow sampler creation failed")
		return
	}
	defer gfx.destroy(&ctx, shadow_sampler)

	cube_buffer, cube_buffer_ok := gfx.create_buffer(&ctx, {
		label = "cube vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(cube_vertices[:]),
	})
	if !cube_buffer_ok {
		log_gfx_error(&ctx, "cube vertex buffer creation failed")
		return
	}
	defer gfx.destroy(&ctx, cube_buffer)

	plane_buffer, plane_buffer_ok := gfx.create_buffer(&ctx, {
		label = "plane vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(plane_vertices[:]),
	})
	if !plane_buffer_ok {
		log_gfx_error(&ctx, "plane vertex buffer creation failed")
		return
	}
	defer gfx.destroy(&ctx, plane_buffer)

	depth_layout := shadow_depth_shader.layout_desc()
	depth_layout.buffers[0].stride = u32(size_of(Scene_Vertex))
	depth_program, depth_program_ok := ape_sample.shader_program_load(&ctx, {
		package_path = "build/shaders/shadow_depth.ashader",
		shader_label = "shadow depth shader",
		pipeline_desc = {
			label = "shadow depth pipeline",
			primitive_type = .Triangles,
			layout = depth_layout,
			depth_only = true,
			depth = {format = .D32F, enabled = true, write_enabled = true, compare = .Less_Equal},
			raster = {fill_mode = .Solid, cull_mode = .None, winding = .Clockwise},
		},
	})
	if !depth_program_ok {
		return
	}
	defer ape_sample.shader_program_destroy(&ctx, &depth_program)

	shadows_program, shadows_program_ok := ape_sample.shader_program_load(&ctx, {
		package_path = "build/shaders/improved_shadows.ashader",
		shader_label = "improved shadows shader",
		pipeline_desc = {
			label = "improved shadows pipeline",
			primitive_type = .Triangles,
			layout = improved_shadows_shader.layout_desc(),
			color_formats = {0 = .BGRA8},
			depth = {format = .D32F, enabled = true, write_enabled = true, compare = .Less_Equal},
			raster = {fill_mode = .Solid, cull_mode = .None, winding = .Clockwise},
		},
	})
	if !shadows_program_ok {
		return
	}
	defer ape_sample.shader_program_destroy(&ctx, &shadows_program)

	depth_cube_bindings: gfx.Bindings
	depth_cube_bindings.vertex_buffers[0] = {buffer = cube_buffer}
	depth_plane_bindings: gfx.Bindings
	depth_plane_bindings.vertex_buffers[0] = {buffer = plane_buffer}

	shadows_cube_bindings := depth_cube_bindings
	improved_shadows_shader.set_view_diffuse_texture(&shadows_cube_bindings, diffuse_view)
	improved_shadows_shader.set_view_shadow_map(&shadows_cube_bindings, shadow_sample_view)
	improved_shadows_shader.set_sampler_diffuse_sampler(&shadows_cube_bindings, diffuse_sampler)
	improved_shadows_shader.set_sampler_shadow_sampler(&shadows_cube_bindings, shadow_sampler)

	shadows_plane_bindings := depth_plane_bindings
	improved_shadows_shader.set_view_diffuse_texture(&shadows_plane_bindings, diffuse_view)
	improved_shadows_shader.set_view_shadow_map(&shadows_plane_bindings, shadow_sample_view)
	improved_shadows_shader.set_sampler_diffuse_sampler(&shadows_plane_bindings, diffuse_sampler)
	improved_shadows_shader.set_sampler_shadow_sampler(&shadows_plane_bindings, shadow_sampler)

	render_width := fb_width
	render_height := fb_height
	frame := 0
	for !app.should_close(&window) {
		app.poll_events()

		resize, resize_ok := ape_sample.resize_swapchain(&ctx, &window, &render_width, &render_height)
		if !resize_ok {
			log_gfx_error(&ctx, "resize failed")
			return
		}
		if !resize.active {
			continue
		}

		shadow_action := gfx.default_pass_action()
		shadow_action.depth.clear_value = 1
		if !gfx.begin_pass(&ctx, {label = "shadow map pass", depth_stencil_attachment = shadow_depth_view, action = shadow_action}) {
			log_gfx_error(&ctx, "shadow begin_pass failed")
			return
		}
		if !gfx.apply_pipeline(&ctx, depth_program.pipeline) {
			log_gfx_error(&ctx, "shadow apply_pipeline failed")
			return
		}
		if !draw_scene(&ctx, .Shadow, depth_plane_bindings, depth_cube_bindings, light_view_proj, cube_models[:], i32(len(plane_vertices)), i32(len(cube_vertices))) {
			return
		}
		if !gfx.end_pass(&ctx) {
			log_gfx_error(&ctx, "shadow end_pass failed")
			return
		}

		view := ape_math.look_at_lh(camera_pos, ape_math.Vec3{0, 0.45, 0.35}, ape_math.Vec3{0, 1, 0})
		projection := ape_math.cube_projection(render_width, render_height)
		frame_uniforms := Frame_Uniforms {
			view_proj = ape_math.mul(projection, view),
			light_pos = {light_pos[0], light_pos[1], light_pos[2], 0},
			view_pos = {camera_pos[0], camera_pos[1], camera_pos[2], 0},
			shadow_map_size = {SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, 0, 0},
		}

		pass_action := gfx.default_pass_action()
		pass_action.colors[0].clear_value = gfx.Color{r = 0.1, g = 0.1, b = 0.1, a = 1}
		pass_action.depth.clear_value = 1
		if !gfx.begin_pass(&ctx, {label = "shadows pass", action = pass_action}) {
			log_gfx_error(&ctx, "shadows begin_pass failed")
			return
		}
		if !gfx.apply_pipeline(&ctx, shadows_program.pipeline) {
			log_gfx_error(&ctx, "shadows apply_pipeline failed")
			return
		}
		if !improved_shadows_shader.apply_uniform_FrameUniforms(&ctx, &frame_uniforms) {
			log_gfx_error(&ctx, "shadows frame uniform upload failed")
			return
		}
		if !draw_scene(&ctx, .Lit, shadows_plane_bindings, shadows_cube_bindings, light_view_proj, cube_models[:], i32(len(plane_vertices)), i32(len(cube_vertices))) {
			return
		}
		if !gfx.end_pass(&ctx) {
			log_gfx_error(&ctx, "shadows end_pass failed")
			return
		}
		if !gfx.commit(&ctx) {
			log_gfx_error(&ctx, "commit failed")
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

draw_scene :: proc(
	ctx: ^gfx.Context,
	scene_pass: Scene_Pass,
	plane_bindings: gfx.Bindings,
	cube_bindings: gfx.Bindings,
	light_view_proj: ape_math.Mat4,
	cube_models: []ape_math.Mat4,
	plane_vertex_count: i32,
	cube_vertex_count: i32,
) -> bool {
	if !gfx.apply_bindings(ctx, plane_bindings) {
		return fail_gfx(ctx, "plane apply_bindings failed")
	}
	if !apply_object_uniforms(ctx, scene_pass, ape_math.identity(), light_view_proj) {
		return fail_gfx(ctx, "plane uniform upload failed")
	}
	if !gfx.draw(ctx, 0, plane_vertex_count) {
		return fail_gfx(ctx, "plane draw failed")
	}

	if !gfx.apply_bindings(ctx, cube_bindings) {
		return fail_gfx(ctx, "cube apply_bindings failed")
	}
	for model in cube_models {
		if !apply_object_uniforms(ctx, scene_pass, model, light_view_proj) {
			return fail_gfx(ctx, "cube uniform upload failed")
		}
		if !gfx.draw(ctx, 0, cube_vertex_count) {
			return fail_gfx(ctx, "cube draw failed")
		}
	}
	return true
}

apply_object_uniforms :: proc(ctx: ^gfx.Context, scene_pass: Scene_Pass, model, light_view_proj: ape_math.Mat4) -> bool {
	uniforms := Object_Uniforms {
		model = model,
		light_view_proj = light_view_proj,
	}
	switch scene_pass {
	case .Shadow:
		return shadow_depth_shader.apply_uniform_ObjectUniforms(ctx, &uniforms)
	case .Lit:
		return improved_shadows_shader.apply_uniform_ObjectUniforms(ctx, &uniforms)
	}
	return false
}

log_gfx_error :: proc(ctx: ^gfx.Context, message: string) {
	fmt.eprintln(message, ": ", gfx.last_error(ctx))
}

fail_gfx :: proc(ctx: ^gfx.Context, message: string) -> bool {
	log_gfx_error(ctx, message)
	return false
}
