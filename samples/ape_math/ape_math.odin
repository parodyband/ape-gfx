package ape_math

import "core:math"

Mat4 :: [4][4]f32

cube_projection :: proc(width, height: i32) -> Mat4 {
	aspect := f32(16.0 / 9.0)
	if height > 0 {
		aspect = f32(width) / f32(height)
	}

	return perspective_lh(math.to_radians_f32(60), aspect, 0.1, 100)
}

mul :: proc(a, b: Mat4) -> Mat4 {
	result: Mat4
	for row in 0..<4 {
		for col in 0..<4 {
			result[row][col] =
				a[row][0] * b[0][col] +
				a[row][1] * b[1][col] +
				a[row][2] * b[2][col] +
				a[row][3] * b[3][col]
		}
	}
	return result
}

translation :: proc(x, y, z: f32) -> Mat4 {
	return Mat4 {
		{1, 0, 0, x},
		{0, 1, 0, y},
		{0, 0, 1, z},
		{0, 0, 0, 1},
	}
}

rotation_x :: proc(angle: f32) -> Mat4 {
	c := math.cos_f32(angle)
	s := math.sin_f32(angle)
	return Mat4 {
		{1, 0,  0, 0},
		{0, c, -s, 0},
		{0, s,  c, 0},
		{0, 0,  0, 1},
	}
}

rotation_y :: proc(angle: f32) -> Mat4 {
	c := math.cos_f32(angle)
	s := math.sin_f32(angle)
	return Mat4 {
		{ c, 0, s, 0},
		{ 0, 1, 0, 0},
		{-s, 0, c, 0},
		{ 0, 0, 0, 1},
	}
}

perspective_lh :: proc(fovy_radians, aspect, near_z, far_z: f32) -> Mat4 {
	y_scale := 1.0 / math.tan_f32(fovy_radians * 0.5)
	x_scale := y_scale / aspect
	z_scale := far_z / (far_z - near_z)
	z_bias := -near_z * far_z / (far_z - near_z)

	return Mat4 {
		{x_scale, 0,       0,       0},
		{0,       y_scale, 0,       0},
		{0,       0,       z_scale, z_bias},
		{0,       0,       1,       0},
	}
}
