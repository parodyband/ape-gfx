param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_barrier_validation"
$OutPath = Join-Path $TestDir "d3d11_barrier_validation.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import "core:strings"
import app "ape:app"
import gfx "ape:gfx"

expect_error_contains :: proc(ctx: ^gfx.Context, fragment: string) {
	actual := gfx.last_error(ctx)
	if !strings.contains(actual, fragment) {
		fmt.eprintln("expected error containing: ", fragment)
		fmt.eprintln("actual error:               ", actual)
		os.exit(1)
	}
}

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		os.exit(1)
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 320,
		height = 240,
		title = "Ape D3D11 Barrier Validation",
		no_client_api = true,
	})
	if !window_ok {
		fmt.eprintln("window creation failed")
		os.exit(1)
	}
	defer app.destroy_window(&window)

	fb_width, fb_height := app.framebuffer_size(&window)
	ctx, gfx_ok := gfx.init({
		backend = .D3D11,
		width = fb_width,
		height = fb_height,
		native_window = app.native_window_handle(&window),
		swapchain_format = .BGRA8,
		vsync = false,
		debug = true,
		label = "barrier validation test",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	color_image, color_image_ok := gfx.create_image(&ctx, {
		label = "barrier color image",
		usage = {.Texture, .Color_Attachment},
		width = 16,
		height = 16,
		format = .RGBA8,
	})
	if !color_image_ok {
		fmt.eprintln("color image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, color_image)

	color_attach_view, color_attach_view_ok := gfx.create_view(&ctx, {
		label = "barrier color attachment view",
		color_attachment = {image = color_image},
	})
	if !color_attach_view_ok {
		fmt.eprintln("color attachment view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, color_attach_view)

	storage_image, storage_image_ok := gfx.create_image(&ctx, {
		label = "barrier storage image",
		usage = {.Storage_Image},
		width = 16,
		height = 16,
		format = .RGBA8,
	})
	if !storage_image_ok {
		fmt.eprintln("storage image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_image)

	// 1. Barrier desc shape: invalid image handle is rejected.
	bad_transitions := [?]gfx.Image_Transition {
		{image = gfx.Image_Invalid, from = .Color_Target, to = .Sampled},
	}
	if gfx.barrier(&ctx, {image_transitions = bad_transitions[:]}) {
		fmt.eprintln("barrier with invalid handle unexpectedly succeeded")
		os.exit(1)
	}
	expect_error_contains(&ctx, "invalid image handle")

	// 2. Barrier desc shape: out-of-range subresource range is rejected.
	out_of_range := [?]gfx.Image_Transition {
		{
			image = color_image,
			range = {base_mip = 4, mip_count = 0, base_layer = 0, layer_count = 0, aspect = {}},
			from  = .None,
			to    = .Color_Target,
		},
	}
	if gfx.barrier(&ctx, {image_transitions = out_of_range[:]}) {
		fmt.eprintln("barrier with out-of-range mip unexpectedly succeeded")
		os.exit(1)
	}
	expect_error_contains(&ctx, "base_mip")

	// 3. Buffer barrier: image-only usage rejected.
	storage_buffer, storage_buffer_ok := gfx.create_buffer(&ctx, {
		label = "barrier storage buffer",
		usage = {.Storage},
		size = 64,
	})
	if !storage_buffer_ok {
		fmt.eprintln("storage buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_buffer)

	bad_buffer := [?]gfx.Buffer_Transition {
		{buffer = storage_buffer, from = .None, to = .Color_Target},
	}
	if gfx.barrier(&ctx, {buffer_transitions = bad_buffer[:]}) {
		fmt.eprintln("buffer barrier with image-only usage unexpectedly succeeded")
		os.exit(1)
	}
	expect_error_contains(&ctx, "is not a legal buffer usage")

	// 4. Storage_Read_Write is legal for both storage images and buffers.
	storage_read_write_images := [?]gfx.Image_Transition {
		{image = storage_image, from = .None, to = .Storage_Read_Write},
	}
	if !gfx.barrier(&ctx, {image_transitions = storage_read_write_images[:]}) {
		fmt.eprintln("Storage_Read_Write image barrier failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	storage_read_write_buffers := [?]gfx.Buffer_Transition {
		{buffer = storage_buffer, from = .None, to = .Storage_Read_Write},
	}
	if !gfx.barrier(&ctx, {buffer_transitions = storage_read_write_buffers[:]}) {
		fmt.eprintln("Storage_Read_Write buffer barrier failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	// 5. Wrong-barrier scenario: a render pass declares the image as
	//    Color_Target; a follow-up barrier mis-states the prior usage.
	pass: gfx.Pass_Desc
	pass.color_attachments[0] = color_attach_view
	pass.action = gfx.default_pass_action()
	if !gfx.begin_pass(&ctx, pass) {
		fmt.eprintln("begin_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if !gfx.end_pass(&ctx) {
		fmt.eprintln("end_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	wrong_from := [?]gfx.Image_Transition {
		{image = color_image, from = .Sampled, to = .Sampled},
	}
	if gfx.barrier(&ctx, {image_transitions = wrong_from[:]}) {
		fmt.eprintln("wrong-barrier from=Sampled unexpectedly succeeded")
		os.exit(1)
	}
	expect_error_contains(&ctx, "wrong barrier")
	expect_error_contains(&ctx, "Color_Target")

	// 6. Missing-barrier scenario at apply_bindings: the image is currently
	//    Color_Target; reusing it as a color attachment in a fresh pass is
	//    fine (Color_Target -> Color_Target), but moving it to Sampled via
	//    apply_bindings without an intervening barrier is not.
	correct_to_sampled := [?]gfx.Image_Transition {
		{image = color_image, from = .Color_Target, to = .Sampled},
	}
	if !gfx.barrier(&ctx, {image_transitions = correct_to_sampled[:]}) {
		fmt.eprintln("Color_Target -> Sampled barrier failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	// Now image is recorded as Sampled. Re-binding it as a color attachment
	// without a barrier back to Color_Target must be flagged as a missing
	// barrier by begin_pass.
	missing_pass: gfx.Pass_Desc
	missing_pass.color_attachments[0] = color_attach_view
	missing_pass.action = gfx.default_pass_action()
	if gfx.begin_pass(&ctx, missing_pass) {
		fmt.eprintln("begin_pass without back-to-Color_Target barrier unexpectedly succeeded")
		gfx.end_pass(&ctx)
		os.exit(1)
	}
	expect_error_contains(&ctx, "missing barrier")
	expect_error_contains(&ctx, "Sampled")

	// 7. Frame boundary clears the tracker; the same begin_pass succeeds
	//    once we hit commit (no in-flight pass; commit is legal here).
	if !gfx.commit(&ctx) {
		fmt.eprintln("commit failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if !gfx.begin_pass(&ctx, missing_pass) {
		fmt.eprintln("begin_pass after frame boundary failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if !gfx.end_pass(&ctx) {
		fmt.eprintln("end_pass after frame boundary failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	// 8. Barrier between passes is the legal path: declare Color_Target ->
	//    Sampled, then re-declaring the same transition should fail because
	//    the resource is now Sampled.
	if !gfx.barrier(&ctx, {image_transitions = correct_to_sampled[:]}) {
		fmt.eprintln("legal Color_Target -> Sampled failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if gfx.barrier(&ctx, {image_transitions = correct_to_sampled[:]}) {
		fmt.eprintln("repeat Color_Target -> Sampled unexpectedly succeeded")
		os.exit(1)
	}
	expect_error_contains(&ctx, "wrong barrier")

	fmt.println("D3D11 barrier validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
