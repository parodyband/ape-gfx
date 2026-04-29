package gfx

// create_render_target creates image and view handles for a simple offscreen render target.
// It supports color-only, depth-only, and color-plus-depth targets with optional sampled views.
create_render_target :: proc(ctx: ^Context, desc: Render_Target_Desc) -> (Render_Target, bool) {
	if !require_initialized(ctx, "gfx.create_render_target") {
		return {}, false
	}

	if !validate_render_target_desc(ctx, desc) {
		return {}, false
	}

	sample_count := render_target_sample_count(desc)
	target := Render_Target {
		width = desc.width,
		height = desc.height,
		sample_count = sample_count,
		color_format = desc.color_format,
		depth_format = desc.depth_format,
	}

	if desc.color_format != .Invalid {
		usage := Image_Usage{.Color_Attachment}
		if desc.sampled_color {
			usage += {.Texture}
		}

		image, image_ok := create_image(ctx, {
			label = desc.label,
			kind = .Image_2D,
			usage = usage,
			width = desc.width,
			height = desc.height,
			mip_count = 1,
			array_count = 1,
			sample_count = sample_count,
			format = desc.color_format,
		})
		if !image_ok {
			destroy_render_target(ctx, &target)
			return {}, false
		}
		target.color_image = image

		attachment, attachment_ok := create_view(ctx, {
			label = desc.label,
			color_attachment = {image = image, format = desc.color_format},
		})
		if !attachment_ok {
			destroy_render_target(ctx, &target)
			return {}, false
		}
		target.color_attachment = attachment

		if desc.sampled_color {
			sample, sample_ok := create_view(ctx, {
				label = desc.label,
				texture = {image = image, format = desc.color_format},
			})
			if !sample_ok {
				destroy_render_target(ctx, &target)
				return {}, false
			}
			target.color_sample = sample
		}
	}

	if desc.depth_format != .Invalid {
		usage := Image_Usage{.Depth_Stencil_Attachment}
		if desc.sampled_depth {
			usage += {.Texture}
		}

		image, image_ok := create_image(ctx, {
			label = desc.label,
			kind = .Image_2D,
			usage = usage,
			width = desc.width,
			height = desc.height,
			mip_count = 1,
			array_count = 1,
			sample_count = sample_count,
			format = desc.depth_format,
		})
		if !image_ok {
			destroy_render_target(ctx, &target)
			return {}, false
		}
		target.depth_image = image

		attachment, attachment_ok := create_view(ctx, {
			label = desc.label,
			depth_stencil_attachment = {image = image, format = desc.depth_format},
		})
		if !attachment_ok {
			destroy_render_target(ctx, &target)
			return {}, false
		}
		target.depth_stencil_attachment = attachment

		if desc.sampled_depth {
			sample, sample_ok := create_view(ctx, {
				label = desc.label,
				texture = {image = image, format = desc.depth_format},
			})
			if !sample_ok {
				destroy_render_target(ctx, &target)
				return {}, false
			}
			target.depth_sample = sample
		}
	}

	return target, true
}

// destroy_render_target releases all live handles owned by a Render_Target and clears the struct.
destroy_render_target :: proc(ctx: ^Context, target: ^Render_Target) {
	if target == nil {
		return
	}

	if view_valid(target.color_sample) {
		destroy(ctx, target.color_sample)
	}
	if view_valid(target.color_attachment) {
		destroy(ctx, target.color_attachment)
	}
	if view_valid(target.depth_sample) {
		destroy(ctx, target.depth_sample)
	}
	if view_valid(target.depth_stencil_attachment) {
		destroy(ctx, target.depth_stencil_attachment)
	}
	if image_valid(target.color_image) {
		destroy(ctx, target.color_image)
	}
	if image_valid(target.depth_image) {
		destroy(ctx, target.depth_image)
	}

	target^ = {}
}

// render_target_pass_desc returns a Pass_Desc that targets the render target's attachment views.
render_target_pass_desc :: proc(target: Render_Target, label: string, action: Pass_Action) -> Pass_Desc {
	desc := Pass_Desc {
		label = label,
		depth_stencil_attachment = target.depth_stencil_attachment,
		action = action,
	}
	desc.color_attachments[0] = target.color_attachment
	return desc
}

@(private)
validate_render_target_desc :: proc(ctx: ^Context, desc: Render_Target_Desc) -> bool {
	if desc.width <= 0 || desc.height <= 0 {
		set_validation_error(ctx, "gfx.create_render_target: width and height must be positive")
		return false
	}

	has_color := desc.color_format != .Invalid
	has_depth := desc.depth_format != .Invalid
	if !has_color && !has_depth {
		set_validation_error(ctx, "gfx.create_render_target: color_format or depth_format is required")
		return false
	}
	if desc.sampled_color && !has_color {
		set_validation_error(ctx, "gfx.create_render_target: sampled_color requires color_format")
		return false
	}
	if desc.sampled_depth && !has_depth {
		set_validation_error(ctx, "gfx.create_render_target: sampled_depth requires depth_format")
		return false
	}
	if has_color && !pixel_format_is_color(desc.color_format) {
		set_validation_error(ctx, "gfx.create_render_target: color_format must be a color format")
		return false
	}
	if has_depth && !pixel_format_is_depth(desc.depth_format) {
		set_validation_error(ctx, "gfx.create_render_target: depth_format must be a depth format")
		return false
	}

	sample_count := render_target_sample_count(desc)
	if sample_count <= 0 {
		set_validation_error(ctx, "gfx.create_render_target: sample_count must be positive when specified")
		return false
	}
	if sample_count > 1 && desc.sampled_color {
		set_validation_error(ctx, "gfx.create_render_target: sampled_color does not support multisampled targets yet; resolve into a single-sampled texture")
		return false
	}
	if sample_count > 1 && desc.sampled_depth {
		set_validation_error(ctx, "gfx.create_render_target: sampled_depth does not support multisampled targets yet")
		return false
	}

	return true
}

@(private)
render_target_sample_count :: proc(desc: Render_Target_Desc) -> i32 {
	if desc.sample_count == 0 {
		return 1
	}
	return desc.sample_count
}
