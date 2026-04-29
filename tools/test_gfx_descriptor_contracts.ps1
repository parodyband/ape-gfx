param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\gfx_descriptor_contracts"
$OutPath = Join-Path $TestDir "gfx_descriptor_contracts.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import gfx "ape:gfx"

fail :: proc(message: string) {
	fmt.eprintln(message)
	os.exit(1)
}

expect_error_info :: proc(ctx: ^gfx.Context, expected_code: gfx.Error_Code, expected_message: string) {
	info := gfx.last_error_info(ctx)
	if info.code != expected_code || info.message != expected_message {
		fmt.eprintln("expected error code: ", expected_code)
		fmt.eprintln("actual error code:   ", info.code)
		fmt.eprintln("expected message:    ", expected_message)
		fmt.eprintln("actual message:      ", info.message)
		os.exit(1)
	}
}

main :: proc() {
	zero_ctx, zero_ctx_ok := gfx.init({})
	if !zero_ctx_ok {
		fmt.eprintln("zero Desc init failed: ", gfx.last_error(&zero_ctx))
		os.exit(1)
	}
	if gfx.query_features(&zero_ctx).backend != .Null {
		fail("zero Desc did not resolve to the null backend")
	}
	gfx.shutdown(&zero_ctx)

	negative_size_ctx, negative_size_ok := gfx.init({
		backend = .Null,
		width = -1,
		height = 1,
	})
	if negative_size_ok {
		fail("negative Desc dimensions unexpectedly succeeded")
	}
	expect_error_info(&negative_size_ctx, .Validation, "gfx.init: width and height must be non-negative")

	vulkan_ctx, vulkan_ok := gfx.init({backend = .Vulkan})
	if vulkan_ok {
		fail("Vulkan Desc unexpectedly succeeded")
	}
	expect_error_info(&vulkan_ctx, .Unsupported, "gfx.vulkan: backend scaffold exists, instance/device creation is not implemented yet")

	d3d11_without_window_ctx, d3d11_without_window_ok := gfx.init({
		backend = .D3D11,
		width = 1,
		height = 1,
		swapchain_format = .BGRA8,
	})
	if d3d11_without_window_ok {
		fail("D3D11 Desc without native_window unexpectedly succeeded")
	}
	expect_error_info(&d3d11_without_window_ctx, .Validation, "gfx.d3d11: native_window is required")

	ctx, ok := gfx.init({backend = .Null, label = "descriptor contracts"})
	if !ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	vertex_data := [?]f32{0, 1, 2, 3}
	vertex_buffer, vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "inferred immutable vertex data",
		usage = {.Vertex, .Immutable},
		data = gfx.range(vertex_data[:]),
	})
	if !vertex_buffer_ok || !gfx.buffer_valid(vertex_buffer) {
		fmt.eprintln("valid inferred buffer failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, vertex_buffer)

	vertex_state := gfx.query_buffer_state(&ctx, vertex_buffer)
	if !vertex_state.valid || vertex_state.size != size_of(type_of(vertex_data)) {
		fail("valid inferred buffer did not report expected state")
	}

	invalid_buffer, invalid_buffer_ok := gfx.create_buffer(&ctx, {
		label = "missing usage",
		size = 16,
	})
	if invalid_buffer_ok || gfx.buffer_valid(invalid_buffer) {
		fail("buffer without usage unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_buffer: usage must include at least one role flag")

	missing_lifetime, missing_lifetime_ok := gfx.create_buffer(&ctx, {
		label = "missing lifetime",
		usage = {.Vertex},
		size = 16,
	})
	if missing_lifetime_ok || gfx.buffer_valid(missing_lifetime) {
		fail("buffer without update/lifetime flag unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_buffer: usage must include Immutable, Dynamic_Update, or Stream_Update")

	immutable_without_data, immutable_without_data_ok := gfx.create_buffer(&ctx, {
		label = "immutable missing data",
		usage = {.Vertex, .Immutable},
		size = 16,
	})
	if immutable_without_data_ok || gfx.buffer_valid(immutable_without_data) {
		fail("immutable buffer without initial data unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_buffer: immutable buffers require initial data")

	raw_storage_bad_size, raw_storage_bad_size_ok := gfx.create_buffer(&ctx, {
		label = "bad raw storage size",
		usage = {.Storage},
		size = 10,
	})
	if raw_storage_bad_size_ok || gfx.buffer_valid(raw_storage_bad_size) {
		fail("unaligned raw storage buffer unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_buffer: raw storage buffer size must be 4-byte aligned")

	short_data := [?]u32{1, 2}
	short_data_buffer, short_data_buffer_ok := gfx.create_buffer(&ctx, {
		label = "short initial data",
		usage = {.Vertex, .Immutable},
		size = 16,
		data = gfx.range(short_data[:]),
	})
	if short_data_buffer_ok || gfx.buffer_valid(short_data_buffer) {
		fail("undersized initial data unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_buffer: initial data range must cover Buffer_Desc.size")

	texture_image, texture_image_ok := gfx.create_image(&ctx, {
		label = "sampled texture",
		usage = {.Texture},
		width = 16,
		height = 8,
		format = .RGBA8,
	})
	if !texture_image_ok || !gfx.image_valid(texture_image) {
		fmt.eprintln("valid texture image failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, texture_image)

	texture_state := gfx.query_image_state(&ctx, texture_image)
	if !texture_state.valid || texture_state.kind != .Image_2D || texture_state.mip_count != 1 || texture_state.array_count != 1 || texture_state.sample_count != 1 {
		fail("valid texture image did not report defaulted image state")
	}

	// AAA roadmap item 34: zero counts must default to 1, and explicit 1 must
	// match. Verify all three count fields (mips / layers / samples) for the
	// 0 / 1 / >1 cases.
	explicit_one_image, explicit_one_image_ok := gfx.create_image(&ctx, {
		label = "explicit one counts",
		usage = {.Texture},
		width = 16, height = 8,
		mip_count = 1, array_count = 1, sample_count = 1,
		format = .RGBA8,
	})
	if !explicit_one_image_ok || !gfx.image_valid(explicit_one_image) {
		fmt.eprintln("explicit-one image failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, explicit_one_image)
	explicit_one_state := gfx.query_image_state(&ctx, explicit_one_image)
	if explicit_one_state.mip_count != 1 || explicit_one_state.array_count != 1 || explicit_one_state.sample_count != 1 {
		fail("explicit-one image did not match the zero-count default state")
	}

	mip_chain_image, mip_chain_image_ok := gfx.create_image(&ctx, {
		label = "mip chain",
		usage = {.Texture, .Dynamic_Update},
		width = 16, height = 16,
		mip_count = 4,
		format = .RGBA8,
	})
	if !mip_chain_image_ok || !gfx.image_valid(mip_chain_image) {
		fmt.eprintln("mip chain image failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, mip_chain_image)
	if gfx.query_image_state(&ctx, mip_chain_image).mip_count != 4 {
		fail("mip chain image did not preserve mip_count")
	}

	array_image, array_image_ok := gfx.create_image(&ctx, {
		label = "array image",
		usage = {.Color_Attachment},
		width = 8, height = 8,
		array_count = 3,
		format = .RGBA8,
	})
	if !array_image_ok || !gfx.image_valid(array_image) {
		fmt.eprintln("array image failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, array_image)
	if gfx.query_image_state(&ctx, array_image).array_count != 3 {
		fail("array image did not preserve array_count")
	}

	if gfx.query_features(&ctx).msaa_render_targets {
		msaa_image, msaa_image_ok := gfx.create_image(&ctx, {
			label = "msaa image",
			usage = {.Color_Attachment},
			width = 8, height = 8,
			sample_count = 4,
			format = .RGBA8,
		})
		if !msaa_image_ok || !gfx.image_valid(msaa_image) {
			fmt.eprintln("msaa image failed: ", gfx.last_error(&ctx))
			os.exit(1)
		}
		defer gfx.destroy(&ctx, msaa_image)
		if gfx.query_image_state(&ctx, msaa_image).sample_count != 4 {
			fail("msaa image did not preserve sample_count")
		}
	}

	invalid_usage_image, invalid_usage_image_ok := gfx.create_image(&ctx, {
		label = "missing image usage",
		width = 1,
		height = 1,
		format = .RGBA8,
	})
	if invalid_usage_image_ok || gfx.image_valid(invalid_usage_image) {
		fail("image without usage unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_image: usage must not be empty")

	color_depth_image, color_depth_image_ok := gfx.create_image(&ctx, {
		label = "color depth conflict",
		usage = {.Color_Attachment, .Depth_Stencil_Attachment},
		width = 1,
		height = 1,
		format = .D32F,
	})
	if color_depth_image_ok || gfx.image_valid(color_depth_image) {
		fail("color/depth image conflict unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_image: usage cannot combine color and depth-stencil attachments")

	dynamic_storage_image, dynamic_storage_image_ok := gfx.create_image(&ctx, {
		label = "dynamic storage",
		usage = {.Texture, .Storage_Image, .Dynamic_Update},
		width = 1,
		height = 1,
		format = .RGBA8,
	})
	if dynamic_storage_image_ok || gfx.image_valid(dynamic_storage_image) {
		fail("dynamic storage image unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Unsupported, "gfx.create_image: dynamic storage or attachment images are not implemented yet")

	immutable_image_without_data, immutable_image_without_data_ok := gfx.create_image(&ctx, {
		label = "immutable missing data",
		usage = {.Texture, .Immutable},
		width = 1,
		height = 1,
		format = .RGBA8,
	})
	if immutable_image_without_data_ok || gfx.image_valid(immutable_image_without_data) {
		fail("immutable image without data unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_image: immutable image mip 0 requires initial pixel data")

	negative_row_pitch_pixels := [?]u8{255, 255, 255, 255}
	negative_row_pitch_desc := gfx.Image_Desc {
		label = "negative row pitch",
		usage = {.Texture, .Immutable},
		width = 1,
		height = 1,
		format = .RGBA8,
	}
	negative_row_pitch_desc.mips[0] = {
		data = gfx.range(negative_row_pitch_pixels[:]),
		row_pitch = -1,
	}
	negative_row_pitch_image, negative_row_pitch_image_ok := gfx.create_image(&ctx, negative_row_pitch_desc)
	if negative_row_pitch_image_ok || gfx.image_valid(negative_row_pitch_image) {
		fail("image with negative row pitch unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_image: mip 0 row_pitch must be non-negative")

	sampled_view, sampled_view_ok := gfx.create_view(&ctx, {
		label = "sampled view",
		texture = {image = texture_image},
	})
	if !sampled_view_ok || !gfx.view_valid(sampled_view) {
		fmt.eprintln("valid sampled view failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, sampled_view)

	view_state := gfx.query_view_state(&ctx, sampled_view)
	if !view_state.valid || view_state.kind != .Sampled || view_state.image != texture_image {
		fail("valid sampled view did not report expected state")
	}

	render_target, render_target_ok := gfx.create_render_target(&ctx, {
		label = "color depth render target",
		width = 16,
		height = 8,
		color_format = .RGBA8,
		depth_format = .D32F,
		sampled_color = true,
		sampled_depth = true,
	})
	if !render_target_ok ||
	   !gfx.image_valid(render_target.color_image) ||
	   !gfx.view_valid(render_target.color_attachment) ||
	   !gfx.view_valid(render_target.color_sample) ||
	   !gfx.image_valid(render_target.depth_image) ||
	   !gfx.view_valid(render_target.depth_stencil_attachment) ||
	   !gfx.view_valid(render_target.depth_sample) {
		fmt.eprintln("valid render target failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	color_attachment_state := gfx.query_view_state(&ctx, render_target.color_attachment)
	color_sample_state := gfx.query_view_state(&ctx, render_target.color_sample)
	depth_attachment_state := gfx.query_view_state(&ctx, render_target.depth_stencil_attachment)
	depth_sample_state := gfx.query_view_state(&ctx, render_target.depth_sample)
	if color_attachment_state.kind != .Color_Attachment ||
	   color_sample_state.kind != .Sampled ||
	   depth_attachment_state.kind != .Depth_Stencil_Attachment ||
	   depth_sample_state.kind != .Sampled ||
	   color_sample_state.image != render_target.color_image ||
	   depth_sample_state.image != render_target.depth_image {
		fail("valid render target did not report expected view state")
	}

	pass_desc := gfx.render_target_pass_desc(render_target, "render target pass", gfx.default_pass_action())
	if pass_desc.color_attachments[0] != render_target.color_attachment ||
	   pass_desc.depth_stencil_attachment != render_target.depth_stencil_attachment {
		fail("render_target_pass_desc did not target expected attachment views")
	}

	// AAA roadmap item 35: a zero-init Pass_Action must resolve to the same
	// load/store/clear values as default_pass_action(); a Pass_Action with any
	// field set on a slot opts that slot out of defaulting; a fully-specified
	// action passes through unchanged.
	zero_resolved := gfx.pass_action_with_defaults(gfx.Pass_Action{})
	expected_default := gfx.default_pass_action()
	if zero_resolved != expected_default {
		fail("pass_action_with_defaults({}) did not match default_pass_action()")
	}

	partial_action: gfx.Pass_Action
	partial_action.colors[0].clear_value = gfx.Color{r = 0.25, g = 0.5, b = 0.75, a = 0.25}
	partial_action.depth.clear_value = 0.5
	partial_resolved := gfx.pass_action_with_defaults(partial_action)
	if partial_resolved.colors[0].load_action != .Clear ||
	   partial_resolved.colors[0].store_action != .Store ||
	   partial_resolved.colors[0].clear_value != (gfx.Color{r = 0.25, g = 0.5, b = 0.75, a = 0.25}) {
		fail("pass_action_with_defaults preserved partial color slot incorrectly")
	}
	if partial_resolved.depth.load_action != .Clear ||
	   partial_resolved.depth.store_action != .Store ||
	   partial_resolved.depth.clear_value != 0.5 {
		fail("pass_action_with_defaults preserved partial depth slot incorrectly")
	}
	if partial_resolved.colors[1] != expected_default.colors[1] {
		fail("pass_action_with_defaults did not default an untouched color slot")
	}

	full_action: gfx.Pass_Action
	for i in 0..<gfx.MAX_COLOR_ATTACHMENTS {
		full_action.colors[i] = gfx.Color_Attachment_Action {
			load_action  = .Load,
			store_action = .Dont_Care,
			clear_value  = gfx.Color{r = 0.1, g = 0.2, b = 0.3, a = 0.4},
		}
	}
	full_action.depth = gfx.Depth_Attachment_Action {
		load_action  = .Dont_Care,
		store_action = .Dont_Care,
		clear_value  = 0.25,
	}
	full_action.stencil = gfx.Stencil_Attachment_Action {
		load_action  = .Load,
		store_action = .Dont_Care,
		clear_value  = 7,
	}
	full_resolved := gfx.pass_action_with_defaults(full_action)
	if full_resolved != full_action {
		fail("pass_action_with_defaults mutated a fully-specified action")
	}

	// Drive begin_pass on the swapchain with each shape on the null backend.
	// The null backend accepts any valid action, so success here proves the
	// resolution + validation path agrees on each shape.
	if !gfx.begin_pass(&ctx, gfx.Pass_Desc{label = "zero pass action"}) {
		fail(fmt.tprintf("begin_pass with zero action failed: %s", gfx.last_error(&ctx)))
	}
	if !gfx.end_pass(&ctx) { fail("end_pass after zero action failed") }

	if !gfx.begin_pass(&ctx, gfx.Pass_Desc{label = "partial pass action", action = partial_action}) {
		fail(fmt.tprintf("begin_pass with partial action failed: %s", gfx.last_error(&ctx)))
	}
	if !gfx.end_pass(&ctx) { fail("end_pass after partial action failed") }

	if !gfx.begin_pass(&ctx, gfx.Pass_Desc{label = "full pass action", action = full_action}) {
		fail(fmt.tprintf("begin_pass with full action failed: %s", gfx.last_error(&ctx)))
	}
	if !gfx.end_pass(&ctx) { fail("end_pass after full action failed") }

	gfx.destroy_render_target(&ctx, &render_target)
	if gfx.image_valid(render_target.color_image) ||
	   gfx.view_valid(render_target.color_attachment) ||
	   gfx.view_valid(render_target.color_sample) ||
	   gfx.image_valid(render_target.depth_image) ||
	   gfx.view_valid(render_target.depth_stencil_attachment) ||
	   gfx.view_valid(render_target.depth_sample) {
		fail("destroy_render_target did not clear target handles")
	}

	empty_render_target, empty_render_target_ok := gfx.create_render_target(&ctx, {
		label = "empty render target",
		width = 1,
		height = 1,
	})
	if empty_render_target_ok || gfx.image_valid(empty_render_target.color_image) || gfx.image_valid(empty_render_target.depth_image) {
		fail("render target without formats unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_render_target: color_format or depth_format is required")

	wrong_color_render_target, wrong_color_render_target_ok := gfx.create_render_target(&ctx, {
		label = "wrong color format",
		width = 1,
		height = 1,
		color_format = .D32F,
	})
	if wrong_color_render_target_ok || gfx.image_valid(wrong_color_render_target.color_image) {
		fail("render target with depth format as color unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_render_target: color_format must be a color format")

	sampled_missing_color, sampled_missing_color_ok := gfx.create_render_target(&ctx, {
		label = "sampled missing color",
		width = 1,
		height = 1,
		depth_format = .D32F,
		sampled_color = true,
	})
	if sampled_missing_color_ok || gfx.image_valid(sampled_missing_color.depth_image) {
		fail("render target with sampled_color and no color unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_render_target: sampled_color requires color_format")

	sampled_msaa_render_target, sampled_msaa_render_target_ok := gfx.create_render_target(&ctx, {
		label = "sampled msaa",
		width = 1,
		height = 1,
		sample_count = 4,
		color_format = .RGBA8,
		sampled_color = true,
	})
	if sampled_msaa_render_target_ok || gfx.image_valid(sampled_msaa_render_target.color_image) {
		fail("sampled multisampled render target unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_render_target: sampled_color does not support multisampled targets yet; resolve into a single-sampled texture")

	empty_view, empty_view_ok := gfx.create_view(&ctx, {label = "empty view"})
	if empty_view_ok || gfx.view_valid(empty_view) {
		fail("empty view descriptor unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_view: exactly one view flavor must be specified")

	multi_flavor_view, multi_flavor_view_ok := gfx.create_view(&ctx, {
		label = "multi flavor",
		texture = {image = texture_image},
		color_attachment = {image = texture_image},
	})
	if multi_flavor_view_ok || gfx.view_valid(multi_flavor_view) {
		fail("multi-flavor view descriptor unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_view: exactly one view flavor must be specified")

	attachment_image, attachment_image_ok := gfx.create_image(&ctx, {
		label = "attachment only",
		usage = {.Color_Attachment},
		width = 4,
		height = 4,
		format = .RGBA8,
	})
	if !attachment_image_ok || !gfx.image_valid(attachment_image) {
		fmt.eprintln("attachment image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, attachment_image)

	bad_sampled_view, bad_sampled_view_ok := gfx.create_view(&ctx, {
		label = "bad sampled view",
		texture = {image = attachment_image},
	})
	if bad_sampled_view_ok || gfx.view_valid(bad_sampled_view) {
		fail("sampled view over non-texture image unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_view: sampled views require a Texture image")

	storage_buffer, storage_buffer_ok := gfx.create_buffer(&ctx, {
		label = "null storage buffer",
		usage = {.Storage},
		size = 16,
	})
	if !storage_buffer_ok || !gfx.buffer_valid(storage_buffer) {
		fmt.eprintln("storage buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_buffer)

	null_storage_view, null_storage_view_ok := gfx.create_view(&ctx, {
		label = "unsupported null storage view",
		storage_buffer = {buffer = storage_buffer},
	})
	if null_storage_view_ok || gfx.view_valid(null_storage_view) {
		fail("null storage view unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Unsupported, "gfx.create_view: backend does not support storage buffer views")

	fmt.println("gfx descriptor contract validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
