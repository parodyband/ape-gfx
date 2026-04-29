param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\d3d11_compute_pass"
$ShadercPath = Join-Path $TestDir "ape_shaderc.exe"
$SourcePath = Join-Path $TestDir "compute_storage.slang"
$PackagePath = Join-Path $TestDir "compute_storage.ashader"
$GeneratedDir = Join-Path $TestDir "generated"
$GeneratedPath = Join-Path $GeneratedDir "bindings.odin"
$StaleGeneratedPath = Join-Path $TestDir "bindings.odin"
$OutPath = Join-Path $TestDir "d3d11_compute_pass.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null
New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null
Remove-Item -LiteralPath $StaleGeneratedPath -ErrorAction SilentlyContinue

Set-Content -LiteralPath $SourcePath -Value @'
RWTexture2D<float4> output_image : register(u0);
RWByteAddressBuffer output_buffer : register(u1);

struct Item
{
	float4 value;
	uint id;
};

RWStructuredBuffer<Item> output_items : register(u2);

[shader("compute")]
[numthreads(2, 3, 4)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	uint linear_id = dispatch_id.x + dispatch_id.y * 2 + dispatch_id.z * 6;
	output_image[uint2(dispatch_id.x, dispatch_id.y + dispatch_id.z * 3)] = float4(1.0, 0.25, 0.0, 1.0);
	output_buffer.Store(linear_id * 4, 123);

	Item item;
	item.value = float4(float(linear_id), 0.25, 0.0, 1.0);
	item.id = linear_id;
	output_items[linear_id] = item;
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"build",
	(Join-Path $Root.Path "tools\ape_shaderc"),
	"-out:$ShadercPath"
)

Invoke-Native -Command $ShadercPath -Arguments @(
	"-shader-name", "compute_storage",
	"-kind", "compute",
	"-source", $SourcePath,
	"-build-dir", $TestDir,
	"-package", $PackagePath,
	"-generated", $GeneratedPath
)

$Generated = Get-Content -LiteralPath $GeneratedPath -Raw
$ExpectedSnippets = @(
	"D3D11_CS_VIEW_output_image :: 0",
	"D3D11_CS_VIEW_output_buffer :: 1",
	"VIEW_KIND_output_image :: gfx.View_Kind.Storage_Image",
	"VIEW_FORMAT_output_image :: gfx.Pixel_Format.RGBA32F",
	"VIEW_KIND_output_buffer :: gfx.View_Kind.Storage_Buffer",
	"VIEW_STRIDE_output_buffer :: 0",
	"D3D11_CS_VIEW_output_items :: 2",
	"VIEW_KIND_output_items :: gfx.View_Kind.Storage_Buffer",
	"VIEW_STRIDE_output_items :: 20",
	"COMPUTE_THREAD_GROUP_SIZE_X :: 2",
	"COMPUTE_THREAD_GROUP_SIZE_Y :: 3",
	"COMPUTE_THREAD_GROUP_SIZE_Z :: 4",
	"COMPUTE_THREAD_GROUP_INVOCATIONS :: 24",
	"dispatch_groups_for_threads :: proc(thread_count_x: u32, thread_count_y: u32 = 1, thread_count_z: u32 = 1) -> (u32, u32, u32)",
	"dispatch_threads :: proc(ctx: ^gfx.Context, thread_count_x: u32, thread_count_y: u32 = 1, thread_count_z: u32 = 1) -> bool"
)

foreach ($Snippet in $ExpectedSnippets) {
	if (-not $Generated.Contains($Snippet)) {
		Write-Error "Missing generated compute metadata: $Snippet"
	}
}

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import app "ape:app"
import compute_storage_shader "ape:build/validation_tests/d3d11_compute_pass/generated"
import gfx "ape:gfx"
import shader_assets "ape:shader"

Item :: struct {
	value: [4]f32,
	id: u32,
}

#assert(size_of(Item) == 20)

main :: proc() {
	if !app.init() {
		fmt.eprintln("app init failed")
		os.exit(1)
	}
	defer app.shutdown()

	window, window_ok := app.create_window({
		width = 320,
		height = 240,
		title = "Ape D3D11 Compute Pass",
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
		label = "compute pass validation test",
	})
	if !gfx_ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	features := gfx.query_features(&ctx)
	if !features.compute || !features.storage_images || !features.storage_buffers {
		fmt.eprintln("unexpected compute feature flags")
		os.exit(1)
	}

	shader_package, package_ok := shader_assets.load("build/validation_tests/d3d11_compute_pass/compute_storage.ashader")
	if !package_ok {
		fmt.eprintln("failed to read compute shader package")
		os.exit(1)
	}
	defer shader_assets.unload(&shader_package)

	shader_desc, shader_desc_ok := shader_assets.shader_desc(&shader_package, .D3D11_DXBC, "compute storage shader")
	if !shader_desc_ok || shader_desc.stages[int(gfx.Shader_Stage.Compute)].bytecode.ptr == nil {
		fmt.eprintln("failed to build compute shader desc")
		os.exit(1)
	}

	shader, shader_ok := gfx.create_shader(&ctx, shader_desc)
	if !shader_ok {
		fmt.eprintln("shader creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, shader)

	pipeline, pipeline_ok := gfx.create_compute_pipeline(&ctx, {
		label = "compute storage pipeline",
		shader = shader,
	})
	if !pipeline_ok {
		fmt.eprintln("compute pipeline creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, pipeline)

	storage_image, storage_image_ok := gfx.create_image(&ctx, {
		label = "compute output image",
		usage = {.Storage_Image},
		width = 2,
		height = 12,
		format = .RGBA32F,
	})
	if !storage_image_ok {
		fmt.eprintln("storage image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_image)

	storage_image_view, storage_image_view_ok := gfx.create_view(&ctx, {
		label = "compute output image view",
		storage_image = {
			image = storage_image,
		},
	})
	if !storage_image_view_ok {
		fmt.eprintln("storage image view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_image_view)

	storage_buffer, storage_buffer_ok := gfx.create_buffer(&ctx, {
		label = "compute output buffer",
		usage = {.Storage},
		size = 128,
	})
	if !storage_buffer_ok {
		fmt.eprintln("storage buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_buffer)

	storage_buffer_view, storage_buffer_view_ok := gfx.create_view(&ctx, {
		label = "compute output buffer view",
		storage_buffer = {
			buffer = storage_buffer,
		},
	})
	if !storage_buffer_view_ok {
		fmt.eprintln("storage buffer view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, storage_buffer_view)

	structured_buffer, structured_buffer_ok := gfx.create_buffer(&ctx, {
		label = "compute structured output buffer",
		usage = {.Storage},
		size = 24 * size_of(Item),
		storage_stride = size_of(Item),
	})
	if !structured_buffer_ok {
		fmt.eprintln("structured buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, structured_buffer)

	structured_buffer_view, structured_buffer_view_ok := gfx.create_view(&ctx, {
		label = "compute structured output buffer view",
		storage_buffer = {
			buffer = structured_buffer,
		},
	})
	if !structured_buffer_view_ok {
		fmt.eprintln("structured buffer view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, structured_buffer_view)

	wrong_stride_buffer, wrong_stride_buffer_ok := gfx.create_buffer(&ctx, {
		label = "wrong stride structured buffer",
		usage = {.Storage},
		size = 24 * 16,
		storage_stride = 16,
	})
	if !wrong_stride_buffer_ok {
		fmt.eprintln("wrong stride buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, wrong_stride_buffer)

	wrong_stride_view, wrong_stride_view_ok := gfx.create_view(&ctx, {
		label = "wrong stride structured view",
		storage_buffer = {
			buffer = wrong_stride_buffer,
		},
	})
	if !wrong_stride_view_ok {
		fmt.eprintln("wrong stride view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, wrong_stride_view)

	sampled_image, sampled_image_ok := gfx.create_image(&ctx, {
		label = "wrong sampled image",
		usage = {.Texture},
		width = 1,
		height = 1,
		format = .RGBA8,
	})
	if !sampled_image_ok {
		fmt.eprintln("sampled image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, sampled_image)

	sampled_view, sampled_view_ok := gfx.create_view(&ctx, {
		label = "wrong sampled view",
		texture = {
			image = sampled_image,
		},
	})
	if !sampled_view_ok {
		fmt.eprintln("sampled view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, sampled_view)

	wrong_format_image, wrong_format_image_ok := gfx.create_image(&ctx, {
		label = "wrong format storage image",
		usage = {.Storage_Image},
		width = 1,
		height = 1,
		format = .R32F,
	})
	if !wrong_format_image_ok {
		fmt.eprintln("wrong format storage image creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, wrong_format_image)

	wrong_format_view, wrong_format_view_ok := gfx.create_view(&ctx, {
		label = "wrong format storage view",
		storage_image = {
			image = wrong_format_image,
		},
	})
	if !wrong_format_view_ok {
		fmt.eprintln("wrong format storage view creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.destroy(&ctx, wrong_format_view)

	if !gfx.begin_compute_pass(&ctx, {label = "compute"}) {
		fmt.eprintln("begin_compute_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	if !gfx.apply_compute_pipeline(&ctx, pipeline) {
		fmt.eprintln("apply_compute_pipeline failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	wrong_bindings: gfx.Bindings
	wrong_bindings.views[0] = sampled_view
	if gfx.apply_bindings(&ctx, wrong_bindings) {
		fmt.eprintln("sampled view bound to storage slot unexpectedly succeeded")
		os.exit(1)
	}
	expected := "gfx.d3d11: resource view slot 0 expects storage image view, got sampled view"
	if gfx.last_error(&ctx) != expected {
		fmt.eprintln("invalid compute view kind failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	wrong_format_bindings: gfx.Bindings
	wrong_format_bindings.views[0] = wrong_format_view
	if gfx.apply_bindings(&ctx, wrong_format_bindings) {
		fmt.eprintln("storage image format mismatch unexpectedly succeeded")
		os.exit(1)
	}
	expected = "gfx.d3d11: storage image resource view slot 0 expects format RGBA32F, got R32F"
	if gfx.last_error(&ctx) != expected {
		fmt.eprintln("invalid compute storage image format failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	wrong_stride_bindings: gfx.Bindings
	wrong_stride_bindings.views[2] = wrong_stride_view
	if gfx.apply_bindings(&ctx, wrong_stride_bindings) {
		fmt.eprintln("storage buffer stride mismatch unexpectedly succeeded")
		os.exit(1)
	}
	expected = "gfx.d3d11: storage buffer resource view slot 2 expects stride 20, got 16"
	if gfx.last_error(&ctx) != expected {
		fmt.eprintln("invalid compute storage buffer stride failed with unexpected error: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	bindings: gfx.Bindings
	bindings.views[0] = storage_image_view
	bindings.views[1] = storage_buffer_view
	bindings.views[2] = structured_buffer_view
	if !gfx.apply_bindings(&ctx, bindings) {
		fmt.eprintln("apply_bindings failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	group_x, group_y, group_z := compute_storage_shader.dispatch_groups_for_threads(2, 12, 1)
	if group_x != 1 || group_y != 4 || group_z != 1 {
		fmt.eprintln("generated dispatch group helper returned unexpected counts")
		os.exit(1)
	}

	if !compute_storage_shader.dispatch_threads(&ctx, 2, 12, 1) {
		fmt.eprintln("dispatch failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	if !gfx.end_compute_pass(&ctx) {
		fmt.eprintln("end_compute_pass failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	read_value: u32
	if !gfx.read_buffer(&ctx, {
		buffer = storage_buffer,
		data = gfx.range_raw(rawptr(&read_value), size_of(u32)),
	}) {
		fmt.eprintln("read_buffer failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if read_value != 123 {
		fmt.eprintln("compute storage buffer readback returned unexpected value: ", read_value)
		os.exit(1)
	}

	read_items: [24]Item
	if !gfx.read_buffer(&ctx, {
		buffer = structured_buffer,
		data = gfx.range(read_items[:]),
	}) {
		fmt.eprintln("structured read_buffer failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	if read_items[23].id != 23 || read_items[23].value[0] != 23 {
		fmt.eprintln("compute structured buffer readback returned unexpected value")
		os.exit(1)
	}

	if !gfx.commit(&ctx) {
		fmt.eprintln("commit failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	fmt.println("D3D11 compute pass validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
