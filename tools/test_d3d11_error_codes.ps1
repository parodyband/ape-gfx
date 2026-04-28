param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_error_codes"
$OutPath = Join-Path $TestDir "d3d11_error_codes.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import app "ape:engine/app"
import gfx "ape:engine/gfx"

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
	if !app.init() {
		fmt.eprintln("app init failed")
		os.exit(1)
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 320,
		height = 240,
		title = "Ape D3D11 Error Codes",
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
		label = "d3d11 error code validation",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	invalid_bytecode := [?]u8{0, 1, 2, 3}
	shader_desc: gfx.Shader_Desc
	shader_desc.label = "invalid backend bytecode"
	shader_desc.stages[int(gfx.Shader_Stage.Vertex)] = {
		stage = .Vertex,
		entry = "vs_main",
		bytecode = gfx.range(invalid_bytecode[:]),
	}
	shader_desc.stages[int(gfx.Shader_Stage.Fragment)] = {
		stage = .Fragment,
		entry = "fs_main",
		bytecode = gfx.range(invalid_bytecode[:]),
	}

	shader, shader_ok := gfx.create_shader(&ctx, shader_desc)
	if shader_ok || gfx.shader_valid(shader) {
		fmt.eprintln("invalid D3D11 bytecode unexpectedly created a shader")
		gfx.destroy(&ctx, shader)
		os.exit(1)
	}
	expect_error_info(&ctx, .Backend, "gfx.d3d11: CreateVertexShader failed")

	fmt.println("D3D11 backend error code validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
