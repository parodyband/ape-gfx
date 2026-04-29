param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_storage_views"
$OutPath = Join-Path $TestDir "d3d11_storage_views.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import app "ape:app"
import gfx "ape:gfx"

main :: proc() {
	null_ctx, null_ok := gfx.init({
		backend = .Null,
		width = 1,
		height = 1,
	})
	if !null_ok {
		fmt.eprintln("null gfx init failed: ", gfx.last_error(&null_ctx))
		os.exit(1)
	}

	null_storage_buffer, null_storage_buffer_ok := gfx.create_buffer(&null_ctx, {
		label = "null storage buffer",
		usage = {.Storage},
		size = 16,
	})
	if !null_storage_buffer_ok {
		fmt.eprintln("null storage buffer creation failed: ", gfx.last_error(&null_ctx))
		os.exit(1)
	}

	null_storage_view, null_storage_view_ok := gfx.create_view(&null_ctx, {
		label = "null storage buffer view",
		storage_buffer = {
			buffer = null_storage_buffer,
		},
	})
	if null_storage_view_ok || gfx.view_valid(null_storage_view) {
		fmt.eprintln("null storage buffer view unexpectedly succeeded")
		os.exit(1)
	}
	expected_null_storage_error := "gfx.create_view: backend does not support storage buffer views"
	if gfx.last_error(&null_ctx) != expected_null_storage_error {
		fmt.eprintln("null storage buffer view failed with unexpected error: ", gfx.last_error(&null_ctx))
		os.exit(1)
	}
	gfx.shutdown(&null_ctx)

	if !app.init() {
		fmt.eprintln("app init failed")
		os.exit(1)
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 320,
		height = 240,
		title = "Ape D3D11 Storage Views",
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
		label = "storage view validation test",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	features := gfx.query_features(&ctx)
	if !features.storage_images || !features.storage_buffers || !features.compute {
		fmt.eprintln("unexpected storage feature flags")
		os.exit(1)
	}

	storage_image, storage_image_ok := gfx.create_image(&ctx, {
		label = "storage image",
		usage = {.Texture, .Storage_Image},
		width = 32,
		height = 16,
		format = .RGBA32F,
	})
	if !storage_image_ok {
		fmt.eprintln("storage image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_image)

	storage_image_view, storage_image_view_ok := gfx.create_view(&ctx, {
		label = "storage image view",
		storage_image = {
			image = storage_image,
			mip_level = 0,
		},
	})
	if !storage_image_view_ok {
		fmt.eprintln("storage image view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_image_view)

	image_view_state := gfx.query_view_state(&ctx, storage_image_view)
	if !image_view_state.valid ||
	   image_view_state.kind != .Storage_Image ||
	   image_view_state.image != storage_image ||
	   image_view_state.width != 32 ||
	   image_view_state.height != 16 ||
	   image_view_state.format != .RGBA32F {
		fmt.eprintln("unexpected storage image view state")
		os.exit(1)
	}

	sampled_only_image, sampled_only_image_ok := gfx.create_image(&ctx, {
		label = "sampled only image",
		usage = {.Texture},
		width = 8,
		height = 8,
		format = .RGBA8,
	})
	if !sampled_only_image_ok {
		fmt.eprintln("sampled only image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, sampled_only_image)

	invalid_storage_image_view, invalid_storage_image_view_ok := gfx.create_view(&ctx, {
		label = "invalid storage image usage",
		storage_image = {
			image = sampled_only_image,
		},
	})
	if invalid_storage_image_view_ok || gfx.view_valid(invalid_storage_image_view) {
		fmt.eprintln("non-storage image view unexpectedly succeeded")
		os.exit(1)
	}
	expected_image_usage_error := "gfx.create_view: storage image views require a storage-capable image"
	if gfx.last_error(&ctx) != expected_image_usage_error {
		fmt.eprintln("non-storage image view failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	storage_buffer, storage_buffer_ok := gfx.create_buffer(&ctx, {
		label = "storage buffer",
		usage = {.Storage},
		size = 256,
	})
	if !storage_buffer_ok {
		fmt.eprintln("storage buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_buffer)

	invalid_storage_buffer, invalid_storage_buffer_ok := gfx.create_buffer(&ctx, {
		label = "invalid dynamic storage buffer",
		usage = {.Storage, .Dynamic_Update},
		size = 64,
	})
	if invalid_storage_buffer_ok || gfx.buffer_valid(invalid_storage_buffer) {
		fmt.eprintln("dynamic storage buffer unexpectedly succeeded")
		os.exit(1)
	}
	expected_storage_buffer_flags_error := "gfx.create_buffer: storage buffers are GPU-only for now and must not use update/lifetime flags"
	if gfx.last_error(&ctx) != expected_storage_buffer_flags_error {
		fmt.eprintln("dynamic storage buffer failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	storage_buffer_view, storage_buffer_view_ok := gfx.create_view(&ctx, {
		label = "storage buffer view",
		storage_buffer = {
			buffer = storage_buffer,
			offset = 16,
			size = 64,
		},
	})
	if !storage_buffer_view_ok {
		fmt.eprintln("storage buffer view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_buffer_view)

	buffer_view_state := gfx.query_view_state(&ctx, storage_buffer_view)
	if !buffer_view_state.valid ||
	   buffer_view_state.kind != .Storage_Buffer ||
	   buffer_view_state.buffer != storage_buffer ||
	   buffer_view_state.offset != 16 ||
	   buffer_view_state.size != 64 {
		fmt.eprintln("unexpected storage buffer view state")
		os.exit(1)
	}

	vertex_data := [?]f32{0, 1, 2, 3}
	vertex_buffer, vertex_buffer_ok := gfx.create_buffer(&ctx, {
		label = "not storage",
		usage = {.Vertex, .Immutable},
		data = gfx.range(vertex_data[:]),
	})
	if !vertex_buffer_ok {
		fmt.eprintln("vertex buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, vertex_buffer)

	invalid_usage_view, invalid_usage_view_ok := gfx.create_view(&ctx, {
		label = "invalid storage buffer usage",
		storage_buffer = {
			buffer = vertex_buffer,
			size = 16,
		},
	})
	if invalid_usage_view_ok || gfx.view_valid(invalid_usage_view) {
		fmt.eprintln("non-storage buffer view unexpectedly succeeded")
		os.exit(1)
	}
	expected_usage_error := "gfx.create_view: storage buffer views require a storage-capable buffer"
	if gfx.last_error(&ctx) != expected_usage_error {
		fmt.eprintln("non-storage buffer view failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	invalid_alignment_view, invalid_alignment_view_ok := gfx.create_view(&ctx, {
		label = "invalid storage buffer alignment",
		storage_buffer = {
			buffer = storage_buffer,
			offset = 2,
			size = 64,
		},
	})
	if invalid_alignment_view_ok || gfx.view_valid(invalid_alignment_view) {
		fmt.eprintln("unaligned storage buffer view unexpectedly succeeded")
		os.exit(1)
	}
	expected_alignment_error := "gfx.create_view: raw storage buffer view offset and size must be 4-byte aligned"
	if gfx.last_error(&ctx) != expected_alignment_error {
		fmt.eprintln("unaligned storage buffer view failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	fmt.println("D3D11 storage view validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
