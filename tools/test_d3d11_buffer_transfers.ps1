param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_buffer_transfers"
$OutPath = Join-Path $TestDir "d3d11_buffer_transfers.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import app "ape:engine/app"
import gfx "ape:engine/gfx"

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		os.exit(1)
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 320,
		height = 240,
		title = "Ape D3D11 Buffer Transfers",
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
		label = "buffer transfer validation test",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	features := gfx.query_features(&ctx)
	if !features.buffer_updates || !features.buffer_readback {
		fmt.eprintln("unexpected buffer transfer feature flags")
		os.exit(1)
	}

	dynamic_buffer, dynamic_buffer_ok := gfx.create_buffer(&ctx, {
		label = "dynamic transfer buffer",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !dynamic_buffer_ok {
		fmt.eprintln("dynamic buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, dynamic_buffer)

	update_values := [?]u32{10, 20, 30, 40}
	if !gfx.update_buffer(&ctx, {
		buffer = dynamic_buffer,
		data = gfx.range(update_values[:]),
	}) {
		fmt.eprintln("update_buffer failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	read_values: [4]u32
	if !gfx.read_buffer(&ctx, {
		buffer = dynamic_buffer,
		data = gfx.range(read_values[:]),
	}) {
		fmt.eprintln("read_buffer failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	if read_values != update_values {
		fmt.eprintln("read_buffer returned unexpected data")
		os.exit(1)
	}

	immutable_values := [?]u32{1, 2, 3, 4}
	immutable_buffer, immutable_buffer_ok := gfx.create_buffer(&ctx, {
		label = "immutable transfer negative",
		usage = {.Vertex, .Immutable},
		data = gfx.range(immutable_values[:]),
	})
	if !immutable_buffer_ok {
		fmt.eprintln("immutable buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, immutable_buffer)

	if gfx.update_buffer(&ctx, {
		buffer = immutable_buffer,
		data = gfx.range(update_values[:]),
	}) {
		fmt.eprintln("immutable buffer update unexpectedly succeeded")
		os.exit(1)
	}
	expected := "gfx.update_buffer: buffer must use Dynamic_Update or Stream_Update"
	if gfx.last_error(&ctx) != expected {
		fmt.eprintln("immutable update failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	fmt.println("D3D11 buffer transfer validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
