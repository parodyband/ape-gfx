param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_invalid_pipeline_layout"
$OutPath = Join-Path $TestDir "d3d11_invalid_pipeline_layout.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

& (Join-Path $PSScriptRoot "compile_shaders.ps1") -ShaderName "triangle"

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import app "ape:app"
import gfx "ape:gfx"
import shader_assets "ape:shader"
import triangle_shader "ape:assets/shaders/generated/triangle"

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		os.exit(1)
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 320,
		height = 240,
		title = "Ape D3D11 Invalid Pipeline Layout",
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
		label = "invalid pipeline layout test",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	shader_package, package_ok := shader_assets.load("build/shaders/triangle.ashader")
	if !package_ok {
		fmt.eprintln("failed to read triangle shader package")
		os.exit(1)
	}
	defer shader_assets.unload(&shader_package)

	shader_desc, shader_desc_ok := shader_assets.shader_desc(&shader_package, .D3D11_DXBC, "triangle shader")
	if !shader_desc_ok {
		fmt.eprintln("failed to build triangle shader desc")
		os.exit(1)
	}

	shader, shader_ok := gfx.create_shader(&ctx, shader_desc)
	if !shader_ok {
		fmt.eprintln("shader creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, shader)

	layout := triangle_shader.layout_desc()
	layout.attrs[1].format = .Float32x2

	pipeline, pipeline_ok := gfx.create_pipeline(&ctx, {
		label = "invalid pipeline",
		shader = shader,
		primitive_type = .Triangles,
		index_type = .None,
		layout = layout,
	})
	if pipeline_ok || gfx.pipeline_valid(pipeline) {
		fmt.eprintln("invalid pipeline layout unexpectedly succeeded")
		gfx.destroy(&ctx, pipeline)
		os.exit(1)
	}

	expected := "gfx.create_pipeline: pipeline vertex input COLOR0 format does not match shader reflection"
	if gfx.last_error(&ctx) != expected {
		fmt.eprintln("invalid pipeline layout failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	fmt.println("Invalid D3D11 pipeline layout failed as expected")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
