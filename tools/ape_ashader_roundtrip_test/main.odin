package main

import "core:fmt"
import "core:os"
import "core:strings"

import shader_assets "ape:shader"

// Round-trip checker for `.ashader` files. APE-27 wires this in to the
// `ape shader test -name ashader-roundtrip` flow. The test executable is
// kept tiny on purpose — it loads the package, asserts the v10 invariants
// the format spec promises, and exits non-zero on any mismatch.
main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: ape_ashader_roundtrip_test <path-to-.ashader>")
		os.exit(2)
	}

	path := os.args[1]
	pkg, ok := shader_assets.load(path)
	if !ok {
		fmt.eprintln("ape_ashader_roundtrip_test: failed to load: ", path)
		os.exit(1)
	}
	defer shader_assets.unload(&pkg)

	if pkg.version != 10 {
		fmt.eprintln("ape_ashader_roundtrip_test: expected version 10, got ", pkg.version)
		os.exit(1)
	}

	if len(pkg.stages) == 0 {
		fmt.eprintln("ape_ashader_roundtrip_test: no stages in package")
		os.exit(1)
	}

	if len(pkg.variants) != 1 {
		fmt.eprintln("ape_ashader_roundtrip_test: expected 1 default variant, got ", len(pkg.variants))
		os.exit(1)
	}

	if len(pkg.axes) != 0 {
		fmt.eprintln("ape_ashader_roundtrip_test: default-only package must declare 0 axes, got ", len(pkg.axes))
		os.exit(1)
	}

	default := pkg.variants[0]
	if default.stage_first != 0 || int(default.stage_count) != len(pkg.stages) {
		fmt.eprintln("ape_ashader_roundtrip_test: default variant does not span all stages")
		os.exit(1)
	}
	if default.binding_first != 0 || int(default.binding_count) != len(pkg.bindings) {
		fmt.eprintln("ape_ashader_roundtrip_test: default variant does not span all bindings")
		os.exit(1)
	}
	if default.key_hash != shader_assets.canonical_key_hash(nil) {
		fmt.eprintln("ape_ashader_roundtrip_test: default variant key_hash mismatch")
		os.exit(1)
	}
	if len(default.pairs) != 0 {
		fmt.eprintln("ape_ashader_roundtrip_test: default variant must have empty key")
		os.exit(1)
	}

	idx, found := shader_assets.find_variant(&pkg, default.key_hash)
	if !found || idx != 0 {
		fmt.eprintln("ape_ashader_roundtrip_test: find_variant did not return default variant")
		os.exit(1)
	}

	// Reflection round-trip: every stage must expose a non-empty reflection
	// blob, and the bytes returned by `reflection_json` must come from the
	// same range that the stage record points at.
	for stage_record in pkg.stages {
		if stage_record.variant != 0 {
			fmt.eprintln("ape_ashader_roundtrip_test: stage record variant != 0")
			os.exit(1)
		}
		json, json_ok := shader_assets.reflection_json(&pkg, stage_record.target, stage_record.stage)
		if !json_ok || len(json) == 0 {
			fmt.eprintln("ape_ashader_roundtrip_test: missing reflection JSON for stage")
			os.exit(1)
		}
		if int(stage_record.reflection_size) != len(json) {
			fmt.eprintln("ape_ashader_roundtrip_test: reflection size mismatch")
			os.exit(1)
		}
		if !strings.contains(json, "\"") {
			fmt.eprintln("ape_ashader_roundtrip_test: reflection JSON does not look like JSON")
			os.exit(1)
		}
	}

	for binding in pkg.bindings {
		if binding.variant != 0 {
			fmt.eprintln("ape_ashader_roundtrip_test: binding record variant != 0")
			os.exit(1)
		}
	}

	fmt.println("ashader round-trip OK: ", path)
}
