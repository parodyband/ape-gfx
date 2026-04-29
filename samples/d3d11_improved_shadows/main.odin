package main

import "core:math"
import "core:time"
import ape_math "ape:samples/ape_math"
import gfx_app "ape:gfx_app"
import app "ape:app"
import gfx "ape:gfx"
import improved_shadows_shader "ape:assets/shaders/generated/improved_shadows"
import shadow_depth_shader "ape:assets/shaders/generated/shadow_depth"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)
SHADOW_MAP_SIZE :: 1024
CAMERA_BASE_FOV :: f32(60)

Scene_Pass :: enum {
	Shadow,
	Lit,
}

Camera_Mode :: enum {
	Orbit,
	First_Person,
}

Camera_Controller :: struct {
	mode: Camera_Mode,

	target: ape_math.Vec3,
	orbit_yaw: f32,
	orbit_pitch: f32,
	orbit_distance: f32,

	fp_position: ape_math.Vec3,
	fp_front: ape_math.Vec3,
	fp_right: ape_math.Vec3,
	fp_up: ape_math.Vec3,
	fp_yaw: f32,
	fp_pitch: f32,
	fp_fov: f32,

	toggle_down: bool,
	mouse_ready: bool,
	last_mouse_x: f64,
	last_mouse_y: f64,
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
	gfx_app.must(app.init(), "app init failed")
	defer app.shutdown()

	window := gfx_app.must_create_window({
		width = 800,
		height = 600,
		title = "Improved Shadows (Ape GFX)",
		no_client_api = true,
	})
	defer app.destroy_window(&window)

	fb_width, fb_height := app.framebuffer_size(&window)
	ctx := gfx_app.must_init_gfx({
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

	shadow_target := gfx_app.must_create_render_target(&ctx, {
		label = "shadow map",
		width = SHADOW_MAP_SIZE,
		height = SHADOW_MAP_SIZE,
		depth_format = .D32F,
		sampled_depth = true,
	})
	defer gfx.destroy_render_target(&ctx, &shadow_target)

	shadow_depth_view := shadow_target.depth_stencil_attachment
	shadow_sample_view := shadow_target.depth_sample

	texture_asset := gfx_app.must_load_texture_asset("build/textures/texture.aptex")
	defer gfx_app.unload_texture_asset(&texture_asset)

	diffuse_texture := gfx_app.must_create_image(&ctx, {
		label = "diffuse texture",
		kind = .Image_2D,
		usage = {.Texture, .Immutable},
		width = texture_asset.width,
		height = texture_asset.height,
		format = .RGBA8,
		data = gfx.range(texture_asset.pixels),
	})
	defer gfx.destroy(&ctx, diffuse_texture)

	diffuse_view := gfx_app.must_create_view(&ctx, {
		label = "diffuse texture view",
		texture = {image = diffuse_texture, format = .RGBA8},
	})
	defer gfx.destroy(&ctx, diffuse_view)

	diffuse_sampler := gfx_app.must_create_sampler(&ctx, {
		label = "diffuse sampler",
		min_filter = .Linear,
		mag_filter = .Linear,
		mip_filter = .Nearest,
		wrap_u = .Repeat,
		wrap_v = .Repeat,
		wrap_w = .Repeat,
	})
	defer gfx.destroy(&ctx, diffuse_sampler)

	shadow_sampler := gfx_app.must_create_sampler(&ctx, {
		label = "shadow sampler",
		min_filter = .Nearest,
		mag_filter = .Nearest,
		mip_filter = .Nearest,
		wrap_u = .Clamp_To_Edge,
		wrap_v = .Clamp_To_Edge,
		wrap_w = .Clamp_To_Edge,
	})
	defer gfx.destroy(&ctx, shadow_sampler)

	cube_buffer := gfx_app.must_create_buffer(&ctx, {
		label = "cube vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(scene.cube_vertices[:]),
	})
	defer gfx.destroy(&ctx, cube_buffer)

	plane_buffer := gfx_app.must_create_buffer(&ctx, {
		label = "plane vertices",
		usage = {.Vertex, .Immutable},
		data = gfx.range(scene.plane_vertices[:]),
	})
	defer gfx.destroy(&ctx, plane_buffer)

	depth_layout := shadow_depth_shader.layout_desc()
	depth_layout.buffers[0].stride = u32(size_of(Scene_Vertex))
	depth_program := gfx_app.must_load_shader_program(&ctx, {
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
		binding_group_layout_desc = shadow_depth_shader.binding_group_layout_desc,
	})
	defer gfx_app.shader_program_destroy(&ctx, &depth_program)

	shadows_program := gfx_app.must_load_shader_program(&ctx, {
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
		binding_group_layout_desc = improved_shadows_shader.binding_group_layout_desc,
	})
	defer gfx_app.shader_program_destroy(&ctx, &shadows_program)

	material_group_layout := gfx_app.shader_program_binding_group_layout(&shadows_program, improved_shadows_shader.GROUP_1)
	shadow_resources_group_layout := gfx_app.shader_program_binding_group_layout(&shadows_program, improved_shadows_shader.GROUP_2)

	depth_cube_bindings: gfx.Bindings
	depth_cube_bindings.vertex_buffers[0] = {buffer = cube_buffer}
	depth_plane_bindings: gfx.Bindings
	depth_plane_bindings.vertex_buffers[0] = {buffer = plane_buffer}

	shadows_cube_bindings := depth_cube_bindings
	shadows_plane_bindings := depth_plane_bindings

	material_group_desc: gfx.Binding_Group_Desc
	material_group_desc.layout = material_group_layout
	improved_shadows_shader.set_group_view_material_diffuse_texture(&material_group_desc, diffuse_view)
	improved_shadows_shader.set_group_sampler_material_diffuse_sampler(&material_group_desc, diffuse_sampler)
	material_group, material_group_ok := gfx.create_binding_group(&ctx, material_group_desc)
	gfx_app.must_gfx(&ctx, material_group_ok, "improved shadows material binding group creation failed")
	defer gfx.destroy(&ctx, material_group)

	shadow_resources_group_desc: gfx.Binding_Group_Desc
	shadow_resources_group_desc.layout = shadow_resources_group_layout
	improved_shadows_shader.set_group_view_shadow_resources_shadow_map(&shadow_resources_group_desc, shadow_sample_view)
	improved_shadows_shader.set_group_sampler_shadow_resources_shadow_sampler(&shadow_resources_group_desc, shadow_sampler)
	shadow_resources_group, shadow_resources_group_ok := gfx.create_binding_group(&ctx, shadow_resources_group_desc)
	gfx_app.must_gfx(&ctx, shadow_resources_group_ok, "improved shadows shadow-resource binding group creation failed")
	defer gfx.destroy(&ctx, shadow_resources_group)

	render_width := fb_width
	render_height := fb_height
	camera := make_camera_controller(scene.camera_pos, ape_math.Vec3{0, 0.45, 0.35})
	last_tick := time.tick_now()
	frame := 0
	for !app.should_close(&window) {
		app.begin_input_frame(&window)
		app.poll_events()
		delta_seconds := f32(time.duration_seconds(time.tick_lap_time(&last_tick)))
		delta_seconds = clamp_f32(delta_seconds, 0, 0.1)
		update_camera(&camera, &window, delta_seconds)

		resize := gfx_app.must_resize_swapchain(&ctx, &window, &render_width, &render_height)
		if !resize.active {
			continue
		}

		gfx_app.begin_pass(&ctx, gfx.render_target_pass_desc(shadow_target, "shadow map pass", {}))
		gfx_app.apply_pipeline(&ctx, depth_program.pipeline)
		draw_scene(&ctx, .Shadow, depth_plane_bindings, depth_cube_bindings, scene.light_view_proj, scene.cube_models[:], i32(len(scene.plane_vertices)), i32(len(scene.cube_vertices)))
		gfx_app.end_pass(&ctx)

		// APE-16: barrier the shadow depth image from Depth_Target_Write to
		// Sampled before the lit pass binds it through shadow_resources_group.
		// D3D11 no-ops; Vulkan/D3D12 require this transition.
		shadow_to_sampled := [?]gfx.Image_Transition {
			{image = shadow_target.depth_image, from = .Depth_Target_Write, to = .Sampled},
		}
		gfx_app.must_gfx(&ctx, gfx.barrier(&ctx, {image_transitions = shadow_to_sampled[:]}), "shadow->sampled barrier failed")

		camera_pos := camera_position(&camera)
		view := camera_view(&camera)
		projection := camera_projection(&camera, render_width, render_height)
		frame_uniforms := Frame_Uniforms {
			ape_view_proj = ape_math.mul(projection, view),
			ape_light_pos = {scene.light_pos[0], scene.light_pos[1], scene.light_pos[2], 0},
			ape_view_pos = {camera_pos[0], camera_pos[1], camera_pos[2], 0},
			ape_shadow_map_size = {SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, 0, 0},
		}

		gfx_app.begin_pass(&ctx, {
			label = "shadows pass",
			action = {colors = {0 = {clear_value = {r = 0.1, g = 0.1, b = 0.1, a = 1}}}},
		})
		gfx_app.apply_pipeline(&ctx, shadows_program.pipeline)
		apply_frame_uniforms(&ctx, &frame_uniforms)
		draw_scene(
			&ctx,
			.Lit,
			shadows_plane_bindings,
			shadows_cube_bindings,
			scene.light_view_proj,
			scene.cube_models[:],
			i32(len(scene.plane_vertices)),
			i32(len(scene.cube_vertices)),
			material_group,
			shadow_resources_group,
		)
		gfx_app.end_pass(&ctx)
		gfx_app.commit(&ctx)

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
	material_group: gfx.Binding_Group = gfx.Binding_Group_Invalid,
	shadow_resources_group: gfx.Binding_Group = gfx.Binding_Group_Invalid,
) {
	apply_scene_bindings(ctx, scene_pass, plane_bindings, material_group, shadow_resources_group)
	apply_object_uniforms(ctx, scene_pass, ape_math.identity(), light_view_proj)
	gfx_app.draw(ctx, 0, plane_vertex_count)

	apply_scene_bindings(ctx, scene_pass, cube_bindings, material_group, shadow_resources_group)
	for model in cube_models {
		apply_object_uniforms(ctx, scene_pass, model, light_view_proj)
		gfx_app.draw(ctx, 0, cube_vertex_count)
	}
}

apply_scene_bindings :: proc(
	ctx: ^gfx.Context,
	scene_pass: Scene_Pass,
	base_bindings: gfx.Bindings,
	material_group: gfx.Binding_Group,
	shadow_resources_group: gfx.Binding_Group,
) {
	switch scene_pass {
	case .Shadow:
		gfx_app.apply_bindings(ctx, base_bindings)
	case .Lit:
		groups := [?]gfx.Binding_Group{material_group, shadow_resources_group}
		gfx_app.must_gfx(ctx, gfx.apply_binding_groups(ctx, groups[:], base_bindings), "lit binding groups apply failed")
	}
}

apply_object_uniforms :: proc(ctx: ^gfx.Context, scene_pass: Scene_Pass, model, light_view_proj: ape_math.Mat4) {
	uniforms := Object_Uniforms {
		ape_model = model,
		ape_light_view_proj = light_view_proj,
	}
	switch scene_pass {
	case .Shadow:
		gfx_app.must_gfx(ctx, shadow_depth_shader.apply_uniform_ObjectUniforms(ctx, &uniforms), "shadow object uniform upload failed")
	case .Lit:
		gfx_app.must_gfx(ctx, improved_shadows_shader.apply_uniform_ObjectUniforms(ctx, &uniforms), "lit object uniform upload failed")
	}
}

apply_frame_uniforms :: proc(ctx: ^gfx.Context, uniforms: ^Frame_Uniforms) {
	gfx_app.must_gfx(ctx, improved_shadows_shader.apply_uniform_FrameUniforms(ctx, uniforms), "frame uniform upload failed")
}

make_camera_controller :: proc(initial_position, target: ape_math.Vec3) -> Camera_Controller {
	offset := ape_math.sub3(initial_position, target)
	orbit_distance := length3(offset)
	orbit_yaw := math.to_degrees_f32(math.atan2_f32(offset[0], offset[2]))
	orbit_pitch := math.to_degrees_f32(math.asin_f32(offset[1] / orbit_distance))

	front := ape_math.normalize3(ape_math.sub3(target, initial_position))
	fp_yaw := math.to_degrees_f32(math.atan2_f32(front[0], front[2]))
	fp_pitch := math.to_degrees_f32(math.asin_f32(front[1]))

	camera := Camera_Controller {
		mode = .Orbit,
		target = target,
		orbit_yaw = orbit_yaw,
		orbit_pitch = orbit_pitch,
		orbit_distance = orbit_distance,
		fp_position = initial_position,
		fp_yaw = fp_yaw,
		fp_pitch = fp_pitch,
		fp_fov = CAMERA_BASE_FOV,
	}
	update_first_person_camera_vectors(&camera)
	return camera
}

update_camera :: proc(camera: ^Camera_Controller, window: ^app.Window, delta_seconds: f32) {
	if app.key_down(window, .Escape) {
		app.request_close(window)
	}

	toggle_down := app.key_down(window, .C)
	if toggle_down && !camera.toggle_down {
		camera.mode = camera.mode == .Orbit ? .First_Person : .Orbit
		camera.mouse_ready = false
	}
	camera.toggle_down = toggle_down

	mouse_x, mouse_y := app.cursor_position(window)
	mouse_dx, mouse_dy: f64
	left_down := app.mouse_button_down(window, .Left)
	if left_down {
		if camera.mouse_ready {
			mouse_dx = mouse_x - camera.last_mouse_x
			mouse_dy = mouse_y - camera.last_mouse_y
		} else {
			camera.mouse_ready = true
		}
	} else {
		camera.mouse_ready = false
	}
	camera.last_mouse_x = mouse_x
	camera.last_mouse_y = mouse_y

	_, scroll_y := app.scroll_delta(window)

	switch camera.mode {
	case .Orbit:
		update_orbit_camera(camera, mouse_dx, mouse_dy, scroll_y, left_down)
	case .First_Person:
		update_first_person_camera(camera, window, mouse_dx, mouse_dy, scroll_y, left_down, delta_seconds)
	}
}

update_orbit_camera :: proc(camera: ^Camera_Controller, mouse_dx, mouse_dy, scroll_y: f64, rotating: bool) {
	if rotating {
		camera.orbit_yaw += f32(mouse_dx) * 1.0
		camera.orbit_pitch += f32(mouse_dy) * 1.0
		camera.orbit_pitch = clamp_f32(camera.orbit_pitch, -89, 89)
	}

	if scroll_y != 0 {
		camera.orbit_distance -= f32(scroll_y) * 0.5
		camera.orbit_distance = clamp_f32(camera.orbit_distance, 1.0, 20.0)
	}
}

update_first_person_camera :: proc(
	camera: ^Camera_Controller,
	window: ^app.Window,
	mouse_dx, mouse_dy, scroll_y: f64,
	aiming: bool,
	delta_seconds: f32,
) {
	if aiming {
		camera.fp_yaw += f32(mouse_dx) * 0.1
		camera.fp_pitch -= f32(mouse_dy) * 0.1
		camera.fp_pitch = clamp_f32(camera.fp_pitch, -89, 89)
		update_first_person_camera_vectors(camera)
	}

	if scroll_y != 0 {
		camera.fp_fov -= f32(scroll_y)
		camera.fp_fov = clamp_f32(camera.fp_fov, 20, 75)
	}

	velocity := 5.0 * delta_seconds
	if app.key_down(window, .W) || app.key_down(window, .Up) {
		camera.fp_position = add3(camera.fp_position, scale3(camera.fp_front, velocity))
	}
	if app.key_down(window, .S) || app.key_down(window, .Down) {
		camera.fp_position = add3(camera.fp_position, scale3(camera.fp_front, -velocity))
	}
	if app.key_down(window, .A) || app.key_down(window, .Left) {
		camera.fp_position = add3(camera.fp_position, scale3(camera.fp_right, -velocity))
	}
	if app.key_down(window, .D) || app.key_down(window, .Right) {
		camera.fp_position = add3(camera.fp_position, scale3(camera.fp_right, velocity))
	}
}

update_first_person_camera_vectors :: proc(camera: ^Camera_Controller) {
	yaw := math.to_radians_f32(camera.fp_yaw)
	pitch := math.to_radians_f32(camera.fp_pitch)
	front := ape_math.Vec3 {
		math.cos_f32(pitch) * math.sin_f32(yaw),
		math.sin_f32(pitch),
		math.cos_f32(pitch) * math.cos_f32(yaw),
	}
	camera.fp_front = ape_math.normalize3(front)
	camera.fp_right = ape_math.normalize3(ape_math.cross3(ape_math.Vec3{0, 1, 0}, camera.fp_front))
	camera.fp_up = ape_math.cross3(camera.fp_front, camera.fp_right)
}

camera_position :: proc(camera: ^Camera_Controller) -> ape_math.Vec3 {
	switch camera.mode {
	case .Orbit:
		return orbit_camera_position(camera)
	case .First_Person:
		return camera.fp_position
	}

	return camera.fp_position
}

camera_view :: proc(camera: ^Camera_Controller) -> ape_math.Mat4 {
	switch camera.mode {
	case .Orbit:
		return ape_math.look_at_lh(orbit_camera_position(camera), camera.target, ape_math.Vec3{0, 1, 0})
	case .First_Person:
		return ape_math.look_at_lh(camera.fp_position, add3(camera.fp_position, camera.fp_front), camera.fp_up)
	}

	return ape_math.identity()
}

camera_projection :: proc(camera: ^Camera_Controller, width, height: i32) -> ape_math.Mat4 {
	aspect := f32(16.0 / 9.0)
	if height > 0 {
		aspect = f32(width) / f32(height)
	}

	fov := CAMERA_BASE_FOV
	if camera.mode == .First_Person {
		fov = camera.fp_fov
	}

	return ape_math.perspective_lh(math.to_radians_f32(fov), aspect, 0.1, 100)
}

orbit_camera_position :: proc(camera: ^Camera_Controller) -> ape_math.Vec3 {
	yaw := math.to_radians_f32(camera.orbit_yaw)
	pitch := math.to_radians_f32(camera.orbit_pitch)
	cos_pitch := math.cos_f32(pitch)

	return add3(camera.target, ape_math.Vec3 {
		camera.orbit_distance * cos_pitch * math.sin_f32(yaw),
		camera.orbit_distance * math.sin_f32(pitch),
		camera.orbit_distance * cos_pitch * math.cos_f32(yaw),
	})
}

add3 :: proc(a, b: ape_math.Vec3) -> ape_math.Vec3 {
	return ape_math.Vec3{a[0] + b[0], a[1] + b[1], a[2] + b[2]}
}

scale3 :: proc(v: ape_math.Vec3, scalar: f32) -> ape_math.Vec3 {
	return ape_math.Vec3{v[0] * scalar, v[1] * scalar, v[2] * scalar}
}

length3 :: proc(v: ape_math.Vec3) -> f32 {
	return math.sqrt_f32(ape_math.dot3(v, v))
}

clamp_f32 :: proc(value, min_value, max_value: f32) -> f32 {
	if value < min_value {
		return min_value
	}
	if value > max_value {
		return max_value
	}
	return value
}
