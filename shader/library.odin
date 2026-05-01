package shader

import "core:os"
import "core:strings"
import gfx "ape:gfx"

// Shader_Id is a stable runtime identifier for a shader identity. It is minted
// by `register` and remains valid for the lifetime of the owning Library.
// AAA roadmap item 32: identity + permutation key are the runtime lookup
// inputs; everything backend-specific is cached behind this id.
Shader_Id :: distinct u32

// Shader_Id_Invalid is returned when registration fails.
Shader_Id_Invalid :: Shader_Id(0)

// Permutation_Key is a runtime-side permutation selector. The pair count is
// bounded by MAX_PERMUTATION_AXES so the key fits in a fixed buffer; broader
// keys are a refactor signal per the design note.
Permutation_Key :: struct {
	pair_count: u32,
	pairs: [MAX_PERMUTATION_AXES]Permutation_Key_Pair,
}

// Library_Compiler is the optional source-compile fallback. When `resolve`
// misses both the live cache and the on-disk `.ashader`, the library invokes
// the compiler to produce a fresh package at `out_path`. Returning false
// surfaces as a Library lookup failure.
//
// The default contract is one-shot: produce `out_path` synchronously. The
// runtime owns no policy about caching that file; the user controls where it
// lands and whether to retain it across runs.
Library_Compiler :: #type proc(name: string, source_path: string, out_path: string, user: rawptr) -> bool

// Library_Pipeline_Desc is the pipeline-cache lookup key. `base` carries the
// non-shader pipeline state and is used to mint the eventual gfx.Pipeline.
// The `shader` field on `base` is filled in by the library after it resolves
// the variant — callers must leave it Shader_Invalid.
Library_Pipeline_Desc :: struct {
	id: Shader_Id,
	key: Permutation_Key,
	state_hash: u64,
	base: gfx.Pipeline_Desc,
}

// Library owns runtime caches mapping (Shader_Id, Permutation_Key) to a live
// gfx.Shader and (id, key, render_state_hash) to a gfx.Pipeline. Loaded
// `.ashader` packages and registration metadata live here too; destroying the
// library tears down all derived gfx handles in the supplied context.
Library :: struct {
	entries: [dynamic]Library_Entry,
	name_index: map[string]Shader_Id,
	pipelines: [dynamic]Pipeline_Cache_Entry,
	compile: Library_Compiler,
	compile_user: rawptr,
}

@(private)
Library_Entry :: struct {
	name: string,
	package_path: string,
	source_path: string,
	package_owned: bool,
	package_loaded: bool,
	pkg: Package,
	shaders: [dynamic]Shader_Cache_Entry,
}

@(private)
Shader_Cache_Entry :: struct {
	target: Backend_Target,
	variant_index: u32,
	key_hash: u64,
	shader: gfx.Shader,
}

@(private)
Pipeline_Cache_Entry :: struct {
	id: Shader_Id,
	target: Backend_Target,
	variant_index: u32,
	state_hash: u64,
	shader: gfx.Shader,
	pipeline: gfx.Pipeline,
}

// library_init returns an empty Library. The returned value can be moved.
library_init :: proc() -> Library {
	return Library {
		entries = make([dynamic]Library_Entry),
		name_index = make(map[string]Shader_Id),
		pipelines = make([dynamic]Pipeline_Cache_Entry),
	}
}

// library_destroy releases every cached gfx handle and frees library-owned
// memory. Pass the same Context the library minted handles into.
library_destroy :: proc(lib: ^Library, ctx: ^gfx.Context) {
	if lib == nil {
		return
	}

	for &entry in lib.pipelines {
		if gfx.pipeline_valid(entry.pipeline) {
			gfx.destroy_pipeline(ctx, entry.pipeline)
		}
	}
	delete(lib.pipelines)
	lib.pipelines = nil

	for &entry in lib.entries {
		for &shader_entry in entry.shaders {
			if gfx.shader_valid(shader_entry.shader) {
				gfx.destroy_shader(ctx, shader_entry.shader)
			}
		}
		delete(entry.shaders)
		if entry.package_owned && entry.package_loaded {
			unload(&entry.pkg)
		}
		delete(entry.name)
		delete(entry.package_path)
		delete(entry.source_path)
	}
	delete(lib.entries)
	lib.entries = nil

	delete(lib.name_index)
	lib.name_index = nil
}

// set_source_compiler installs the optional source-compile fallback. When
// `nil`, `resolve` returns false on a miss instead of trying to recompile.
set_source_compiler :: proc(lib: ^Library, fn: Library_Compiler, user: rawptr) {
	if lib == nil {
		return
	}
	lib.compile = fn
	lib.compile_user = user
}

// register_path registers a shader identity backed by an `.ashader` file at
// `package_path`. The file is loaded lazily on the first resolve.
register_path :: proc(lib: ^Library, name: string, package_path: string) -> (Shader_Id, bool) {
	return register_path_with_source(lib, name, package_path, "")
}

// register_path_with_source binds a `.ashader` package path *and* a source
// path. If the package is missing on disk and a Library_Compiler is set, the
// runtime will invoke it to produce the package on first resolve.
register_path_with_source :: proc(lib: ^Library, name, package_path, source_path: string) -> (Shader_Id, bool) {
	if lib == nil || name == "" {
		return Shader_Id_Invalid, false
	}
	if _, dup := lib.name_index[name]; dup {
		return Shader_Id_Invalid, false
	}

	id := Shader_Id(u32(len(lib.entries)) + 1)
	entry := Library_Entry {
		name = strings.clone(name),
		package_path = strings.clone(package_path),
		source_path = strings.clone(source_path),
		shaders = make([dynamic]Shader_Cache_Entry),
	}

	append(&lib.entries, entry)
	lib.name_index[lib.entries[len(lib.entries) - 1].name] = id
	return id, true
}

// register_package registers an already-parsed Package. Useful for tests and
// for runtime-compiled variants. The library does not take ownership of `pkg`
// unless `take_ownership` is true.
register_package :: proc(lib: ^Library, name: string, pkg: Package, take_ownership: bool) -> (Shader_Id, bool) {
	if lib == nil || name == "" {
		return Shader_Id_Invalid, false
	}
	if _, dup := lib.name_index[name]; dup {
		return Shader_Id_Invalid, false
	}

	id := Shader_Id(u32(len(lib.entries)) + 1)
	entry := Library_Entry {
		name = strings.clone(name),
		package_owned = take_ownership,
		package_loaded = true,
		pkg = pkg,
		shaders = make([dynamic]Shader_Cache_Entry),
	}

	append(&lib.entries, entry)
	lib.name_index[lib.entries[len(lib.entries) - 1].name] = id
	return id, true
}

// shader_id_for_name returns the id minted by a previous register call.
shader_id_for_name :: proc(lib: ^Library, name: string) -> (Shader_Id, bool) {
	if lib == nil {
		return Shader_Id_Invalid, false
	}
	id, ok := lib.name_index[name]
	return id, ok
}

// permutation_key_set inserts or updates one (axis, value) pair, keeping the
// pair list sorted by axis index so `permutation_key_hash` is canonical.
// Returns false if the key is full or axis is out of range.
permutation_key_set :: proc(key: ^Permutation_Key, axis: u16, value: u16) -> bool {
	if key == nil {
		return false
	}
	for i in 0..<int(key.pair_count) {
		if key.pairs[i].axis == axis {
			key.pairs[i].value = value
			return true
		}
	}
	if int(key.pair_count) >= MAX_PERMUTATION_AXES {
		return false
	}
	insert_at := int(key.pair_count)
	for i in 0..<int(key.pair_count) {
		if key.pairs[i].axis > axis {
			insert_at = i
			break
		}
	}
	for i := int(key.pair_count); i > insert_at; i -= 1 {
		key.pairs[i] = key.pairs[i - 1]
	}
	key.pairs[insert_at] = Permutation_Key_Pair{axis = axis, value = value}
	key.pair_count += 1
	return true
}

// permutation_key_clear resets the key to the all-defaults state.
permutation_key_clear :: proc(key: ^Permutation_Key) {
	if key == nil {
		return
	}
	key.pair_count = 0
}

// permutation_key_hash returns the canonical FNV-1a hash matching the shader
// package writer. Defaults are filled in from the package only by `resolve`,
// so an empty key always hashes to the default-variant identity.
permutation_key_hash :: proc(key: Permutation_Key) -> u64 {
	k := key
	return canonical_key_hash(k.pairs[:int(k.pair_count)])
}

// target_for_backend maps a gfx.Backend to the .ashader Backend_Target the
// runtime should fetch. Returns false for backends without a baked target.
target_for_backend :: proc(backend: gfx.Backend) -> (Backend_Target, bool) {
	switch backend {
	case .D3D12:
		return .D3D12_DXIL, true
	case .Vulkan:
		return .Vulkan_SPIRV, true
	case .Null:
		return .D3D12_DXIL, true
	case .Auto:
		return .D3D12_DXIL, false
	}
	return .D3D12_DXIL, false
}

// resolve maps (id, key) to a backend gfx.Shader, materialising it on first
// use. Subsequent calls with the same key return the cached handle.
//
// On a miss, the library:
//   1. Loads the `.ashader` package if it has not been loaded yet.
//   2. If the package is missing on disk, invokes the source compiler.
//   3. Resolves the canonical key against the package variants, falling back
//      to variant 0 (defaults) when the key matches no declared variant.
//   4. Builds a gfx.Shader_Desc from the variant's stage and binding records
//      and creates a backend shader object.
resolve :: proc(lib: ^Library, ctx: ^gfx.Context, id: Shader_Id, key: Permutation_Key) -> (gfx.Shader, bool) {
	if lib == nil || ctx == nil {
		return gfx.Shader_Invalid, false
	}
	entry := library_entry(lib, id)
	if entry == nil {
		return gfx.Shader_Invalid, false
	}

	target, target_ok := target_for_backend(ctx.backend)
	if !target_ok {
		return gfx.Shader_Invalid, false
	}

	if !ensure_package_loaded(lib, entry) {
		return gfx.Shader_Invalid, false
	}

	variant_index, variant_ok := select_variant(&entry.pkg, key)
	if !variant_ok {
		return gfx.Shader_Invalid, false
	}

	canonical_hash := entry.pkg.variants[variant_index].key_hash
	for record in entry.shaders {
		if record.target == target && record.variant_index == u32(variant_index) {
			return record.shader, true
		}
	}

	desc, desc_ok := variant_shader_desc(&entry.pkg, target, u32(variant_index), entry.name)
	if !desc_ok {
		return gfx.Shader_Invalid, false
	}

	handle, ok := gfx.create_shader(ctx, desc)
	if !ok {
		return gfx.Shader_Invalid, false
	}

	append(&entry.shaders, Shader_Cache_Entry {
		target = target,
		variant_index = u32(variant_index),
		key_hash = canonical_hash,
		shader = handle,
	})
	return handle, true
}

// resolve_pipeline returns a cached gfx.Pipeline keyed by (id, key,
// state_hash). The first call creates the underlying shader (via `resolve`)
// and the pipeline; later calls re-use the same Pipeline handle so reflection
// bindings and pipeline state are not recomputed each frame.
//
// The caller is responsible for the state_hash — anything that affects the
// pipeline state (vertex layout, render formats, depth/raster/blend, label)
// must contribute. The library treats `state_hash` as opaque.
resolve_pipeline :: proc(lib: ^Library, ctx: ^gfx.Context, desc: Library_Pipeline_Desc) -> (gfx.Pipeline, bool) {
	if lib == nil || ctx == nil {
		return gfx.Pipeline_Invalid, false
	}

	shader, shader_ok := resolve(lib, ctx, desc.id, desc.key)
	if !shader_ok {
		return gfx.Pipeline_Invalid, false
	}

	target, _ := target_for_backend(ctx.backend)
	entry := library_entry(lib, desc.id)
	if entry == nil {
		return gfx.Pipeline_Invalid, false
	}
	variant_index, variant_ok := select_variant(&entry.pkg, desc.key)
	if !variant_ok {
		return gfx.Pipeline_Invalid, false
	}

	for record in lib.pipelines {
		if record.id == desc.id &&
		   record.target == target &&
		   record.variant_index == u32(variant_index) &&
		   record.state_hash == desc.state_hash &&
		   record.shader == shader {
			return record.pipeline, true
		}
	}

	final := desc.base
	final.shader = shader
	pipeline, ok := gfx.create_pipeline(ctx, final)
	if !ok {
		return gfx.Pipeline_Invalid, false
	}

	append(&lib.pipelines, Pipeline_Cache_Entry {
		id = desc.id,
		target = target,
		variant_index = u32(variant_index),
		state_hash = desc.state_hash,
		shader = shader,
		pipeline = pipeline,
	})
	return pipeline, true
}

@(private)
library_entry :: proc(lib: ^Library, id: Shader_Id) -> ^Library_Entry {
	if lib == nil || u32(id) == 0 || int(u32(id)) > len(lib.entries) {
		return nil
	}
	return &lib.entries[int(u32(id)) - 1]
}

@(private)
ensure_package_loaded :: proc(lib: ^Library, entry: ^Library_Entry) -> bool {
	if entry.package_loaded {
		return true
	}
	if entry.package_path == "" {
		return false
	}

	if !os.exists(entry.package_path) {
		if lib.compile == nil {
			return false
		}
		if !lib.compile(entry.name, entry.source_path, entry.package_path, lib.compile_user) {
			return false
		}
	}

	pkg, ok := load(entry.package_path)
	if !ok {
		return false
	}

	entry.pkg = pkg
	entry.package_loaded = true
	entry.package_owned = true
	return true
}

@(private)
select_variant :: proc(pkg: ^Package, key: Permutation_Key) -> (int, bool) {
	if pkg == nil || len(pkg.variants) == 0 {
		return 0, false
	}

	k := key
	hash := canonical_key_hash(k.pairs[:int(k.pair_count)])
	if idx, found := find_variant(pkg, hash); found {
		return idx, true
	}

	// Defaults fallback: caller asked for a key with no axes set, which
	// should always resolve to variant 0 — and so should any key whose
	// values exactly match every axis default.
	if key.pair_count == 0 {
		return 0, true
	}
	if all_pairs_are_defaults(pkg, key) {
		return 0, true
	}

	return 0, false
}

@(private)
all_pairs_are_defaults :: proc(pkg: ^Package, key: Permutation_Key) -> bool {
	for i in 0..<int(key.pair_count) {
		pair := key.pairs[i]
		if int(pair.axis) >= len(pkg.axes) {
			return false
		}
		if u32(pair.value) != pkg.axes[int(pair.axis)].default_index {
			return false
		}
	}
	return true
}

@(private)
variant_shader_desc :: proc(pkg: ^Package, target: Backend_Target, variant_index: u32, label: string) -> (gfx.Shader_Desc, bool) {
	if pkg == nil || int(variant_index) >= len(pkg.variants) {
		return {}, false
	}

	variant := pkg.variants[variant_index]
	desc: gfx.Shader_Desc
	desc.label = label
	desc.has_binding_metadata = pkg.version >= 2 && variant.binding_count > 0

	stage_seen: [3]bool
	found := false

	for stage_index in int(variant.stage_first)..<int(variant.stage_first + variant.stage_count) {
		record := pkg.stages[stage_index]
		if record.target != target {
			continue
		}

		stage, stage_ok := to_gfx_stage(record.stage)
		if !stage_ok {
			return {}, false
		}
		if stage_seen[int(stage)] {
			return {}, false
		}
		stage_seen[int(stage)] = true

		bytecode, bytecode_ok := byte_range(pkg, record.bytecode_offset, record.bytecode_size)
		if !bytecode_ok {
			return {}, false
		}

		entry := ""
		if entry_bytes, entry_ok := byte_range(pkg, u64(record.entry_offset), u64(record.entry_size)); entry_ok {
			entry = string(entry_bytes)
		}

		desc.stages[int(stage)] = gfx.Shader_Stage_Desc {
			stage = stage,
			entry = entry,
			bytecode = gfx.Range{ptr = raw_data(bytecode), size = len(bytecode)},
		}
		found = true
	}

	if !found {
		return {}, false
	}

	binding_count := 0
	for binding_index in int(variant.binding_first)..<int(variant.binding_first + variant.binding_count) {
		record := pkg.bindings[binding_index]
		if record.target != target || !record.used {
			continue
		}
		if binding_count >= gfx.MAX_SHADER_BINDINGS {
			return {}, false
		}

		stage, stage_ok := to_gfx_stage(record.stage)
		if !stage_ok {
			return {}, false
		}
		kind, kind_ok := to_gfx_binding_kind(record.kind)
		if !kind_ok {
			return {}, false
		}

		name := ""
		if name_bytes, name_ok := byte_range(pkg, u64(record.name_offset), u64(record.name_size)); name_ok {
			name = string(name_bytes)
		}

		desc.bindings[binding_count] = gfx.Shader_Binding_Desc {
			active = true,
			stage = stage,
			kind = kind,
			group = record.group,
			slot = record.logical_slot,
			native_slot = record.slot,
			native_space = record.native_space,
			name = name,
			size = record.size,
			view_kind = record.view_kind,
			access = record.access,
			storage_image_format = record.storage_image_format,
			storage_buffer_stride = record.storage_buffer_stride,
		}
		binding_count += 1
	}

	vertex_input_count := 0
	for record in pkg.vertex_inputs {
		if !record.used {
			continue
		}
		if vertex_input_count >= gfx.MAX_VERTEX_ATTRIBUTES {
			return {}, false
		}

		semantic := ""
		if semantic_bytes, semantic_ok := byte_range(pkg, u64(record.semantic_offset), u64(record.semantic_size)); semantic_ok {
			semantic = string(semantic_bytes)
		}

		desc.vertex_inputs[vertex_input_count] = gfx.Shader_Vertex_Input_Desc {
			active = true,
			semantic = semantic,
			semantic_index = record.semantic_index,
			format = record.format,
		}
		vertex_input_count += 1
	}
	desc.has_vertex_input_metadata = vertex_input_count > 0

	return desc, true
}
