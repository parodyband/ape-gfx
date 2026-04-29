param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_invalid_uniform_size"
$OutPath = Join-Path $TestDir "d3d11_invalid_uniform_size.exe"
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
		title = "Ape D3D11 Invalid Uniform Size",
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
		label = "invalid uniform size test",
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

	group_layout, group_layout_ok := gfx.create_binding_group_layout(&ctx, triangle_shader.binding_group_layout_desc(triangle_shader.GROUP_0, label = "triangle bindings"))
	if !group_layout_ok {
		fmt.eprintln("binding group layout creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, group_layout)

	pipeline_layout, pipeline_layout_ok := gfx.create_pipeline_layout(&ctx, {
		label = "triangle pipeline layout",
		group_layouts = {
			triangle_shader.GROUP_0 = group_layout,
		},
	})
	if !pipeline_layout_ok {
		fmt.eprintln("pipeline layout creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, pipeline_layout)

	pipeline, pipeline_ok := gfx.create_pipeline(&ctx, {
		label = "invalid uniform size pipeline",
		shader = shader,
		pipeline_layout = pipeline_layout,
		primitive_type = .Triangles,
		index_type = .None,
		layout = triangle_shader.layout_desc(),
	})
	if !pipeline_ok {
		fmt.eprintln("pipeline creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, pipeline)

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

	valid_uniform := triangle_shader.FrameUniforms{}
	if gfx.apply_uniform(&ctx, triangle_shader.GROUP_0, triangle_shader.UB_FrameUniforms + 1, &valid_uniform) {
		fmt.eprintln("unused uniform slot unexpectedly succeeded")
		os.exit(1)
	}

	expected_unused := "gfx.d3d11: uniform group 0 slot 1 is not used by the current pipeline"
	if gfx.last_error(&ctx) != expected_unused {
		fmt.eprintln("unused uniform slot failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	wrong_uniform_size := [3]f32{}
	if gfx.apply_uniform(&ctx, triangle_shader.GROUP_0, triangle_shader.UB_FrameUniforms, &wrong_uniform_size) {
		fmt.eprintln("invalid uniform size unexpectedly succeeded")
		os.exit(1)
	}

	expected := "gfx.d3d11: uniform group 0 slot 0 data size 12 does not match reflected size 16"
	if gfx.last_error(&ctx) != expected {
		fmt.eprintln("invalid uniform size failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	fmt.println("Invalid D3D11 uniform size failed as expected")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
