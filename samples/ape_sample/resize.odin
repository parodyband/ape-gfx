package ape_sample

import app "ape:app"
import gfx "ape:gfx"

Resize_Result :: struct {
	active: bool,
	resized: bool,
	width: i32,
	height: i32,
}

resize_swapchain :: proc(ctx: ^gfx.Context, window: ^app.Window, current_width, current_height: ^i32) -> (Resize_Result, bool) {
	width, height := app.framebuffer_size(window)
	result := Resize_Result {
		width = width,
		height = height,
	}

	if width <= 0 || height <= 0 {
		return result, true
	}

	result.active = true
	if width == current_width^ && height == current_height^ {
		return result, true
	}

	if !gfx.resize(ctx, width, height) {
		return result, false
	}

	current_width^ = width
	current_height^ = height
	result.resized = true
	return result, true
}

aspect_fit_half_extents :: proc(view_width, view_height, content_width, content_height: i32, max_half_extent: f32) -> (half_width, half_height: f32) {
	return aspect_fit_half_extents_in_bounds(view_width, view_height, content_width, content_height, max_half_extent, max_half_extent)
}

aspect_fit_half_extents_in_bounds :: proc(view_width, view_height, content_width, content_height: i32, max_half_width, max_half_height: f32) -> (half_width, half_height: f32) {
	if max_half_width <= 0 || max_half_height <= 0 {
		return 0, 0
	}

	if view_width <= 0 || view_height <= 0 || content_width <= 0 || content_height <= 0 {
		return max_half_width, max_half_height
	}

	view_aspect := f32(view_width) / f32(view_height)
	content_aspect := f32(content_width) / f32(content_height)

	half_width = max_half_width
	half_height = half_width * view_aspect / content_aspect
	if half_height <= max_half_height {
		return
	}

	half_height = max_half_height
	half_width = half_height * content_aspect / view_aspect
	return
}

reference_aspect_x_scale :: proc(view_width, view_height: i32, reference_aspect: f32) -> f32 {
	if view_width <= 0 || view_height <= 0 || reference_aspect <= 0 {
		return 1
	}

	view_aspect := f32(view_width) / f32(view_height)
	return reference_aspect / view_aspect
}
