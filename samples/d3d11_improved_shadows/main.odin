package main

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

Object_Uniforms :: struct {
	ape_model:           ape_math.Mat4,
	ape_light_view_proj: ape_math.Mat4,
}

Frame_Uniforms :: struct {
	ape_view_proj:       ape_math.Mat4,
	ape_light_pos:       [4]f32,
	ape_view_pos:        [4]f32,
	ape_shadow_map_size: [4]f32,
}

main :: proc() {
	ape_sample.must(app.init(), "app init failed")
	defer app.shutdown()

	window := ape_sample.must_create_window({
		width = 800,
		height = 600,
		title = "Improved Shadows (Ape GFX)",
		no_client_api = true,
	})
	defer app.destroy_window(&window)

	fb_width, fb_height := app.framebuffer_size(&window)
	ctx := ape_sample.must_init_gfx({
		backend = .D3D11,
		width = fb_width,
		height = fb_height,
		native_window = app.native_window_handle(&window),
		swapchain_format = .BGRA8,
		vsync = true,
		debug = true,
		label = "ape d3d11 improved shadows",
	})
	defer gfx.shutdown(&ctx)

	scene := make_scene()

	shadow_image := ape_sample.must_create_image(&ctx, {
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
	defer gfx.destroy(&ctx, shadow_image)

	shadow_depth_view := ape_sample.must_create_view(&ctx, {
		label = "shadow depth attachment",
		depth_stencil_attachment = {image = shadow_image, format = .D32F},
	})
	defer gfx.destroy(&ctx, shadow_depth_view)

	shadow_sample_view := ape_sample.must_create_view(&ctx, {
		label = "shadow sampled depth",
		texture = {image = shadow_image, format = .D32F},
	})
	defer gfx.destroy(&ctx, shadow_sample_view)

	texture_asset := ape_sample.must_load_texture_asset("build/textures/texture.aptex")
	defer ape_sample.unload_texture_asset(&texture_asset)

	diffuse_texture := ape_sample.must_create_image(&ctx, {
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
	defer gfx.destroy(&ctx, diffuse_texture)

	diffuse_view := ape_sample.must_create_view(&ctx, {
		label = "diffuse texture view",
		texture = {image = diffuse_texture, format = .RGBA8},
	})
	defer gfx.destroy(&ctx, diffuse_view)

	diffuse_sampler := ape_sample.must_create_sampler(&ctx, {
		label = "diffuse sampler",
		min_filter = .Linear,
		mag_filter = .Linear,
		mip_filter = .Nearest,
		wrap_u = .Repeat,
		wrap_v = .Repeat,
		wrap_w = .Repeat,
	})
	defer gfx.destroy(&ctx, diffuse_sampler)

	shadow_sampler := ape_sample.must_create_sampler(&ctx, {
		label = "shadow sampler",
		min_filter = .Nearest,
		mag_filter = .Nearest,
		mip_filter = .Nearest,
		wrap_u = .Clamp_To_Edge,
		wrap_v = .Clamp_To_Edge,
		wrap_w = .Clamp_To_Edge,
	})
	defer gfx.destroy(&ctx, shadow_sampler)

	cube_buffer := ape_sample.must_create_buffer(&ctx, {
		label = "cube vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(scene.cube_vertices[:]),
	})
	defer gfx.destroy(&ctx, cube_buffer)

	plane_buffer := ape_sample.must_create_buffer(&ctx, {
		label = "plane vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(scene.plane_vertices[:]),
	})
	defer gfx.destroy(&ctx, plane_buffer)

	depth_layout := shadow_depth_shader.layout_desc()
	depth_layout.buffers[0].stride = u32(size_of(Scene_Vertex))
	depth_program := ape_sample.must_load_shader_program(&ctx, {
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
	defer ape_sample.shader_program_destroy(&ctx, &depth_program)

	shadows_program := ape_sample.must_load_shader_program(&ctx, {
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

		resize := ape_sample.must_resize_swapchain(&ctx, &window, &render_width, &render_height)
		if !resize.active {
			continue
		}

		shadow_action := gfx.default_pass_action()
		shadow_action.depth.clear_value = 1
		ape_sample.begin_pass(&ctx, {label = "shadow map pass", depth_stencil_attachment = shadow_depth_view, action = shadow_action})
		ape_sample.apply_pipeline(&ctx, depth_program.pipeline)
		draw_scene(&ctx, .Shadow, depth_plane_bindings, depth_cube_bindings, scene.light_view_proj, scene.cube_models[:], i32(len(scene.plane_vertices)), i32(len(scene.cube_vertices)))
		ape_sample.end_pass(&ctx)

		view := ape_math.look_at_lh(scene.camera_pos, ape_math.Vec3{0, 0.45, 0.35}, ape_math.Vec3{0, 1, 0})
		projection := ape_math.cube_projection(render_width, render_height)
		frame_uniforms := Frame_Uniforms {
			ape_view_proj = ape_math.mul(projection, view),
			ape_light_pos = {scene.light_pos[0], scene.light_pos[1], scene.light_pos[2], 0},
			ape_view_pos = {scene.camera_pos[0], scene.camera_pos[1], scene.camera_pos[2], 0},
			ape_shadow_map_size = {SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, 0, 0},
		}

		pass_action := gfx.default_pass_action()
		pass_action.colors[0].clear_value = gfx.Color{r = 0.1, g = 0.1, b = 0.1, a = 1}
		pass_action.depth.clear_value = 1
		ape_sample.begin_pass(&ctx, {label = "shadows pass", action = pass_action})
		ape_sample.apply_pipeline(&ctx, shadows_program.pipeline)
		apply_frame_uniforms(&ctx, &frame_uniforms)
		draw_scene(&ctx, .Lit, shadows_plane_bindings, shadows_cube_bindings, scene.light_view_proj, scene.cube_models[:], i32(len(scene.plane_vertices)), i32(len(scene.cube_vertices)))
		ape_sample.end_pass(&ctx)
		ape_sample.commit(&ctx)

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
) {
	ape_sample.apply_bindings(ctx, plane_bindings)
	apply_object_uniforms(ctx, scene_pass, ape_math.identity(), light_view_proj)
	ape_sample.draw(ctx, 0, plane_vertex_count)

	ape_sample.apply_bindings(ctx, cube_bindings)
	for model in cube_models {
		apply_object_uniforms(ctx, scene_pass, model, light_view_proj)
		ape_sample.draw(ctx, 0, cube_vertex_count)
	}
}

apply_object_uniforms :: proc(ctx: ^gfx.Context, scene_pass: Scene_Pass, model, light_view_proj: ape_math.Mat4) {
	uniforms := Object_Uniforms {
		ape_model = model,
		ape_light_view_proj = light_view_proj,
	}
	switch scene_pass {
	case .Shadow:
		ape_sample.must_gfx(ctx, shadow_depth_shader.apply_uniform_ObjectUniforms(ctx, &uniforms), "shadow object uniform upload failed")
	case .Lit:
		ape_sample.must_gfx(ctx, improved_shadows_shader.apply_uniform_ObjectUniforms(ctx, &uniforms), "lit object uniform upload failed")
	}
}

apply_frame_uniforms :: proc(ctx: ^gfx.Context, uniforms: ^Frame_Uniforms) {
	ape_sample.must_gfx(ctx, improved_shadows_shader.apply_uniform_FrameUniforms(ctx, uniforms), "frame uniform upload failed")
}
