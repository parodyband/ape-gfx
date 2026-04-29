param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_bindless_reject"
$OutPath = Join-Path $TestDir "d3d11_bindless_reject.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

// AAA roadmap item 29 / APE-25: D3D11 fallback for bindless / runtime
// descriptor arrays. The decision is Policy A — permanent hard reject at
// `create_binding_heap` with a D3D11-specific Unsupported message,
// distinct from the implementation-pending message other backends emit.
// See gfx-bindless-note.md §9.

import "core:fmt"
import "core:os"
import app "ape:app"
import gfx "ape:gfx"

fail :: proc(message: string) {
	fmt.eprintln(message)
	os.exit(1)
}

expect_error_info :: proc(ctx: ^gfx.Context, code: gfx.Error_Code, message: string) {
	info := gfx.last_error_info(ctx)
	if info.code != code || info.message != message {
		fmt.eprintln("expected: ", code, message)
		fmt.eprintln("actual:   ", info.code, info.message)
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
		title = "Ape D3D11 Bindless Reject",
		no_client_api = true,
	})
	if !window_ok {
		fail("window creation failed")
	}
	defer app.destroy_window(&window)

	fb_width, fb_height := app.framebuffer_size(&window)
	ctx, ctx_ok := gfx.init({
		backend = .D3D11,
		width = fb_width,
		height = fb_height,
		native_window = app.native_window_handle(&window),
		swapchain_format = .BGRA8,
		vsync = false,
		debug = true,
		label = "d3d11 bindless reject",
	})
	if !ctx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	// Validation must still run before backend rejection — a malformed desc
	// reports Validation, not Unsupported. This pins the layering.
	if heap, ok := gfx.create_binding_heap(&ctx, gfx.Binding_Heap_Desc{
		label    = "zero capacity",
		capacity = 0,
		view_kind = .Sampled,
		access    = .Read,
	}); ok || u64(heap) != 0 {
		fail("zero-capacity heap unexpectedly succeeded on D3D11")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_binding_heap: capacity must be > 0")

	// Well-shaped sampled-view heap: D3D11 rejects with the permanent,
	// backend-named Unsupported message.
	expected_message := "gfx.create_binding_heap: D3D11 does not support bindless or runtime descriptor arrays (Features.bindless_resource_tables = false); use Binding_Group fixed arrays or pick the Vulkan / D3D12 backend"

	if heap, ok := gfx.create_binding_heap(&ctx, gfx.Binding_Heap_Desc{
		label     = "particle textures",
		capacity  = 4096,
		view_kind = .Sampled,
		access    = .Read,
	}); ok || u64(heap) != 0 {
		fail("sampled-view binding heap unexpectedly succeeded on D3D11")
	}
	expect_error_info(&ctx, .Unsupported, expected_message)

	// Storage-buffer heap shape (a different desc shape; same rejection).
	if heap, ok := gfx.create_binding_heap(&ctx, gfx.Binding_Heap_Desc{
		label                 = "particle storage",
		capacity              = 64,
		view_kind             = .Storage_Buffer,
		access                = .Read_Write,
		storage_buffer_stride = 16,
	}); ok || u64(heap) != 0 {
		fail("storage-buffer binding heap unexpectedly succeeded on D3D11")
	}
	expect_error_info(&ctx, .Unsupported, expected_message)

	// Sampler heap shape.
	if heap, ok := gfx.create_binding_heap(&ctx, gfx.Binding_Heap_Desc{
		label    = "sampler heap",
		capacity = 16,
		samplers = true,
	}); ok || u64(heap) != 0 {
		fail("sampler binding heap unexpectedly succeeded on D3D11")
	}
	expect_error_info(&ctx, .Unsupported, expected_message)

	// `Features.bindless_resource_tables` is part of the public contract —
	// once that field exists. For now we assert the negative through the
	// rejection path above; the field is added when item 28 / a future
	// feature-flag pass lands.

	fmt.println("D3D11 bindless / runtime descriptor heap reject path verified")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
