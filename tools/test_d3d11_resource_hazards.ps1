param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_resource_hazards"
$OutPath = Join-Path $TestDir "d3d11_resource_hazards.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import app "ape:app"
import gfx "ape:gfx"

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
		fmt.eprintln("app init failed")
		os.exit(1)
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 320,
		height = 240,
		title = "Ape D3D11 Resource Hazards",
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
		label = "resource hazard validation test",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	color_image, color_image_ok := gfx.create_image(&ctx, {
		label = "hazard color image",
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

	color_view_a, color_view_a_ok := gfx.create_view(&ctx, {
		label = "hazard color view a",
		color_attachment = {
			image = color_image,
		},
	})
	if !color_view_a_ok {
		fmt.eprintln("color view a creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, color_view_a)

	color_view_b, color_view_b_ok := gfx.create_view(&ctx, {
		label = "hazard color view b",
		color_attachment = {
			image = color_image,
		},
	})
	if !color_view_b_ok {
		fmt.eprintln("color view b creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, color_view_b)

	sampled_color_view, sampled_color_view_ok := gfx.create_view(&ctx, {
		label = "hazard sampled color",
		texture = {
			image = color_image,
		},
	})
	if !sampled_color_view_ok {
		fmt.eprintln("sampled color view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, sampled_color_view)

	if gfx.resolve_image(&ctx, {source = color_image, destination = color_image}) {
		fmt.eprintln("single-sampled resolve unexpectedly succeeded")
		os.exit(1)
	}
	expect_error(&ctx, "gfx.resolve_image: source image must be multisampled")

	alias_pass: gfx.Pass_Desc
	alias_pass.color_attachments[0] = color_view_a
	alias_pass.color_attachments[1] = color_view_b
	alias_pass.action = gfx.default_pass_action()
	if gfx.begin_pass(&ctx, alias_pass) {
		fmt.eprintln("aliased color attachment pass unexpectedly succeeded")
		gfx.end_pass(&ctx)
		os.exit(1)
	}
	expect_error(&ctx, "gfx.begin_pass: color attachment slots 0 and 1 alias the same image")

	sparse_pass: gfx.Pass_Desc
	sparse_pass.color_attachments[1] = color_view_a
	sparse_pass.action = gfx.default_pass_action()
	if gfx.begin_pass(&ctx, sparse_pass) {
		fmt.eprintln("sparse color attachment pass unexpectedly succeeded")
		gfx.end_pass(&ctx)
		os.exit(1)
	}
	expect_error(&ctx, "gfx.begin_pass: color attachments must be contiguous from slot 0; slot 0 is missing")

	pass: gfx.Pass_Desc
	pass.color_attachments[0] = color_view_a
	pass.action = gfx.default_pass_action()
	if !gfx.begin_pass(&ctx, pass) {
		fmt.eprintln("begin_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	bindings: gfx.Bindings
	bindings.views[0] = sampled_color_view
	if gfx.apply_bindings(&ctx, bindings) {
		fmt.eprintln("sampling active color attachment unexpectedly succeeded")
		os.exit(1)
	}
	expect_error(&ctx, "gfx.apply_bindings: resource view slot 0 aliases an active pass attachment")

	read_buffer, read_buffer_ok := gfx.create_buffer(&ctx, {
		label = "read during pass buffer",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !read_buffer_ok {
		fmt.eprintln("read buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, read_buffer)

	readback: [1]u32
	if gfx.read_buffer(&ctx, {
		buffer = read_buffer,
		data = gfx.range(readback[:]),
	}) {
		fmt.eprintln("read_buffer during pass unexpectedly succeeded")
		os.exit(1)
	}
	expect_error(&ctx, "gfx.read_buffer: cannot transfer buffer data while a pass is in progress")

	if !gfx.end_pass(&ctx) {
		fmt.eprintln("end_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	storage_image, storage_image_ok := gfx.create_image(&ctx, {
		label = "storage image read write hazard",
		usage = {.Texture, .Storage_Image},
		width = 16,
		height = 16,
		format = .RGBA32F,
	})
	if !storage_image_ok {
		fmt.eprintln("storage image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_image)

	storage_sampled_view, storage_sampled_view_ok := gfx.create_view(&ctx, {
		label = "storage image sampled view",
		texture = {
			image = storage_image,
		},
	})
	if !storage_sampled_view_ok {
		fmt.eprintln("storage sampled view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_sampled_view)

	storage_write_view, storage_write_view_ok := gfx.create_view(&ctx, {
		label = "storage image write view",
		storage_image = {
			image = storage_image,
		},
	})
	if !storage_write_view_ok {
		fmt.eprintln("storage write view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_write_view)

	if !gfx.begin_compute_pass(&ctx, {label = "compute image hazard"}) {
		fmt.eprintln("begin_compute_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	compute_bindings: gfx.Bindings
	compute_bindings.views[0] = storage_sampled_view
	compute_bindings.views[1] = storage_write_view
	if gfx.apply_bindings(&ctx, compute_bindings) {
		fmt.eprintln("compute read/write image hazard unexpectedly succeeded")
		os.exit(1)
	}
	expect_error(&ctx, "gfx.apply_bindings: resource view slot 1 writes a resource read by slot 0")

	if !gfx.end_compute_pass(&ctx) {
		fmt.eprintln("end_compute_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	storage_buffer, storage_buffer_ok := gfx.create_buffer(&ctx, {
		label = "storage buffer write hazard",
		usage = {.Storage},
		size = 64,
	})
	if !storage_buffer_ok {
		fmt.eprintln("storage buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_buffer)

	storage_buffer_view_a, storage_buffer_view_a_ok := gfx.create_view(&ctx, {
		label = "storage buffer view a",
		storage_buffer = {
			buffer = storage_buffer,
			offset = 0,
			size = 32,
		},
	})
	if !storage_buffer_view_a_ok {
		fmt.eprintln("storage buffer view a creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_buffer_view_a)

	storage_buffer_view_b, storage_buffer_view_b_ok := gfx.create_view(&ctx, {
		label = "storage buffer view b",
		storage_buffer = {
			buffer = storage_buffer,
			offset = 16,
			size = 32,
		},
	})
	if !storage_buffer_view_b_ok {
		fmt.eprintln("storage buffer view b creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_buffer_view_b)

	if !gfx.begin_compute_pass(&ctx, {label = "compute buffer hazard"}) {
		fmt.eprintln("begin_compute_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	buffer_bindings: gfx.Bindings
	buffer_bindings.views[0] = storage_buffer_view_a
	buffer_bindings.views[1] = storage_buffer_view_b
	if gfx.apply_bindings(&ctx, buffer_bindings) {
		fmt.eprintln("compute write/write buffer hazard unexpectedly succeeded")
		os.exit(1)
	}
	expect_error(&ctx, "gfx.apply_bindings: resource view slots 0 and 1 write the same resource")

	if !gfx.end_compute_pass(&ctx) {
		fmt.eprintln("end_compute_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	fmt.println("D3D11 resource hazard validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
