package ape_math

import "core:math"

Vec3 :: [3]f32
Mat4 :: [4][4]f32

identity :: proc() -> Mat4 {
	return Mat4 {
		{1, 0, 0, 0},
		{0, 1, 0, 0},
		{0, 0, 1, 0},
		{0, 0, 0, 1},
	}
}

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

scale :: proc(x, y, z: f32) -> Mat4 {
	return Mat4 {
		{x, 0, 0, 0},
		{0, y, 0, 0},
		{0, 0, z, 0},
		{0, 0, 0, 1},
	}
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

rotation_axis :: proc(angle: f32, axis: Vec3) -> Mat4 {
	n := normalize3(axis)
	x := n[0]
	y := n[1]
	z := n[2]
	c := math.cos_f32(angle)
	s := math.sin_f32(angle)
	t := 1 - c

	return Mat4 {
		{t * x * x + c,     t * x * y - s * z, t * x * z + s * y, 0},
		{t * x * y + s * z, t * y * y + c,     t * y * z - s * x, 0},
		{t * x * z - s * y, t * y * z + s * x, t * z * z + c,     0},
		{0,                 0,                 0,                 1},
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

orthographic_lh :: proc(left, right, bottom, top, near_z, far_z: f32) -> Mat4 {
	return Mat4 {
		{2 / (right - left), 0, 0, -(right + left) / (right - left)},
		{0, 2 / (top - bottom), 0, -(top + bottom) / (top - bottom)},
		{0, 0, 1 / (far_z - near_z), -near_z / (far_z - near_z)},
		{0, 0, 0, 1},
	}
}

look_at_lh :: proc(eye, target, up: Vec3) -> Mat4 {
	z_axis := normalize3(sub3(target, eye))
	x_axis := normalize3(cross3(up, z_axis))
	y_axis := cross3(z_axis, x_axis)

	return Mat4 {
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

// 4x4 matrix inverse via cofactor expansion. Returns identity if the
// input is singular (det == 0). Used by the bistro skybox to reproject
// NDC corners into world-space ray directions.
inverse :: proc(m: Mat4) -> Mat4 {
	a := m
	inv: Mat4

	inv[0][0] =  a[1][1]*a[2][2]*a[3][3] - a[1][1]*a[2][3]*a[3][2] - a[2][1]*a[1][2]*a[3][3] + a[2][1]*a[1][3]*a[3][2] + a[3][1]*a[1][2]*a[2][3] - a[3][1]*a[1][3]*a[2][2]
	inv[1][0] = -a[1][0]*a[2][2]*a[3][3] + a[1][0]*a[2][3]*a[3][2] + a[2][0]*a[1][2]*a[3][3] - a[2][0]*a[1][3]*a[3][2] - a[3][0]*a[1][2]*a[2][3] + a[3][0]*a[1][3]*a[2][2]
	inv[2][0] =  a[1][0]*a[2][1]*a[3][3] - a[1][0]*a[2][3]*a[3][1] - a[2][0]*a[1][1]*a[3][3] + a[2][0]*a[1][3]*a[3][1] + a[3][0]*a[1][1]*a[2][3] - a[3][0]*a[1][3]*a[2][1]
	inv[3][0] = -a[1][0]*a[2][1]*a[3][2] + a[1][0]*a[2][2]*a[3][1] + a[2][0]*a[1][1]*a[3][2] - a[2][0]*a[1][2]*a[3][1] - a[3][0]*a[1][1]*a[2][2] + a[3][0]*a[1][2]*a[2][1]

	inv[0][1] = -a[0][1]*a[2][2]*a[3][3] + a[0][1]*a[2][3]*a[3][2] + a[2][1]*a[0][2]*a[3][3] - a[2][1]*a[0][3]*a[3][2] - a[3][1]*a[0][2]*a[2][3] + a[3][1]*a[0][3]*a[2][2]
	inv[1][1] =  a[0][0]*a[2][2]*a[3][3] - a[0][0]*a[2][3]*a[3][2] - a[2][0]*a[0][2]*a[3][3] + a[2][0]*a[0][3]*a[3][2] + a[3][0]*a[0][2]*a[2][3] - a[3][0]*a[0][3]*a[2][2]
	inv[2][1] = -a[0][0]*a[2][1]*a[3][3] + a[0][0]*a[2][3]*a[3][1] + a[2][0]*a[0][1]*a[3][3] - a[2][0]*a[0][3]*a[3][1] - a[3][0]*a[0][1]*a[2][3] + a[3][0]*a[0][3]*a[2][1]
	inv[3][1] =  a[0][0]*a[2][1]*a[3][2] - a[0][0]*a[2][2]*a[3][1] - a[2][0]*a[0][1]*a[3][2] + a[2][0]*a[0][2]*a[3][1] + a[3][0]*a[0][1]*a[2][2] - a[3][0]*a[0][2]*a[2][1]

	inv[0][2] =  a[0][1]*a[1][2]*a[3][3] - a[0][1]*a[1][3]*a[3][2] - a[1][1]*a[0][2]*a[3][3] + a[1][1]*a[0][3]*a[3][2] + a[3][1]*a[0][2]*a[1][3] - a[3][1]*a[0][3]*a[1][2]
	inv[1][2] = -a[0][0]*a[1][2]*a[3][3] + a[0][0]*a[1][3]*a[3][2] + a[1][0]*a[0][2]*a[3][3] - a[1][0]*a[0][3]*a[3][2] - a[3][0]*a[0][2]*a[1][3] + a[3][0]*a[0][3]*a[1][2]
	inv[2][2] =  a[0][0]*a[1][1]*a[3][3] - a[0][0]*a[1][3]*a[3][1] - a[1][0]*a[0][1]*a[3][3] + a[1][0]*a[0][3]*a[3][1] + a[3][0]*a[0][1]*a[1][3] - a[3][0]*a[0][3]*a[1][1]
	inv[3][2] = -a[0][0]*a[1][1]*a[3][2] + a[0][0]*a[1][2]*a[3][1] + a[1][0]*a[0][1]*a[3][2] - a[1][0]*a[0][2]*a[3][1] - a[3][0]*a[0][1]*a[1][2] + a[3][0]*a[0][2]*a[1][1]

	inv[0][3] = -a[0][1]*a[1][2]*a[2][3] + a[0][1]*a[1][3]*a[2][2] + a[1][1]*a[0][2]*a[2][3] - a[1][1]*a[0][3]*a[2][2] - a[2][1]*a[0][2]*a[1][3] + a[2][1]*a[0][3]*a[1][2]
	inv[1][3] =  a[0][0]*a[1][2]*a[2][3] - a[0][0]*a[1][3]*a[2][2] - a[1][0]*a[0][2]*a[2][3] + a[1][0]*a[0][3]*a[2][2] + a[2][0]*a[0][2]*a[1][3] - a[2][0]*a[0][3]*a[1][2]
	inv[2][3] = -a[0][0]*a[1][1]*a[2][3] + a[0][0]*a[1][3]*a[2][1] + a[1][0]*a[0][1]*a[2][3] - a[1][0]*a[0][3]*a[2][1] - a[2][0]*a[0][1]*a[1][3] + a[2][0]*a[0][3]*a[1][1]
	inv[3][3] =  a[0][0]*a[1][1]*a[2][2] - a[0][0]*a[1][2]*a[2][1] - a[1][0]*a[0][1]*a[2][2] + a[1][0]*a[0][2]*a[2][1] + a[2][0]*a[0][1]*a[1][2] - a[2][0]*a[0][2]*a[1][1]

	det := a[0][0]*inv[0][0] + a[0][1]*inv[1][0] + a[0][2]*inv[2][0] + a[0][3]*inv[3][0]
	if det == 0 { return identity() }
	inv_det := 1.0 / det
	for r in 0 ..< 4 {
		for c in 0 ..< 4 {
			inv[r][c] *= inv_det
		}
	}
	return inv
}
