package main

import "core:math"
import ape_math "ape:samples/ape_math"

Scene_Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	uv:       [2]f32,
}

Scene :: struct {
	light_pos:       ape_math.Vec3,
	camera_pos:      ape_math.Vec3,
	camera_target:   ape_math.Vec3,
	light_view_proj: ape_math.Mat4,
	cube_models:     [3]ape_math.Mat4,
	cube_vertices:   [36]Scene_Vertex,
	plane_vertices:  [6]Scene_Vertex,
}

make_scene :: proc() -> Scene {
	light_pos := ape_math.Vec3{-2, 4, -1}
	light_projection := ape_math.orthographic_lh(-10, 10, -10, 10, 1, 7.5)
	light_view := ape_math.look_at_lh(light_pos, ape_math.Vec3{0, 0, 0}, ape_math.Vec3{0, 1, 0})

	return {
		light_pos = light_pos,
		camera_pos = {0, 3.0, -7.0},
		camera_target = {0, 0.4, 0.35},
		light_view_proj = ape_math.mul(light_projection, light_view),
		cube_models = {
			ape_math.mul(ape_math.translation(0, 1.5, 0), ape_math.scale(0.5, 0.5, 0.5)),
			ape_math.mul(ape_math.translation(2, 0, 1), ape_math.scale(0.5, 0.5, 0.5)),
			ape_math.mul(
				ape_math.mul(
					ape_math.translation(-1, 0, 2),
					ape_math.rotation_axis(math.to_radians_f32(60), ape_math.Vec3{1, 0, 1}),
				),
				ape_math.scale(0.25, 0.25, 0.25),
			),
		},
		cube_vertices = {
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
		},
		plane_vertices = {
			{position = { 25, -0.5,  25}, normal = {0, 1, 0}, uv = {25,  0}},
			{position = {-25, -0.5,  25}, normal = {0, 1, 0}, uv = { 0,  0}},
			{position = {-25, -0.5, -25}, normal = {0, 1, 0}, uv = { 0, 25}},
			{position = { 25, -0.5,  25}, normal = {0, 1, 0}, uv = {25,  0}},
			{position = {-25, -0.5, -25}, normal = {0, 1, 0}, uv = { 0, 25}},
			{position = { 25, -0.5, -25}, normal = {0, 1, 0}, uv = {25, 25}},
		},
	}
}
