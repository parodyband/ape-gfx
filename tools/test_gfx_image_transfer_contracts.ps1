param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\gfx_image_transfer_contracts"
$OutPath = Join-Path $TestDir "gfx_image_transfer_contracts.exe"
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
	ctx, ok := gfx.init({backend = .Null, label = "image transfer contracts"})
	if !ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	dynamic_image, dynamic_image_ok := gfx.create_image(&ctx, {
		label = "dynamic image",
		usage = {.Texture, .Dynamic_Update},
		width = 4,
		height = 4,
		format = .RGBA8,
	})
	if !dynamic_image_ok || !gfx.image_valid(dynamic_image) {
		fmt.eprintln("dynamic image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, dynamic_image)

	full_pixels: [4 * 4 * 4]u8
	if !gfx.update_image(&ctx, {
		image = dynamic_image,
		data = gfx.range(&full_pixels),
	}) {
		fmt.eprintln("valid full image update failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	partial_pixels: [2 * 2 * 4]u8
	if !gfx.update_image(&ctx, {
		image = dynamic_image,
		x = 1,
		y = 1,
		width = 2,
		height = 2,
		data = gfx.range(&partial_pixels),
	}) {
		fmt.eprintln("valid partial image update failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	if gfx.update_image(&ctx, {
		image = dynamic_image,
		width = 2,
		height = 2,
		row_pitch = -1,
		data = gfx.range(&partial_pixels),
	}) {
		fail("negative row_pitch update unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.update_image: row_pitch must be non-negative")

	if gfx.update_image(&ctx, {
		image = dynamic_image,
		width = 2,
		height = 2,
		row_pitch = 4,
		data = gfx.range(&partial_pixels),
	}) {
		fail("too-small row_pitch update unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.update_image: image update row pitch is too small")

	short_pixels: [12]u8
	if gfx.update_image(&ctx, {
		image = dynamic_image,
		width = 2,
		height = 2,
		data = gfx.range(&short_pixels),
	}) {
		fail("too-small update data unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.update_image: image update data range is too small")

	if gfx.update_image(&ctx, {
		image = dynamic_image,
		x = 3,
		y = 0,
		width = 2,
		height = 1,
		data = gfx.range(&partial_pixels),
	}) {
		fail("out-of-range update rectangle unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.update_image: update rectangle is out of range")

	static_image, static_image_ok := gfx.create_image(&ctx, {
		label = "static texture",
		usage = {.Texture},
		width = 4,
		height = 4,
		format = .RGBA8,
	})
	if !static_image_ok || !gfx.image_valid(static_image) {
		fmt.eprintln("static image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, static_image)

	if gfx.update_image(&ctx, {
		image = static_image,
		data = gfx.range(&full_pixels),
	}) {
		fail("update on non-dynamic image unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.update_image: image must use Dynamic_Update or Stream_Update")

	if gfx.resolve_image(&ctx, {
		source = static_image,
		destination = dynamic_image,
	}) {
		fail("single-sampled resolve unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.resolve_image: source image must be multisampled")

	short_dynamic_image, short_dynamic_image_ok := gfx.create_image(&ctx, {
		label = "short dynamic initial data",
		usage = {.Texture, .Dynamic_Update},
		width = 4,
		height = 4,
		format = .RGBA8,
		data = gfx.range(&short_pixels),
	})
	if short_dynamic_image_ok || gfx.image_valid(short_dynamic_image) {
		fail("short dynamic initial image data unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_image: dynamic image initial data range is too small")

	one_pixel: [4]u8
	slice_pitch_desc := gfx.Image_Desc {
		label = "bad immutable slice pitch",
		usage = {.Texture, .Immutable},
		width = 1,
		height = 1,
		format = .RGBA8,
	}
	slice_pitch_desc.mips[0] = {
		data = gfx.range(&one_pixel),
		slice_pitch = 3,
	}
	slice_pitch_image, slice_pitch_image_ok := gfx.create_image(&ctx, slice_pitch_desc)
	if slice_pitch_image_ok || gfx.image_valid(slice_pitch_image) {
		fail("image with too-small slice pitch unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_image: immutable image mip 0 slice pitch is too small")

	fmt.println("gfx image transfer contract validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
