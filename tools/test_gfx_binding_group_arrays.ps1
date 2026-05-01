param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\gfx_binding_group_arrays"
$OutPath = Join-Path $TestDir "gfx_binding_group_arrays.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

// AAA roadmap item 28 / APE-24: validation rules for fixed-array, runtime-array,
// and bindless descriptor bindings. Covers the easy traps for each category and
// verifies the reflection-driven cross-check (layout array_count vs binding
// group payload count).

import "core:fmt"
import "core:os"
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
	ctx, ctx_ok := gfx.init({backend = .Null, label = "binding group arrays"})
	if !ctx_ok {
		fmt.eprintln("init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	// Set up a sampled image + view + sampler we can reuse across tests.
	pixels := [?]u8{255, 255, 255, 255}
	image, image_ok := gfx.create_image(&ctx, gfx.Image_Desc{
		label  = "tex",
		usage  = {.Texture, .Immutable},
		width  = 1, height = 1,
		format = .RGBA8,
		mips   = {0 = {data = gfx.range(pixels[:])}},
	})
	if !image_ok { fail("image creation failed") }
	defer gfx.destroy(&ctx, image)

	view_a, view_a_ok := gfx.create_view(&ctx, gfx.View_Desc{
		label = "view_a", texture = {image = image},
	})
	if !view_a_ok { fail("view_a creation failed") }
	defer gfx.destroy(&ctx, view_a)

	view_b, view_b_ok := gfx.create_view(&ctx, gfx.View_Desc{
		label = "view_b", texture = {image = image},
	})
	if !view_b_ok { fail("view_b creation failed") }
	defer gfx.destroy(&ctx, view_b)

	sampler, sampler_ok := gfx.create_sampler(&ctx, gfx.Sampler_Desc{label = "samp"})
	if !sampler_ok { fail("sampler creation failed") }
	defer gfx.destroy(&ctx, sampler)

	// === Fixed-array layout: a Resource_View array of size 3 at slot 0 ===
	array_layout: gfx.Binding_Group_Layout_Desc
	array_layout.label = "fixed view array layout"
	array_layout.entries[0] = {
		active       = true,
		stages       = {.Fragment},
		kind         = .Resource_View,
		slot         = 0,
		array_count  = 3,
		name         = "textures",
		resource_view = {view_kind = .Sampled, access = .Read},
	}
	array_layout_handle, array_layout_ok := gfx.create_binding_group_layout(&ctx, array_layout)
	if !array_layout_ok {
		fmt.eprintln("array layout failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}

	// EASY TRAP: layout declares N=3 but Binding_Group payload is missing.
	missing_payload_desc: gfx.Binding_Group_Desc
	missing_payload_desc.layout = array_layout_handle
	if _, ok := gfx.create_binding_group(&ctx, missing_payload_desc); ok {
		fail("missing array payload unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation,
		"gfx.create_binding_group: resource view slot 0 declares a fixed array of size 3 but no Binding_Group_Desc.arrays entry populates it")

	// EASY TRAP: payload count differs from layout array_count (binding fewer).
	too_few_views := [?]gfx.View{view_a, view_b}
	too_few_desc: gfx.Binding_Group_Desc
	too_few_desc.layout = array_layout_handle
	too_few_desc.arrays[0] = {
		active = true, kind = .Resource_View, slot = 0,
		count  = u32(len(too_few_views)), views = too_few_views[:],
	}
	if _, ok := gfx.create_binding_group(&ctx, too_few_desc); ok {
		fail("array with too few views unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation,
		"gfx.create_binding_group: resource view slot 0 fixed-array count 2 does not match layout count 3")

	// EASY TRAP: payload count matches layout but views slice is shorter.
	short_slice_desc: gfx.Binding_Group_Desc
	short_slice_desc.layout = array_layout_handle
	short_slice_desc.arrays[0] = {
		active = true, kind = .Resource_View, slot = 0,
		count = 3, views = too_few_views[:],
	}
	if _, ok := gfx.create_binding_group(&ctx, short_slice_desc); ok {
		fail("array views slice shorter than count unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation,
		"gfx.create_binding_group: resource view fixed-array at slot 0 expects 3 views, got 2")

	// EASY TRAP: orphan payload — array entry that no layout entry declares.
	orphan_views := [?]gfx.View{view_a}
	orphan_desc: gfx.Binding_Group_Desc
	orphan_desc.layout = array_layout_handle
	full_views := [?]gfx.View{view_a, view_b, view_a}
	orphan_desc.arrays[0] = {
		active = true, kind = .Resource_View, slot = 0,
		count = 3, views = full_views[:],
	}
	orphan_desc.arrays[1] = {
		active = true, kind = .Resource_View, slot = 7,
		count = 1, views = orphan_views[:],
	}
	if _, ok := gfx.create_binding_group(&ctx, orphan_desc); ok {
		fail("orphan array payload unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation,
		"gfx.create_binding_group: arrays[1] resource view slot 7 is not declared as a fixed array by the layout")

	// EASY TRAP: scalar views[] populated for a slot that the layout marks as a
	// fixed array. Caller should use Binding_Group_Desc.arrays instead.
	scalar_at_array_desc: gfx.Binding_Group_Desc
	scalar_at_array_desc.layout = array_layout_handle
	scalar_at_array_desc.arrays[0] = {
		active = true, kind = .Resource_View, slot = 0,
		count = 3, views = full_views[:],
	}
	scalar_at_array_desc.views[1] = view_a
	if _, ok := gfx.create_binding_group(&ctx, scalar_at_array_desc); ok {
		fail("scalar views[] populated inside fixed-array slot range unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation,
		"gfx.create_binding_group: resource view slot 1 is declared as a fixed array; populate Binding_Group_Desc.arrays instead")

	// HAPPY PATH: full payload of N=3 sampled views matches the layout exactly.
	good_desc: gfx.Binding_Group_Desc
	good_desc.layout = array_layout_handle
	good_desc.arrays[0] = {
		active = true, kind = .Resource_View, slot = 0,
		count = 3, views = full_views[:],
	}
	good_group, good_ok := gfx.create_binding_group(&ctx, good_desc)
	if !good_ok {
		fmt.eprintln("happy-path fixed array failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	gfx.destroy(&ctx, good_group)

	// === Layout overlap detection: scalar at slot 1 collides with array
	//     [0, 3) at slot 0. ===
	overlap_layout: gfx.Binding_Group_Layout_Desc
	overlap_layout.entries[0] = {
		active = true, stages = {.Fragment},
		kind = .Resource_View, slot = 0, array_count = 3,
		name = "textures",
		resource_view = {view_kind = .Sampled, access = .Read},
	}
	overlap_layout.entries[1] = {
		active = true, stages = {.Fragment},
		kind = .Resource_View, slot = 1,
		name = "extra",
		resource_view = {view_kind = .Sampled, access = .Read},
	}
	if _, ok := gfx.create_binding_group_layout(&ctx, overlap_layout); ok {
		fail("layout with overlapping slot ranges unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation,
		"gfx.validate_binding_group_layout_desc: resource view slot range [1, 2) overlaps existing entry at slot 0")

	// === Layout rejects unsized arrays (deferred to Binding_Heap path). ===
	unsized_layout: gfx.Binding_Group_Layout_Desc
	unsized_layout.entries[0] = {
		active = true, stages = {.Fragment},
		kind = .Resource_View, slot = 0, unsized = true,
		name = "textures",
		resource_view = {view_kind = .Sampled, access = .Read},
	}
	if _, ok := gfx.create_binding_group_layout(&ctx, unsized_layout); ok {
		fail("unsized layout entry unexpectedly accepted")
	}
	expect_error_info(&ctx, .Validation,
		"gfx.validate_binding_group_layout_desc: entry 0 declares an unsized array; runtime / bindless arrays use Binding_Heap (item 28 ships fixed arrays only)")

	// === Layout rejects array_count > 1 on a uniform block. ===
	uniform_array_layout: gfx.Binding_Group_Layout_Desc
	uniform_array_layout.entries[0] = {
		active = true, stages = {.Fragment},
		kind = .Uniform_Block, slot = 0, array_count = 4,
		name = "ub",
		uniform_block = {size = 16},
	}
	if _, ok := gfx.create_binding_group_layout(&ctx, uniform_array_layout); ok {
		fail("uniform-block array unexpectedly accepted")
	}
	expect_error_info(&ctx, .Validation,
		"gfx.validate_binding_group_layout_desc: entry 0 uniform blocks do not support fixed arrays")

	// === Binding_Heap creation is gated to backend support — surface validates
	//     the desc shape, then reports Unsupported. ===
	zero_capacity_heap, zero_capacity_ok := gfx.create_binding_heap(&ctx, gfx.Binding_Heap_Desc{
		label = "zero capacity",
		capacity = 0,
		view_kind = .Sampled,
		access    = .Read,
	})
	if zero_capacity_ok || u64(zero_capacity_heap) != 0 {
		fail("zero-capacity heap unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_binding_heap: capacity must be > 0")

	bad_format_heap, bad_format_ok := gfx.create_binding_heap(&ctx, gfx.Binding_Heap_Desc{
		label = "bad storage format",
		capacity = 16,
		view_kind = .Storage_Image,
		access    = .Read_Write,
		storage_image_format = .RGBA8, // not in shader_storage_image_format_valid
	})
	if bad_format_ok || u64(bad_format_heap) != 0 {
		fail("storage image heap with unsupported format unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_binding_heap: storage image heap has an unsupported format")

	mixed_kind_heap, mixed_ok := gfx.create_binding_heap(&ctx, gfx.Binding_Heap_Desc{
		label = "sampler + view kind",
		capacity = 16,
		samplers = true,
		storage_image_format = .RGBA32F,
	})
	if mixed_ok || u64(mixed_kind_heap) != 0 {
		fail("sampler heap with format unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_binding_heap: sampler heap must not declare a storage image format")

	good_heap, good_heap_ok := gfx.create_binding_heap(&ctx, gfx.Binding_Heap_Desc{
		label = "good shape",
		capacity = 16,
		view_kind = .Sampled,
		access    = .Read,
	})
	if good_heap_ok || u64(good_heap) != 0 {
		fail("heap with valid shape unexpectedly returned a live handle (backend not implemented yet)")
	}
	expect_error_info(&ctx, .Unsupported,
		"gfx.create_binding_heap: backend support is not implemented yet (item 28 ships fixed arrays only; runtime / bindless heap is gated on the runtime-array sample)")

	// Heap update / apply entry points must reject invalid handles even before
	// the backend lands so callers get a stable error vocabulary.
	if gfx.update_binding_heap_views(&ctx, gfx.Binding_Heap_Invalid, 0, []gfx.View{}) {
		fail("update_binding_heap_views with invalid heap unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Invalid_Handle, "gfx.update_binding_heap_views: heap handle is invalid")

	if gfx.apply_binding_heap(&ctx, 0, gfx.Binding_Heap_Invalid) {
		fail("apply_binding_heap with invalid heap unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Invalid_Handle, "gfx.apply_binding_heap: heap handle is invalid")

	fmt.println("gfx binding group array validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
