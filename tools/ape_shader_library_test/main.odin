package main

import "core:fmt"
import "core:os"
import gfx "ape:gfx"
import shader "ape:shader"

// Runtime test for the shader Library introduced by APE-28 (AAA roadmap
// item 32). Builds an in-memory two-variant package, registers it, then:
//
//   1. Resolves shader and pipeline handles for two distinct permutation
//      keys and asserts the handles differ between variants.
//   2. Repeats both lookups and asserts the cache returns the same handles.
//   3. Drives a Null-backend frame that applies *both* pipelines in a single
//      pass — the runtime "switch a permutation mid-frame" case the design
//      note calls out.
//
// The pipeline cache is keyed by (Shader_Id, Permutation_Key, state_hash);
// reusing the library across frames is what keeps reflection/binding work off
// the per-frame path.
main :: proc() {
	axes := []shader.Permutation_Axis {
		{
			name = "MODE",
			kind = .Bool,
			value_count = 2,
			default_index = 0,
		},
	}

	vs_default_bytecode := []u8 {0xDE, 0xAD, 0xBE, 0xEF}
	fs_default_bytecode := []u8 {0xCA, 0xFE, 0xBA, 0xBE}
	vs_alt_bytecode := []u8 {0x01, 0x02, 0x03, 0x04}
	fs_alt_bytecode := []u8 {0x05, 0x06, 0x07, 0x08}

	variants := []shader.Test_Package_Variant {
		{
			axis_values = nil,
			stages = []shader.Test_Package_Variant_Stage {
				{
					target = .D3D11_DXBC,
					stage = .Vertex,
					entry = "vs_main",
					bytecode = vs_default_bytecode,
					reflection_json = "{}",
				},
				{
					target = .D3D11_DXBC,
					stage = .Fragment,
					entry = "fs_main",
					bytecode = fs_default_bytecode,
					reflection_json = "{}",
				},
			},
		},
		{
			axis_values = []u16{1},
			stages = []shader.Test_Package_Variant_Stage {
				{
					target = .D3D11_DXBC,
					stage = .Vertex,
					entry = "vs_alt",
					bytecode = vs_alt_bytecode,
					reflection_json = "{}",
				},
				{
					target = .D3D11_DXBC,
					stage = .Fragment,
					entry = "fs_alt",
					bytecode = fs_alt_bytecode,
					reflection_json = "{}",
				},
			},
		},
	}

	pkg, pkg_ok := shader.make_test_package(axes, variants)
	if !pkg_ok {
		fail("synthetic package construction failed")
	}

	ctx, init_ok := gfx.init({
		backend = .Null,
		width = 64,
		height = 64,
		debug = true,
		label = "ape shader library test",
	})
	if !init_ok {
		fail(fmt.tprintf("gfx init failed: %s", gfx.last_error(&ctx)))
	}
	defer gfx.shutdown(&ctx)

	lib := shader.library_init()
	defer shader.library_destroy(&lib, &ctx)

	id, register_ok := shader.register_package(&lib, "perm_test", pkg, true)
	if !register_ok {
		fail("register_package failed")
	}

	default_key: shader.Permutation_Key
	alt_key: shader.Permutation_Key
	if !shader.permutation_key_set(&alt_key, 0, 1) {
		fail("permutation_key_set failed")
	}

	if shader.permutation_key_hash(default_key) == shader.permutation_key_hash(alt_key) {
		fail("default and alt keys hashed identically")
	}

	shader_default, ok := shader.resolve(&lib, &ctx, id, default_key)
	if !ok || !gfx.shader_valid(shader_default) {
		fail("resolve(default) failed")
	}
	shader_alt, ok2 := shader.resolve(&lib, &ctx, id, alt_key)
	if !ok2 || !gfx.shader_valid(shader_alt) {
		fail("resolve(alt) failed")
	}
	if shader_default == shader_alt {
		fail("default and alt variants returned the same shader handle")
	}

	// Cache hit on identical lookups.
	shader_default_again, _ := shader.resolve(&lib, &ctx, id, default_key)
	if shader_default_again != shader_default {
		fail("shader cache returned a different handle for the default variant")
	}
	shader_alt_again, _ := shader.resolve(&lib, &ctx, id, alt_key)
	if shader_alt_again != shader_alt {
		fail("shader cache returned a different handle for the alt variant")
	}

	pipeline_desc := gfx.Pipeline_Desc {
		label = "perm_test",
		primitive_type = .Triangles,
		color_formats = {0 = .RGBA8},
	}

	pipe_default, ok3 := shader.resolve_pipeline(&lib, &ctx, {
		id = id,
		key = default_key,
		state_hash = 0xA1B2C3D4,
		base = pipeline_desc,
	})
	if !ok3 || !gfx.pipeline_valid(pipe_default) {
		fail("resolve_pipeline(default) failed")
	}
	pipe_alt, ok4 := shader.resolve_pipeline(&lib, &ctx, {
		id = id,
		key = alt_key,
		state_hash = 0xA1B2C3D4,
		base = pipeline_desc,
	})
	if !ok4 || !gfx.pipeline_valid(pipe_alt) {
		fail("resolve_pipeline(alt) failed")
	}
	if pipe_default == pipe_alt {
		fail("default and alt pipelines collapsed to the same handle")
	}

	pipe_default_again, _ := shader.resolve_pipeline(&lib, &ctx, {
		id = id,
		key = default_key,
		state_hash = 0xA1B2C3D4,
		base = pipeline_desc,
	})
	if pipe_default_again != pipe_default {
		fail("pipeline cache returned a different handle for the default variant")
	}

	// Different state_hash -> different cached pipeline, same shader.
	pipe_default_alt_state, ok5 := shader.resolve_pipeline(&lib, &ctx, {
		id = id,
		key = default_key,
		state_hash = 0xDEADBEEF,
		base = pipeline_desc,
	})
	if !ok5 || pipe_default_alt_state == pipe_default {
		fail("pipeline cache ignored state_hash")
	}

	// Drive an actual frame: apply both pipelines back-to-back. This is the
	// "switch a permutation at runtime within one frame" requirement.
	action := gfx.default_pass_action()
	pass := gfx.Pass_Desc {
		label = "permutation switch",
		action = action,
	}
	if !gfx.begin_pass(&ctx, pass) {
		fail(fmt.tprintf("begin_pass failed: %s", gfx.last_error(&ctx)))
	}
	if !gfx.apply_pipeline(&ctx, pipe_default) {
		fail(fmt.tprintf("apply_pipeline(default) failed: %s", gfx.last_error(&ctx)))
	}
	if !gfx.apply_pipeline(&ctx, pipe_alt) {
		fail(fmt.tprintf("apply_pipeline(alt) failed: %s", gfx.last_error(&ctx)))
	}
	if !gfx.end_pass(&ctx) {
		fail(fmt.tprintf("end_pass failed: %s", gfx.last_error(&ctx)))
	}
	if !gfx.commit(&ctx) {
		fail(fmt.tprintf("commit failed: %s", gfx.last_error(&ctx)))
	}

	fmt.println("ape_shader_library_test: OK")
}

fail :: proc(message: string) -> ! {
	fmt.eprintln("ape_shader_library_test FAILED: ", message)
	os.exit(1)
}
