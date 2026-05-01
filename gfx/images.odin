package gfx

// create_image creates a texture, storage image, or attachment image.
// On failure, the returned handle is Image_Invalid and last_error explains why.
//
// example:
//   image, ok := gfx.create_image(&ctx, {
//       label  = "diffuse",
//       kind   = .Image_2D,
//       usage  = {.Texture, .Immutable},
//       width  = 256, height = 256,
//       format = .RGBA8,
//       mips   = {0 = {data = gfx.range(pixels[:])}},
//   })
create_image :: proc(ctx: ^Context, desc: Image_Desc) -> (Image, bool) {
	if !require_initialized(ctx, "gfx.create_image") {
		return Image_Invalid, false
	}

	if desc.width <= 0 || desc.height <= 0 {
		set_validation_error(ctx, "gfx.create_image: width and height must be positive")
		return Image_Invalid, false
	}

	if !validate_image_desc(ctx, desc) {
		return Image_Invalid, false
	}

	array_count := image_desc_array_count(desc)
	sample_count := image_desc_sample_count(desc)
	limits := backend_query_limits(ctx)
	if limits.max_image_dimension_2d > 0 {
		if int(desc.width) > limits.max_image_dimension_2d {
			set_validation_errorf(ctx, "gfx.create_image: width exceeds backend 2D image dimension limit (%d)", limits.max_image_dimension_2d)
			return Image_Invalid, false
		}
		if int(desc.height) > limits.max_image_dimension_2d {
			set_validation_errorf(ctx, "gfx.create_image: height exceeds backend 2D image dimension limit (%d)", limits.max_image_dimension_2d)
			return Image_Invalid, false
		}
	}
	if limits.max_image_array_layers > 0 && int(array_count) > limits.max_image_array_layers {
		set_validation_errorf(ctx, "gfx.create_image: array_count exceeds backend image array layer limit (%d)", limits.max_image_array_layers)
		return Image_Invalid, false
	}
	if limits.max_image_sample_count > 0 && int(sample_count) > limits.max_image_sample_count {
		set_validation_errorf(ctx, "gfx.create_image: sample_count exceeds backend sample count limit (%d)", limits.max_image_sample_count)
		return Image_Invalid, false
	}

	if sample_count > 1 {
		features := backend_query_features(ctx)
		if !features.msaa_render_targets {
			set_unsupported_error(ctx, "gfx.create_image: backend does not support multisampled render targets")
			return Image_Invalid, false
		}
		if image_desc_mip_count(desc) > 1 {
			set_validation_error(ctx, "gfx.create_image: multisampled images cannot have mipmaps")
			return Image_Invalid, false
		}
		if .Texture in desc.usage {
			set_validation_error(ctx, "gfx.create_image: multisampled images cannot use Texture usage yet; resolve into a single-sampled texture")
			return Image_Invalid, false
		}
		if .Storage_Image in desc.usage {
			set_unsupported_error(ctx, "gfx.create_image: multisampled storage images are not supported")
			return Image_Invalid, false
		}
		if !(.Color_Attachment in desc.usage) && !(.Depth_Stencil_Attachment in desc.usage) {
			set_validation_error(ctx, "gfx.create_image: multisampled images must be render attachments")
			return Image_Invalid, false
		}
	}

	handle_id := alloc_resource_id(ctx, &ctx.image_pool, "gfx.create_image")
	if handle_id == 0 {
		return Image_Invalid, false
	}

	handle := Image(handle_id)
	if !backend_create_image(ctx, handle, desc) {
		cancel_resource_id(&ctx.image_pool, handle_id)
		return Image_Invalid, false
	}

	return handle, true
}

// destroy_image releases a live image handle.
destroy_image :: proc(ctx: ^Context, image: Image) {
	if !require_initialized(ctx, "gfx.destroy_image") {
		return
	}
	if !require_resource(ctx, &ctx.image_pool, u64(image), "gfx.destroy_image", "image") {
		return
	}
	if message := image_blocked_from_destroy(ctx, image); message != "" {
		set_validation_error(ctx, message)
		return
	}

	backend_destroy_image(ctx, image)
	release_resource_id(&ctx.image_pool, u64(image))
}

// update_image writes CPU data into a dynamic image subregion.
update_image :: proc(ctx: ^Context, desc: Image_Update_Desc) -> bool {
	if !require_initialized(ctx, "gfx.update_image") {
		return false
	}

	if ctx.in_pass {
		set_validation_error(ctx, "gfx.update_image: cannot update an image while a pass is in progress")
		return false
	}

	if !require_resource(ctx, &ctx.image_pool, u64(desc.image), "gfx.update_image", "image") {
		return false
	}

	if !validate_image_update_desc(ctx, desc) {
		return false
	}

	return backend_update_image(ctx, desc)
}

// resolve_image resolves a multisampled color image into a single-sampled image.
resolve_image :: proc(ctx: ^Context, desc: Image_Resolve_Desc) -> bool {
	if !require_initialized(ctx, "gfx.resolve_image") {
		return false
	}

	if ctx.in_pass {
		set_validation_error(ctx, "gfx.resolve_image: cannot resolve an image while a pass is in progress")
		return false
	}

	if !require_resource(ctx, &ctx.image_pool, u64(desc.source), "gfx.resolve_image", "source image") {
		return false
	}
	if !require_resource(ctx, &ctx.image_pool, u64(desc.destination), "gfx.resolve_image", "destination image") {
		return false
	}

	if !validate_image_resolve_desc(ctx, desc) {
		return false
	}

	return backend_resolve_image(ctx, desc)
}

// query_image_state returns read-only state for a live image, or zero if invalid.
query_image_state :: proc(ctx: ^Context, image: Image) -> Image_State {
	if ctx == nil || !ctx.initialized || !resource_id_alive(ctx, &ctx.image_pool, u64(image)) {
		return {}
	}

	return backend_query_image_state(ctx, image)
}

@(private)
validate_image_desc :: proc(ctx: ^Context, desc: Image_Desc) -> bool {
	if desc.kind != .Image_2D {
		set_unsupported_error(ctx, "gfx.create_image: only Image_2D is supported for now")
		return false
	}
	if desc.depth < 0 {
		set_validation_error(ctx, "gfx.create_image: depth must be non-negative")
		return false
	}
	if desc.depth > 1 {
		set_unsupported_error(ctx, "gfx.create_image: Image_2D depth must be 1 when specified")
		return false
	}
	if desc.format == .Invalid {
		set_validation_error(ctx, "gfx.create_image: format must be valid")
		return false
	}
	if pixel_format_size(desc.format) == 0 {
		set_unsupported_error(ctx, "gfx.create_image: unsupported image format")
		return false
	}
	if desc.mip_count < 0 {
		set_validation_error(ctx, "gfx.create_image: mip_count must be positive when specified")
		return false
	}
	if image_desc_mip_count(desc) > MAX_IMAGE_MIPS {
		set_validation_errorf(ctx, "gfx.create_image: mip_count exceeds public image mip limit (%d)", MAX_IMAGE_MIPS)
		return false
	}
	if desc.array_count < 0 {
		set_validation_error(ctx, "gfx.create_image: array_count must be positive when specified")
		return false
	}
	if desc.sample_count < 0 {
		set_validation_error(ctx, "gfx.create_image: sample_count must be positive when specified")
		return false
	}
	if !validate_image_usage(ctx, desc.usage) {
		return false
	}

	has_depth := .Depth_Stencil_Attachment in desc.usage
	has_storage := .Storage_Image in desc.usage
	has_color := .Color_Attachment in desc.usage
	has_dynamic := image_usage_has_dynamic_update(desc.usage)
	has_immutable := .Immutable in desc.usage
	has_mip_data := image_desc_has_mip_data(desc)
	if has_depth && !pixel_format_is_depth(desc.format) {
		set_validation_error(ctx, "gfx.create_image: depth-stencil images require a depth format")
		return false
	}
	if !has_depth && !pixel_format_is_color(desc.format) {
		set_validation_error(ctx, "gfx.create_image: color images require a color format")
		return false
	}

	if !validate_optional_range(ctx, "gfx.create_image", "data", desc.data) {
		return false
	}
	for mip_data, mip in desc.mips {
		if mip_data.row_pitch < 0 {
			set_validation_errorf(ctx, "gfx.create_image: mip %d row_pitch must be non-negative", mip)
			return false
		}
		if mip_data.slice_pitch < 0 {
			set_validation_errorf(ctx, "gfx.create_image: mip %d slice_pitch must be non-negative", mip)
			return false
		}
		if !validate_optional_range(ctx, "gfx.create_image", "mip data", mip_data.data) {
			return false
		}
		if range_has_data(mip_data.data) && mip >= int(image_desc_mip_count(desc)) {
			set_validation_errorf(ctx, "gfx.create_image: mip data specified beyond mip_count at mip %d", mip)
			return false
		}
	}

	mip_count := image_desc_mip_count(desc)
	if mip_count > 1 && !has_dynamic && !(has_immutable && has_mip_data) {
		set_validation_error(ctx, "gfx.create_image: immutable mip chains require explicit mip data")
		return false
	}
	if has_dynamic && range_has_data(desc.data) && mip_count != 1 {
		set_validation_error(ctx, "gfx.create_image: initial dynamic image data only supports one mip level; use update_image for mip chains")
		return false
	}
	if has_dynamic && has_mip_data {
		set_validation_error(ctx, "gfx.create_image: dynamic images do not accept initial mip-chain data; use update_image")
		return false
	}
	if has_color && (range_has_data(desc.data) || has_mip_data) {
		set_validation_error(ctx, "gfx.create_image: color attachment images do not accept initial pixel data yet")
		return false
	}
	if has_storage && (range_has_data(desc.data) || has_mip_data) {
		set_validation_error(ctx, "gfx.create_image: storage images do not accept initial pixel data yet")
		return false
	}
	if has_depth && (range_has_data(desc.data) || has_mip_data) {
		set_validation_error(ctx, "gfx.create_image: depth-stencil images do not accept initial data yet")
		return false
	}
	if has_immutable && !validate_initial_image_data(ctx, desc, mip_count, pixel_format_size(desc.format)) {
		return false
	}
	if has_dynamic && range_has_data(desc.data) {
		if !validate_image_data_range(
			ctx,
			"gfx.create_image",
			"dynamic image initial",
			Image_Subresource_Data{data = desc.data},
			u32(desc.width),
			u32(desc.height),
			pixel_format_size(desc.format),
			"requires pixel data",
		) {
			return false
		}
	}

	return true
}

@(private)
validate_image_usage :: proc(ctx: ^Context, usage: Image_Usage) -> bool {
	if usage == {} {
		set_validation_error(ctx, "gfx.create_image: usage must not be empty")
		return false
	}

	has_texture := .Texture in usage
	has_storage := .Storage_Image in usage
	has_color := .Color_Attachment in usage
	has_depth := .Depth_Stencil_Attachment in usage
	has_immutable := .Immutable in usage
	has_dynamic := image_usage_has_dynamic_update(usage)

	if !has_texture && !has_storage && !has_color && !has_depth {
		set_validation_error(ctx, "gfx.create_image: usage must include Texture, Storage_Image, Color_Attachment, or Depth_Stencil_Attachment")
		return false
	}
	if has_color && has_depth {
		set_validation_error(ctx, "gfx.create_image: usage cannot combine color and depth-stencil attachments")
		return false
	}
	if has_storage && has_depth {
		set_validation_error(ctx, "gfx.create_image: storage images cannot use depth-stencil formats")
		return false
	}
	if has_immutable && (has_storage || has_color || has_depth || has_dynamic) {
		set_validation_error(ctx, "gfx.create_image: immutable images must be texture-only for now")
		return false
	}
	if has_dynamic && !has_texture {
		set_validation_error(ctx, "gfx.create_image: dynamic image updates require Texture usage")
		return false
	}
	if has_dynamic && (has_storage || has_color || has_depth) {
		set_unsupported_error(ctx, "gfx.create_image: dynamic storage or attachment images are not implemented yet")
		return false
	}
	if .Dynamic_Update in usage && .Stream_Update in usage {
		set_validation_error(ctx, "gfx.create_image: usage has conflicting update flags")
		return false
	}

	return true
}

@(private)
validate_initial_image_data :: proc(ctx: ^Context, desc: Image_Desc, mip_count: i32, pixel_size: int) -> bool {
	for mip in 0..<int(mip_count) {
		mip_data := image_mip_data(desc, mip)
		if !range_has_data(mip_data.data) {
			set_validation_errorf(ctx, "gfx.create_image: immutable image mip %d requires initial pixel data", mip)
			return false
		}

		mip_width := mip_dimension(u32(desc.width), u32(mip))
		mip_height := mip_dimension(u32(desc.height), u32(mip))
		row_pitch := image_mip_row_pitch(mip_data, mip_width, pixel_size)
		min_row_pitch := mip_width * u32(pixel_size)
		if row_pitch < min_row_pitch {
			set_validation_errorf(ctx, "gfx.create_image: immutable image mip %d row pitch is too small", mip)
			return false
		}

		required_size := int(row_pitch) * int(mip_height - 1) + int(min_row_pitch)
		if mip_data.slice_pitch > 0 && int(mip_data.slice_pitch) < required_size {
			set_validation_errorf(ctx, "gfx.create_image: immutable image mip %d slice pitch is too small", mip)
			return false
		}
		if mip_data.data.size < required_size {
			set_validation_errorf(ctx, "gfx.create_image: immutable image mip %d data range is too small", mip)
			return false
		}
	}

	return true
}

@(private)
validate_image_update_desc :: proc(ctx: ^Context, desc: Image_Update_Desc) -> bool {
	image_state := query_image_state(ctx, desc.image)
	if !image_state.valid {
		set_invalid_handle_error(ctx, "gfx.update_image: image handle is invalid")
		return false
	}
	if !image_usage_has_dynamic_update(image_state.usage) {
		set_validation_error(ctx, "gfx.update_image: image must use Dynamic_Update or Stream_Update")
		return false
	}
	if image_state.kind != .Image_2D {
		set_unsupported_error(ctx, "gfx.update_image: only Image_2D updates are supported")
		return false
	}
	if image_state.sample_count > 1 {
		set_validation_error(ctx, "gfx.update_image: multisampled images cannot be updated")
		return false
	}
	if !pixel_format_is_color(image_state.format) {
		set_validation_error(ctx, "gfx.update_image: only color images can be updated")
		return false
	}
	if desc.mip_level < 0 || desc.array_layer < 0 {
		set_validation_error(ctx, "gfx.update_image: mip level and array layer must be non-negative")
		return false
	}
	if desc.mip_level >= image_state.mip_count || desc.array_layer >= image_state.array_count {
		set_validation_error(ctx, "gfx.update_image: subresource is out of range")
		return false
	}
	if desc.x < 0 || desc.y < 0 {
		set_validation_error(ctx, "gfx.update_image: x and y must be non-negative")
		return false
	}
	if desc.width < 0 || desc.height < 0 {
		set_validation_error(ctx, "gfx.update_image: width and height must be non-negative")
		return false
	}
	if !validate_optional_range(ctx, "gfx.update_image", "data", desc.data) {
		return false
	}
	if !range_has_data(desc.data) {
		set_validation_error(ctx, "gfx.update_image: data range is empty")
		return false
	}
	if desc.row_pitch < 0 {
		set_validation_error(ctx, "gfx.update_image: row_pitch must be non-negative")
		return false
	}

	mip_width := mip_dimension(u32(image_state.width), u32(desc.mip_level))
	mip_height := mip_dimension(u32(image_state.height), u32(desc.mip_level))
	update_width := u32(desc.width)
	update_height := u32(desc.height)
	if desc.width == 0 {
		update_width = mip_width
	}
	if desc.height == 0 {
		update_height = mip_height
	}

	if int(desc.x) + int(update_width) > int(mip_width) ||
	   int(desc.y) + int(update_height) > int(mip_height) {
		set_validation_error(ctx, "gfx.update_image: update rectangle is out of range")
		return false
	}

	pixel_size := pixel_format_size(image_state.format)
	mip_data := Image_Subresource_Data {
		data = desc.data,
		row_pitch = desc.row_pitch,
	}
	return validate_image_data_range(
		ctx,
		"gfx.update_image",
		"image update",
		mip_data,
		update_width,
		update_height,
		pixel_size,
		"requires pixel data",
	)
}

@(private)
validate_image_resolve_desc :: proc(ctx: ^Context, desc: Image_Resolve_Desc) -> bool {
	source_state := query_image_state(ctx, desc.source)
	destination_state := query_image_state(ctx, desc.destination)
	if !source_state.valid || !destination_state.valid {
		set_validation_error(ctx, "gfx.resolve_image: source or destination image is invalid")
		return false
	}
	if source_state.kind != .Image_2D || destination_state.kind != .Image_2D {
		set_unsupported_error(ctx, "gfx.resolve_image: only Image_2D resolves are supported")
		return false
	}
	if source_state.sample_count <= 1 {
		set_validation_error(ctx, "gfx.resolve_image: source image must be multisampled")
		return false
	}
	if destination_state.sample_count != 1 {
		set_validation_error(ctx, "gfx.resolve_image: destination image must be single-sampled")
		return false
	}
	if !(.Color_Attachment in source_state.usage) || !pixel_format_is_color(source_state.format) {
		set_unsupported_error(ctx, "gfx.resolve_image: only color attachment resolves are supported")
		return false
	}
	if !(.Texture in destination_state.usage) && !(.Color_Attachment in destination_state.usage) {
		set_validation_error(ctx, "gfx.resolve_image: destination image must be a Texture or Color_Attachment")
		return false
	}
	if source_state.format != destination_state.format {
		set_validation_error(ctx, "gfx.resolve_image: source and destination formats must match")
		return false
	}
	if source_state.width != destination_state.width || source_state.height != destination_state.height {
		set_validation_error(ctx, "gfx.resolve_image: source and destination dimensions must match")
		return false
	}
	if source_state.mip_count != 1 || destination_state.mip_count != 1 ||
	   source_state.array_count != 1 || destination_state.array_count != 1 {
		set_unsupported_error(ctx, "gfx.resolve_image: only single-mip single-layer resolves are supported")
		return false
	}

	return true
}

@(private)
validate_image_data_range :: proc(
	ctx: ^Context,
	op: string,
	label: string,
	mip_data: Image_Subresource_Data,
	width, height: u32,
	pixel_size: int,
	missing_data_message: string,
) -> bool {
	if mip_data.row_pitch < 0 {
		set_validation_errorf(ctx, "%s: %s row_pitch must be non-negative", op, label)
		return false
	}
	if mip_data.slice_pitch < 0 {
		set_validation_errorf(ctx, "%s: %s slice_pitch must be non-negative", op, label)
		return false
	}
	if !range_has_data(mip_data.data) {
		set_validation_errorf(ctx, "%s: %s %s", op, label, missing_data_message)
		return false
	}

	row_pitch := image_mip_row_pitch(mip_data, width, pixel_size)
	min_row_pitch := width * u32(pixel_size)
	if row_pitch < min_row_pitch {
		set_validation_errorf(ctx, "%s: %s row pitch is too small", op, label)
		return false
	}

	required_size := image_data_required_size(int(row_pitch), int(min_row_pitch), int(height))
	if mip_data.slice_pitch > 0 && int(mip_data.slice_pitch) < required_size {
		set_validation_errorf(ctx, "%s: %s slice pitch is too small", op, label)
		return false
	}
	if mip_data.data.size < required_size {
		set_validation_errorf(ctx, "%s: %s data range is too small", op, label)
		return false
	}

	return true
}

@(private)
image_desc_mip_count :: proc(desc: Image_Desc) -> i32 {
	if desc.mip_count <= 0 {
		return 1
	}
	return desc.mip_count
}

@(private)
image_desc_array_count :: proc(desc: Image_Desc) -> i32 {
	if desc.array_count <= 0 {
		return 1
	}
	return desc.array_count
}

@(private)
image_desc_sample_count :: proc(desc: Image_Desc) -> i32 {
	if desc.sample_count <= 0 {
		return 1
	}
	return desc.sample_count
}

@(private)
image_desc_depth :: proc(desc: Image_Desc) -> i32 {
	if desc.depth <= 0 {
		return 1
	}
	return desc.depth
}

@(private)
image_usage_has_dynamic_update :: proc(usage: Image_Usage) -> bool {
	return .Dynamic_Update in usage || .Stream_Update in usage
}

@(private)
image_desc_has_mip_data :: proc(desc: Image_Desc) -> bool {
	for mip_data in desc.mips {
		if range_has_data(mip_data.data) {
			return true
		}
	}

	return false
}

@(private)
image_mip_data :: proc(desc: Image_Desc, mip: int) -> Image_Subresource_Data {
	mip_data := desc.mips[mip]
	if mip == 0 && !range_has_data(mip_data.data) {
		mip_data.data = desc.data
	}

	return mip_data
}

@(private)
image_mip_row_pitch :: proc(mip_data: Image_Subresource_Data, width: u32, pixel_size: int) -> u32 {
	if mip_data.row_pitch > 0 {
		return u32(mip_data.row_pitch)
	}
	return width * u32(pixel_size)
}

@(private)
image_data_required_size :: proc(row_pitch, min_row_pitch, height: int) -> int {
	if height <= 0 {
		return 0
	}
	return row_pitch * (height - 1) + min_row_pitch
}

@(private)
mip_dimension :: proc(value, mip_level: u32) -> u32 {
	result := value >> mip_level
	if result == 0 {
		return 1
	}
	return result
}

@(private)
pixel_format_size :: proc(format: Pixel_Format) -> int {
	switch format {
	case .RGBA8, .BGRA8:
		return 4
	case .RGBA16F:
		return 8
	case .RGBA32F:
		return 16
	case .R32F, .D24S8, .D32F:
		return 4
	case .Invalid:
		return 0
	}

	return 0
}

@(private)
pixel_format_is_color :: proc(format: Pixel_Format) -> bool {
	switch format {
	case .RGBA8, .BGRA8, .RGBA16F, .RGBA32F, .R32F:
		return true
	case .Invalid, .D24S8, .D32F:
		return false
	}

	return false
}

@(private)
pixel_format_is_depth :: proc(format: Pixel_Format) -> bool {
	switch format {
	case .D24S8, .D32F:
		return true
	case .Invalid, .RGBA8, .BGRA8, .RGBA16F, .RGBA32F, .R32F:
		return false
	}

	return false
}
