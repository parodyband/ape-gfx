package shader

import "core:slice"
import "core:strings"

// Test_Package_Variant_Stage describes one stage of one variant for the
// synthetic fixture builder used by the runtime-library test harness. Each
// stage is built into the resulting Package as if it had been packaged from
// disk, so it survives the same `byte_range` validation real packages do.
//
// This API exists so the runtime-lookup test can exercise multi-variant
// resolution without depending on `ape_shaderc` to emit a permutation-bearing
// package. It is intentionally narrow and not part of the production
// surface.
Test_Package_Variant_Stage :: struct {
	target: Backend_Target,
	stage: Stage,
	entry: string,
	bytecode: []u8,
	reflection_json: string,
}

// Test_Package_Variant carries one variant's key and its full stage list.
// The first element of `axis_values` pairs with axis 0 in the supplied axes,
// and so on; pairs are sorted by axis index automatically.
Test_Package_Variant :: struct {
	axis_values: []u16,
	stages: []Test_Package_Variant_Stage,
}

// make_test_package fabricates a Package with the supplied axes and variants.
// The returned package owns its own byte buffer; pass it through `unload` (or
// hand it to `register_package` with `take_ownership = true`) to free it.
//
// Intended for runtime-library tests; production code should load packages
// emitted by `ape_shaderc`.
make_test_package :: proc(axes: []Permutation_Axis, variants: []Test_Package_Variant) -> (Package, bool) {
	if len(variants) == 0 {
		return {}, false
	}

	stage_total := 0
	for variant in variants {
		stage_total += len(variant.stages)
	}

	bytes_builder: strings.Builder
	strings.builder_init(&bytes_builder)

	stage_records := make([]Stage_Record, stage_total)
	variant_records := make([]Permutation_Variant, len(variants))

	stage_cursor := 0
	for variant, variant_index in variants {
		first := stage_cursor
		for stage in variant.stages {
			entry_offset := strings.builder_len(bytes_builder)
			strings.write_string(&bytes_builder, stage.entry)
			bytecode_offset := strings.builder_len(bytes_builder)
			strings.write_bytes(&bytes_builder, stage.bytecode)
			reflection_offset := strings.builder_len(bytes_builder)
			strings.write_string(&bytes_builder, stage.reflection_json)

			stage_records[stage_cursor] = Stage_Record {
				target = stage.target,
				stage = stage.stage,
				entry_offset = u32(entry_offset),
				entry_size = u32(len(stage.entry)),
				bytecode_offset = u64(bytecode_offset),
				bytecode_size = u64(len(stage.bytecode)),
				reflection_offset = u64(reflection_offset),
				reflection_size = u64(len(stage.reflection_json)),
				variant = u32(variant_index),
			}
			stage_cursor += 1
		}

		pairs: []Permutation_Key_Pair
		if len(variant.axis_values) > 0 {
			pairs = make([]Permutation_Key_Pair, len(variant.axis_values))
			for value, axis_index in variant.axis_values {
				pairs[axis_index] = Permutation_Key_Pair{axis = u16(axis_index), value = value}
			}
		}

		variant_records[variant_index] = Permutation_Variant {
			key_hash = canonical_key_hash(pairs),
			pairs = pairs,
			stage_first = u32(first),
			stage_count = u32(len(variant.stages)),
			binding_first = 0,
			binding_count = 0,
		}
	}

	axes_copy := make([]Permutation_Axis, len(axes))
	copy(axes_copy, axes)

	slice.sort_by(variant_records, proc(a, b: Permutation_Variant) -> bool {
		return a.key_hash < b.key_hash
	})

	return Package {
		version = PACKAGE_VERSION,
		bytes = bytes_builder.buf[:],
		stages = stage_records,
		bindings = nil,
		vertex_inputs = nil,
		axes = axes_copy,
		variants = variant_records,
	}, true
}
