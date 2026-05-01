param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d12_uniform_upload_lifetime"
$ShaderPath = Join-Path $TestDir "uniform_upload_lifetime.slang"
$PackagePath = Join-Path $TestDir "uniform_upload_lifetime.ashader"
$GeneratedPath = Join-Path $TestDir "generated\bindings.odin"
$MainPath = Join-Path $TestDir "main.odin"
$OutPath = Join-Path $TestDir "d3d12_uniform_upload_lifetime.exe"
$ShadercPath = Join-Path $Root.Path "build\tools\ape_shaderc.exe"
$PackagePathOdin = $PackagePath.Replace('\', '/')

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $GeneratedPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $ShadercPath) | Out-Null

Set-Content -LiteralPath $ShaderPath -Value @'
cbuffer DispatchParams
{
	uint write_value;
	uint pad0;
	uint pad1;
	uint pad2;
};

RWStructuredBuffer<uint> output_buffer;

[shader("compute")]
[numthreads(1, 1, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	if (dispatch_id.x == 0)
	{
		output_buffer[0] = write_value;
	}
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"build",
	(Join-Path $Root.Path "tools\ape_shaderc"),
	"-out:$ShadercPath"
)

Invoke-Native -Command $ShadercPath -Arguments @(
	"-shader-name", "uniform_upload_lifetime",
	"-kind", "compute",
	"-source", $ShaderPath,
	"-build-dir", $TestDir,
	"-package", $PackagePath,
	"-generated", $GeneratedPath
)

Set-Content -LiteralPath $MainPath -Value @"
package main

import "core:fmt"
import "core:os"
import app "ape:app"
import gfx "ape:gfx"
import shader_assets "ape:shader"

Dispatch_Params :: struct {
	write_value: u32,
	pad0:        u32,
	pad1:        u32,
	pad2:        u32,
}

#assert(size_of(Dispatch_Params) == 16)

OUTPUT_COUNT :: 4

fail :: proc(message: string) {
	fmt.eprintln(message)
	os.exit(1)
}

must_gfx :: proc(ctx: ^gfx.Context, ok: bool, message: string) {
	if !ok {
		fmt.eprintln(message, ": ", gfx.last_error(ctx))
		os.exit(1)
	}
}

main :: proc() {
	if !app.init() {
		fail("app init failed")
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 64,
		height = 64,
		title = "D3D12 Uniform Upload Lifetime Test",
		no_client_api = true,
	})
	if !window_ok {
		fail("window creation failed")
	}
	defer app.destroy_window(&window)

	fb_width, fb_height := app.framebuffer_size(&window)
	ctx, ctx_ok := gfx.init({
		backend = .D3D12,
		width = fb_width,
		height = fb_height,
		native_window = app.native_window_handle(&window),
		swapchain_format = .BGRA8,
		vsync = false,
		debug = true,
		label = "d3d12 uniform upload lifetime regression",
	})
	if !ctx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	pkg, package_ok := shader_assets.load("$PackagePathOdin")
	if !package_ok {
		fail("failed to load uniform lifetime shader package")
	}
	defer shader_assets.unload(&pkg)

	shader_desc, shader_desc_ok := shader_assets.shader_desc(&pkg, .D3D12_DXIL, "uniform upload lifetime shader")
	if !shader_desc_ok {
		fail("failed to build shader desc")
	}

	shader, shader_ok := gfx.create_shader(&ctx, shader_desc)
	must_gfx(&ctx, shader_ok, "shader creation failed")
	defer gfx.destroy(&ctx, shader)

	layout_desc: gfx.Binding_Group_Layout_Desc
	layout_desc.label = "uniform upload lifetime layout"
	layout_desc.group = 0
	layout_desc.entries[0] = {
		active = true,
		stages = {.Compute},
		kind = .Uniform_Block,
		slot = 0,
		name = "DispatchParams",
		uniform_block = {size = size_of(Dispatch_Params)},
	}
	layout_desc.entries[1] = {
		active = true,
		stages = {.Compute},
		kind = .Resource_View,
		slot = 0,
		name = "output_buffer",
		resource_view = {
			view_kind = .Storage_Buffer,
			access = .Read_Write,
			storage_buffer_stride = size_of(u32),
		},
	}
	layout_desc.native_bindings[0] = {
		active = true,
		target = .D3D12,
		stage = .Compute,
		kind = .Uniform_Block,
		slot = 0,
		native_slot = 0,
		native_space = 0,
	}
	layout_desc.native_bindings[1] = {
		active = true,
		target = .D3D12,
		stage = .Compute,
		kind = .Resource_View,
		slot = 0,
		native_slot = 0,
		native_space = 0,
	}

	group_layout, group_layout_ok := gfx.create_binding_group_layout(&ctx, layout_desc)
	must_gfx(&ctx, group_layout_ok, "binding group layout creation failed")
	defer gfx.destroy(&ctx, group_layout)

	pipeline_layout, pipeline_layout_ok := gfx.create_pipeline_layout(&ctx, {
		label = "uniform upload lifetime pipeline layout",
		group_layouts = {0 = group_layout},
	})
	must_gfx(&ctx, pipeline_layout_ok, "pipeline layout creation failed")
	defer gfx.destroy(&ctx, pipeline_layout)

	pipeline, pipeline_ok := gfx.create_compute_pipeline(&ctx, {
		label = "uniform upload lifetime pipeline",
		shader = shader,
		pipeline_layout = pipeline_layout,
	})
	must_gfx(&ctx, pipeline_ok, "compute pipeline creation failed")
	defer gfx.destroy(&ctx, pipeline)

	output_buffers: [OUTPUT_COUNT]gfx.Buffer
	output_views: [OUTPUT_COUNT]gfx.View
	for i in 0..<OUTPUT_COUNT {
		buffer, buffer_ok := gfx.create_buffer(&ctx, {
			label = "uniform upload lifetime output",
			usage = {.Storage},
			size = size_of(u32),
			storage_stride = size_of(u32),
		})
		must_gfx(&ctx, buffer_ok, "output buffer creation failed")
		output_buffers[i] = buffer

		view, view_ok := gfx.create_view(&ctx, {
			label = "uniform upload lifetime output view",
			storage_buffer = {buffer = buffer},
		})
		must_gfx(&ctx, view_ok, "output view creation failed")
		output_views[i] = view
	}

	must_gfx(&ctx, gfx.begin_compute_pass(&ctx, {label = "uniform lifetime writes"}), "begin write pass failed")
	must_gfx(&ctx, gfx.apply_compute_pipeline(&ctx, pipeline), "apply write pipeline failed")
	// Regression guard: every dispatch reuses uniform group 0 slot 0 with a
	// different value before the command list is submitted. D3D12 must bind a
	// distinct upload address for each dispatch, not overwrite one per-slot CB.
	for i in 0..<OUTPUT_COUNT {
		bindings: gfx.Bindings
		bindings.views[0][0] = output_views[i]
		must_gfx(&ctx, gfx.apply_bindings(&ctx, bindings), "apply write bindings failed")
		params := Dispatch_Params {
			write_value = u32((i + 1) * 11),
		}
		must_gfx(&ctx, gfx.apply_uniform(&ctx, 0, 0, &params), "apply write uniform failed")
		must_gfx(&ctx, gfx.dispatch(&ctx, 1, 1, 1), "write dispatch failed")
	}
	must_gfx(&ctx, gfx.end_compute_pass(&ctx), "end write pass failed")

	values: [OUTPUT_COUNT]u32
	for i in 0..<OUTPUT_COUNT {
		value: [1]u32
		must_gfx(&ctx, gfx.read_buffer(&ctx, {buffer = output_buffers[i], data = gfx.range(value[:])}), "output readback failed")
		values[i] = value[0]
	}

	for i in 0..<OUTPUT_COUNT {
		expected := u32((i + 1) * 11)
		if values[i] != expected {
			fmt.eprintf("uniform upload lifetime mismatch at %d: got %d, expected %d\n", i, values[i], expected)
			os.exit(1)
		}
	}

	for i in 0..<OUTPUT_COUNT {
		gfx.destroy(&ctx, output_views[i])
		gfx.destroy(&ctx, output_buffers[i])
	}

	must_gfx(&ctx, gfx.commit(&ctx), "commit failed")
	fmt.println("D3D12 uniform upload lifetime validation passed")
}
"@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
