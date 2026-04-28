param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_backend_limits"
$OutPath = Join-Path $TestDir "d3d11_backend_limits.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import app "ape:engine/app"
import gfx "ape:engine/gfx"

fail :: proc(message: string) {
	fmt.eprintln(message)
	os.exit(1)
}

expect_error :: proc(ctx: ^gfx.Context, expected: string) {
	actual := gfx.last_error(ctx)
	if actual != expected {
		fmt.eprintln("expected error: ", expected)
		fmt.eprintln("actual error:   ", actual)
		os.exit(1)
	}
}

main :: proc() {
	if !app.init() {
		fail("app init failed")
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 320,
		height = 240,
		title = "Ape D3D11 Backend Limits",
		no_client_api = true,
	})
	if !window_ok {
		fail("window creation failed")
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
		label = "backend limits validation test",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	api_limits := gfx.query_limits()
	if api_limits.max_color_attachments != gfx.MAX_COLOR_ATTACHMENTS {
		fail("public API limits did not report max_color_attachments")
	}

	limits := gfx.query_backend_limits(&ctx)
	if limits.max_image_dimension_2d <= 0 {
		fail("backend did not report a 2D image dimension limit")
	}
	if limits.max_image_array_layers <= 0 {
		fail("backend did not report an image array layer limit")
	}
	if limits.max_image_sample_count <= 0 {
		fail("backend did not report a sample count limit")
	}
	if limits.max_compute_thread_groups_per_dimension <= 0 {
		fail("backend did not report a compute dispatch group limit")
	}

	too_wide, too_wide_ok := gfx.create_image(&ctx, {
		label = "too wide",
		usage = {.Texture},
		width = i32(limits.max_image_dimension_2d + 1),
		height = 1,
		format = .RGBA8,
	})
	if too_wide_ok || gfx.image_valid(too_wide) {
		fail("oversized image width unexpectedly succeeded")
	}
	expect_error(&ctx, fmt.tprintf("gfx.create_image: width exceeds backend 2D image dimension limit (%d)", limits.max_image_dimension_2d))

	too_many_layers, too_many_layers_ok := gfx.create_image(&ctx, {
		label = "too many layers",
		usage = {.Texture},
		width = 1,
		height = 1,
		array_count = i32(limits.max_image_array_layers + 1),
		format = .RGBA8,
	})
	if too_many_layers_ok || gfx.image_valid(too_many_layers) {
		fail("oversized image layer count unexpectedly succeeded")
	}
	expect_error(&ctx, fmt.tprintf("gfx.create_image: array_count exceeds backend image array layer limit (%d)", limits.max_image_array_layers))

	too_many_samples, too_many_samples_ok := gfx.create_image(&ctx, {
		label = "too many samples",
		usage = {.Color_Attachment},
		width = 4,
		height = 4,
		sample_count = i32(limits.max_image_sample_count + 1),
		format = .RGBA8,
	})
	if too_many_samples_ok || gfx.image_valid(too_many_samples) {
		fail("oversized sample count unexpectedly succeeded")
	}
	expect_error(&ctx, fmt.tprintf("gfx.create_image: sample_count exceeds backend sample count limit (%d)", limits.max_image_sample_count))

	fmt.println("d3d11 backend limit validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
