param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_invalid_view_kind"
$OutPath = Join-Path $TestDir "d3d11_invalid_view_kind.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

& (Join-Path $PSScriptRoot "compile_shaders.ps1") -ShaderName "textured_quad"

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import app "ape:app"
import gfx "ape:gfx"
import shader_assets "ape:shader"
import textured_quad_shader "ape:assets/shaders/generated/textured_quad"

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		os.exit(1)
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 320,
		height = 240,
		title = "Ape D3D11 Invalid View Kind",
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
		label = "invalid view kind test",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	shader_package, package_ok := shader_assets.load("build/shaders/textured_quad.ashader")
	if !package_ok {
		fmt.eprintln("failed to read textured_quad shader package")
		os.exit(1)
	}
	defer shader_assets.unload(&shader_package)

	shader_desc, shader_desc_ok := shader_assets.shader_desc(&shader_package, .D3D11_DXBC, "textured quad shader")
	if !shader_desc_ok {
		fmt.eprintln("failed to build textured_quad shader desc")
		os.exit(1)
	}

	shader, shader_ok := gfx.create_shader(&ctx, shader_desc)
	if !shader_ok {
		fmt.eprintln("shader creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, shader)

	pipeline, pipeline_ok := gfx.create_pipeline(&ctx, {
		label = "invalid view kind pipeline",
		shader = shader,
		primitive_type = .Triangles,
		index_type = .None,
		layout = textured_quad_shader.layout_desc(),
	})
	if !pipeline_ok {
		fmt.eprintln("pipeline creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, pipeline)

	storage_image, storage_image_ok := gfx.create_image(&ctx, {
		label = "wrong view kind image",
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

	storage_view, storage_view_ok := gfx.create_view(&ctx, {
		label = "wrong view kind storage view",
		storage_image = {
			image = storage_image,
		},
	})
	if !storage_view_ok {
		fmt.eprintln("storage image view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_view)

	if !gfx.begin_pass(&ctx, {
		label = "swapchain",
		action = gfx.default_pass_action(),
	}) {
		fmt.eprintln("begin_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.end_pass(&ctx)

	if !gfx.apply_pipeline(&ctx, pipeline) {
		fmt.eprintln("apply_pipeline failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	bindings: gfx.Bindings
	textured_quad_shader.set_view_ape_texture(&bindings, storage_view)
	if gfx.apply_bindings(&ctx, bindings) {
		fmt.eprintln("storage view bound to sampled slot unexpectedly succeeded")
		os.exit(1)
	}

	expected := "gfx.d3d11: resource view slot 0 expects sampled view, got storage image view"
	if gfx.last_error(&ctx) != expected {
		fmt.eprintln("invalid view kind failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	fmt.println("Invalid D3D11 view kind failed as expected")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
