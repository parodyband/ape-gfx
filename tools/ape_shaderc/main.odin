package main

import "core:fmt"
import json "core:encoding/json"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

PACKAGE_MAGIC :: u32(0x48535041) // "APSH"
PACKAGE_VERSION :: u32(8)
PACKAGE_HEADER_SIZE :: 20
PACKAGE_STAGE_RECORD_SIZE :: 48
PACKAGE_BINDING_RECORD_SIZE :: 56
PACKAGE_VERTEX_INPUT_RECORD_SIZE :: 20

Target :: enum u32 {
	D3D11_DXBC,
	Vulkan_SPIRV,
}

Stage :: enum u32 {
	Vertex,
	Fragment,
	Compute,
}

Shader_Kind :: enum {
	Graphics,
	Compute,
}

Binding_Kind :: enum u32 {
	Uniform_Block,
	Resource_View,
	Sampler,
}

Resource_View_Kind :: enum u32 {
	Sampled,
	Storage_Image,
	Storage_Buffer,
}

Resource_Access :: enum u32 {
	Unknown,
	Read,
	Write,
	Read_Write,
}

Storage_Image_Format :: enum u32 {
	Invalid = 0,
	RGBA32F = 4,
	R32F    = 5,
}

Stage_Desc :: struct {
	target: Target,
	stage: Stage,
	entry: string,
	bytecode_path: string,
	reflection_path: string,
}

Compiled_Stage :: struct {
	target: Target,
	stage: Stage,
	entry: string,
	bytecode: []byte,
	reflection: []byte,
}

Stage_Record :: struct {
	target: Target,
	stage: Stage,
	entry_offset: u32,
	entry_size: u32,
	bytecode_offset: u64,
	bytecode_size: u64,
	reflection_offset: u64,
	reflection_size: u64,
}

Binding_Record :: struct {
	target: Target,
	stage: Stage,
	kind: Binding_Kind,
	slot: u32,
	space: u32,
	logical_slot: u32,
	name: string,
	name_offset: u32,
	name_size: u32,
	size: u32,
	view_kind: Resource_View_Kind,
	access: Resource_Access,
	storage_image_format: Storage_Image_Format,
	storage_buffer_stride: u32,
}

Binding_Group_Layout_Entry :: struct {
	kind: Binding_Kind,
	logical_slot: u32,
	name: string,
	stages: [3]bool,
	size: u32,
	view_kind: Resource_View_Kind,
	access: Resource_Access,
	storage_image_format: Storage_Image_Format,
	storage_buffer_stride: u32,
}

Reflection_Parameter :: struct {
	name: string,
	binding_kind: string,
	slot: u32,
	type_value: json.Value,
}

Reflection_Model :: struct {
	value: json.Value,
	root: json.Object,
	parameters: [dynamic]Reflection_Parameter,
}

Uniform_Block :: struct {
	name: string,
	size: u32,
	alignment: u32,
	fields: [dynamic]Uniform_Field,
}

Uniform_Field :: struct {
	name: string,
	odin_type: string,
	offset: u32,
	size: u32,
	host_size: u32,
}

Generated_Vertex_Format :: enum {
	Float32,
	Float32x2,
	Float32x3,
	Float32x4,
}

Generated_Vertex_Attribute :: struct {
	semantic: string,
	semantic_index: u32,
	format: Generated_Vertex_Format,
	offset: u32,
	size: u32,
}

Generated_Vertex_Layout :: struct {
	attrs: [dynamic]Generated_Vertex_Attribute,
	stride: u32,
}

Compute_Thread_Group_Size :: struct {
	valid: bool,
	x: u32,
	y: u32,
	z: u32,
}

Shader_Job :: struct {
	name: string,
	kind: Shader_Kind,
}

Shader_Build_Result :: struct {
	compiled: [dynamic]Compiled_Stage,
	bindings: [dynamic]Binding_Record,
	uniform_blocks: [dynamic]Uniform_Block,
	vertex_layout: Generated_Vertex_Layout,
	compute_thread_group: Compute_Thread_Group_Size,
}

Modern_Slang_Context :: struct {
	global_session: ^ISlangGlobalSession,
	session: ^ISlangSession,
}

Options :: struct {
	shader_name: string,
	source_path: string,
	build_dir: string,
	package_path: string,
	generated_path: string,
	kind: Shader_Kind,
	all: bool,
	probe_modern_api: bool,
}

SAMPLE_SHADER_JOBS :: [?]Shader_Job {
	{name = "triangle", kind = .Graphics},
	{name = "cube", kind = .Graphics},
	{name = "textured_quad", kind = .Graphics},
	{name = "textured_cube", kind = .Graphics},
	{name = "depth_visualize", kind = .Graphics},
	{name = "shadow_depth", kind = .Graphics},
	{name = "improved_shadows", kind = .Graphics},
	{name = "mrt", kind = .Graphics},
}

main :: proc() {
	options, options_ok := parse_options(os.args[1:])
	if !options_ok {
		print_usage()
		os.exit(1)
	}

	if !pack(options) {
		os.exit(1)
	}
}

parse_options :: proc(args: []string) -> (Options, bool) {
	options := Options {
		build_dir = "build/shaders",
		kind = .Graphics,
	}
	kind_set := false

	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		if arg == "-all" {
			options.all = true
		} else if arg == "-probe-modern-api" {
			options.probe_modern_api = true
		} else if arg == "-shader-name" {
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.shader_name = args[i]
		} else if arg == "-source" {
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.source_path = args[i]
		} else if arg == "-build-dir" {
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.build_dir = args[i]
		} else if arg == "-package" {
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.package_path = args[i]
		} else if arg == "-generated" {
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.generated_path = args[i]
		} else if arg == "-kind" {
			i += 1
			if i >= len(args) {
				return {}, false
			}
			kind_set = true
			switch args[i] {
			case "graphics":
				options.kind = .Graphics
			case "compute":
				options.kind = .Compute
			case:
				return {}, false
			}
		} else {
			return {}, false
		}
	}

	if options.probe_modern_api {
		if options.all ||
		   options.shader_name != "" ||
		   kind_set ||
		   options.source_path != "" ||
		   options.package_path != "" ||
		   options.generated_path != "" {
			return {}, false
		}

		return options, true
	}

	if options.all {
		if options.shader_name != "" ||
		   kind_set ||
		   options.source_path != "" ||
		   options.package_path != "" ||
		   options.generated_path != "" {
			return {}, false
		}

		return options, true
	}

	if options.shader_name == "" {
		return {}, false
	}
	complete_default_paths(&options)

	return options, true
}

complete_default_paths :: proc(options: ^Options) {
	if options.source_path == "" {
		options.source_path = filepath.join({"assets/shaders", fmt.tprintf("%s.slang", options.shader_name)})
	}
	if options.package_path == "" {
		options.package_path = filepath.join({options.build_dir, fmt.tprintf("%s.ashader", options.shader_name)})
	}
	if options.generated_path == "" {
		options.generated_path = filepath.join({"assets/shaders/generated", options.shader_name, "bindings.odin"})
	}
}

print_usage :: proc() {
	fmt.eprintln("usage: ape_shaderc -shader-name <name> [-kind graphics|compute] [-source <path>] [-build-dir <dir>] [-package <path>] [-generated <path>]")
	fmt.eprintln("       ape_shaderc -all [-build-dir <dir>]")
	fmt.eprintln("       ape_shaderc -probe-modern-api")
}

pack :: proc(options: Options) -> bool {
	if options.probe_modern_api {
		return run_modern_slang_api_probe()
	}

	slang: Slang_API
	if !load_slang_api(&slang) {
		return false
	}
	defer unload_slang_api(&slang)

	ctx, context_ok := create_modern_slang_context(&slang)
	if !context_ok {
		return false
	}
	defer destroy_modern_slang_context(&ctx)

	if options.all {
		for job in SAMPLE_SHADER_JOBS {
			job_options := options
			job_options.all = false
			job_options.shader_name = job.name
			job_options.kind = job.kind
			job_options.source_path = ""
			job_options.package_path = ""
			job_options.generated_path = ""
			complete_default_paths(&job_options)
			if !pack_shader(&slang, ctx.session, job_options) {
				return false
			}
		}

		fmt.println("Packed", len(SAMPLE_SHADER_JOBS), "shader packages to", options.build_dir)
		return true
	}

	return pack_shader(&slang, ctx.session, options)
}

pack_shader :: proc(slang: ^Slang_API, session: ^ISlangSession, options: Options) -> bool {
	result: Shader_Build_Result
	defer delete_shader_build_result(&result)

	if !build_shader(slang, session, options, &result) {
		return false
	}

	if !write_generated_bindings(options, result.bindings[:], result.uniform_blocks[:], result.vertex_layout, result.compute_thread_group) {
		return false
	}

	if !write_package(options, result.compiled[:], result.bindings[:], result.vertex_layout) {
		return false
	}

	fmt.println("Packed", options.shader_name, "shader package to", options.package_path)
	return true
}

create_modern_slang_context :: proc(slang: ^Slang_API) -> (Modern_Slang_Context, bool) {
	global_desc := Slang_Global_Session_Desc {
		structureSize = u32(size_of(Slang_Global_Session_Desc)),
		apiVersion = SLANG_API_VERSION,
		languageVersion = SLANG_LANGUAGE_VERSION_2025,
	}

	global_session: ^ISlangGlobalSession
	result := slang.slang_createGlobalSession2(&global_desc, &global_session)
	if slang_failed(result) || global_session == nil {
		fmt.eprintln("ape_shaderc: slang_createGlobalSession2 failed")
		return {}, false
	}

	dxbc_profile := global_session.vtable.findProfile(global_session, cstring("sm_5_0"))
	spirv_profile := global_session.vtable.findProfile(global_session, cstring("glsl_450"))
	if dxbc_profile == SLANG_PROFILE_UNKNOWN || spirv_profile == SLANG_PROFILE_UNKNOWN {
		fmt.eprintln("ape_shaderc: failed to resolve modern Slang target profiles")
		release_slang_unknown(cast(^ISlangUnknown)global_session)
		return {}, false
	}

	targets := [?]Slang_Target_Desc {
		{structureSize = uint(size_of(Slang_Target_Desc)), format = SLANG_TARGET_DXBC, profile = dxbc_profile},
		{structureSize = uint(size_of(Slang_Target_Desc)), format = SLANG_TARGET_SPIRV, profile = spirv_profile},
	}
	session_desc := Slang_Session_Desc {
		structureSize = uint(size_of(Slang_Session_Desc)),
		targets = &targets[0],
		targetCount = SlangInt(len(targets)),
		defaultMatrixLayoutMode = SLANG_MATRIX_LAYOUT_ROW_MAJOR,
	}

	session: ^ISlangSession
	result = global_session.vtable.createSession(global_session, &session_desc, &session)
	if slang_failed(result) || session == nil {
		fmt.eprintln("ape_shaderc: failed to create modern Slang session")
		release_slang_unknown(cast(^ISlangUnknown)global_session)
		return {}, false
	}

	return Modern_Slang_Context {
		global_session = global_session,
		session = session,
	}, true
}

destroy_modern_slang_context :: proc(ctx: ^Modern_Slang_Context) {
	if ctx == nil {
		return
	}

	if ctx.session != nil {
		release_slang_unknown(cast(^ISlangUnknown)ctx.session)
	}
	if ctx.global_session != nil {
		release_slang_unknown(cast(^ISlangUnknown)ctx.global_session)
	}
	ctx^ = {}
}

build_shader :: proc(slang: ^Slang_API, session: ^ISlangSession, options: Options, result: ^Shader_Build_Result) -> bool {
	stages: [dynamic]Stage_Desc
	defer delete(stages)
	append_stage_descs(&stages, options)

	result^ = {}

	source_bytes, source_ok := os.read_entire_file(options.source_path)
	if !source_ok {
		fmt.eprintln("ape_shaderc: failed to read Slang source: ", options.source_path)
		return false
	}
	defer delete(source_bytes)

	source_c, source_err := strings.clone_to_cstring(string(source_bytes), context.temp_allocator)
	if source_err != nil {
		fmt.eprintln("ape_shaderc: failed to prepare Slang source for modern compile")
		return false
	}
	module_name_c, module_name_err := strings.clone_to_cstring(options.shader_name, context.temp_allocator)
	if module_name_err != nil {
		fmt.eprintln("ape_shaderc: failed to prepare Slang module name")
		return false
	}
	source_path_c, source_path_err := strings.clone_to_cstring(options.source_path, context.temp_allocator)
	if source_path_err != nil {
		fmt.eprintln("ape_shaderc: failed to prepare Slang source path")
		return false
	}

	diagnostics: ^ISlangBlob
	module := session.vtable.loadModuleFromSourceString(session, module_name_c, source_path_c, source_c, &diagnostics)
	if diagnostics != nil {
		if module == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
		diagnostics = nil
	}
	if module == nil {
		fmt.eprintln("ape_shaderc: modern Slang failed to load module: ", options.source_path)
		return false
	}
	defer release_slang_unknown(cast(^ISlangUnknown)module)

	for stage in stages {
		compiled_stage, compile_ok := compile_modern_component_stage(
			slang,
			session,
			module,
			options,
			stage,
			&result.bindings,
			&result.uniform_blocks,
			&result.vertex_layout,
			&result.compute_thread_group,
		)
		if !compile_ok {
			delete_shader_build_result(result)
			return false
		}
		append(&result.compiled, compiled_stage)
	}

	if !assign_logical_binding_slots(&result.bindings) {
		delete_shader_build_result(result)
		return false
	}

	return true
}

compile_modern_component_stage :: proc(
	slang: ^Slang_API,
	session: ^ISlangSession,
	module: ^ISlangModule,
	options: Options,
	stage: Stage_Desc,
	bindings: ^[dynamic]Binding_Record,
	uniform_blocks: ^[dynamic]Uniform_Block,
	vertex_layout: ^Generated_Vertex_Layout,
	compute_thread_group: ^Compute_Thread_Group_Size,
) -> (Compiled_Stage, bool) {
	slang_stage, slang_stage_ok := slang_stage_for_stage(stage.stage)
	if !slang_stage_ok {
		fmt.eprintln("ape_shaderc: unsupported modern Slang stage: ", stage.entry)
		return {}, false
	}

	entry_name_c, entry_name_err := strings.clone_to_cstring(stage.entry, context.temp_allocator)
	if entry_name_err != nil {
		fmt.eprintln("ape_shaderc: failed to prepare modern Slang entry name")
		return {}, false
	}

	diagnostics: ^ISlangBlob
	entry_point: ^ISlangEntryPoint
	result := module.vtable.findAndCheckEntryPoint(module, entry_name_c, slang_stage, &entry_point, &diagnostics)
	if diagnostics != nil {
		if slang_failed(result) || entry_point == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
		diagnostics = nil
	}
	if slang_failed(result) || entry_point == nil {
		fmt.eprintln("ape_shaderc: modern Slang failed to find entry point: ", stage.entry)
		return {}, false
	}
	defer release_slang_unknown(cast(^ISlangUnknown)entry_point)

	component_types := [?]^ISlangComponentType {
		cast(^ISlangComponentType)module,
		cast(^ISlangComponentType)entry_point,
	}

	composite: ^ISlangComponentType
	diagnostics = nil
	result = session.vtable.createCompositeComponentType(session, raw_data(component_types[:]), SlangInt(len(component_types)), &composite, &diagnostics)
	if diagnostics != nil {
		if slang_failed(result) || composite == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
		diagnostics = nil
	}
	if slang_failed(result) || composite == nil {
		fmt.eprintln("ape_shaderc: modern Slang failed to create composite component for ", stage.entry)
		return {}, false
	}
	// Slang's linked component keeps internal ownership tied to the composite.
	// Holding our own reference avoids release-order heap corruption on exit.
	_ = (cast(^ISlangUnknown)composite).vtable.addRef(cast(^ISlangUnknown)composite)
	defer release_slang_unknown(cast(^ISlangUnknown)composite)

	linked: ^ISlangComponentType
	diagnostics = nil
	result = composite.vtable.link(composite, &linked, &diagnostics)
	if diagnostics != nil {
		if slang_failed(result) || linked == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
		diagnostics = nil
	}
	if slang_failed(result) || linked == nil {
		fmt.eprintln("ape_shaderc: modern Slang failed to link component for ", stage.entry)
		return {}, false
	}
	defer release_slang_unknown(cast(^ISlangUnknown)linked)

	target_index, target_index_ok := modern_target_index(stage.target)
	if !target_index_ok {
		fmt.eprintln("ape_shaderc: unsupported modern Slang target for ", stage.entry)
		return {}, false
	}

	code_blob: ^ISlangBlob
	diagnostics = nil
	result = linked.vtable.getEntryPointCode(linked, 0, target_index, &code_blob, &diagnostics)
	if diagnostics != nil {
		if slang_failed(result) || code_blob == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
		diagnostics = nil
	}
	if slang_failed(result) || code_blob == nil {
		fmt.eprintln("ape_shaderc: modern Slang failed to compile bytecode for ", stage.entry)
		return {}, false
	}
	defer release_slang_blob(cast(rawptr)code_blob)

	bytecode := copy_blob_bytes(cast(rawptr)code_blob)
	if bytecode == nil {
		fmt.eprintln("ape_shaderc: failed to copy modern Slang bytecode for ", stage.entry)
		return {}, false
	}

	if !write_stage_artifact(stage.bytecode_path, bytecode, "modern bytecode") {
		delete(bytecode)
		return {}, false
	}

	reflection_blob: rawptr
	layout: rawptr
	reflection, reflection_ok := get_modern_reflection_json(slang, linked, target_index, &layout, &reflection_blob)
	if !reflection_ok {
		delete(bytecode)
		return {}, false
	}
	defer release_slang_blob(reflection_blob)

	reflection_model, reflection_model_ok := parse_reflection_model(options, stage, reflection)
	if !reflection_model_ok {
		delete(bytecode)
		delete(reflection)
		return {}, false
	}
	defer delete_reflection_model(&reflection_model)

	metadata: ^ISlangMetadata
	if !get_modern_entry_point_metadata(linked, target_index, &metadata) {
		delete(bytecode)
		delete(reflection)
		return {}, false
	}
	defer release_slang_unknown(cast(^ISlangUnknown)metadata)

	if !collect_bindings_from_reflection(slang, metadata, layout, stage, reflection_model, bindings, uniform_blocks) {
		delete(bytecode)
		delete(reflection)
		return {}, false
	}

	if stage.stage == .Vertex && stage.entry == "vs_main" {
		stage_vertex_layout: Generated_Vertex_Layout
		if !collect_vertex_layout_from_reflection(options, stage, reflection_model.root, &stage_vertex_layout) {
			delete(bytecode)
			delete(reflection)
			delete_vertex_layout(&stage_vertex_layout)
			return {}, false
		}
		if !merge_vertex_layout(vertex_layout, &stage_vertex_layout) {
			delete(bytecode)
			delete(reflection)
			delete_vertex_layout(&stage_vertex_layout)
			return {}, false
		}
		delete_vertex_layout(&stage_vertex_layout)
	}

	if stage.stage == .Compute && stage.entry == "cs_main" {
		stage_compute_thread_group: Compute_Thread_Group_Size
		if !collect_compute_thread_group_from_reflection(options, stage, reflection_model.root, &stage_compute_thread_group) {
			delete(bytecode)
			delete(reflection)
			return {}, false
		}
		if !merge_compute_thread_group(compute_thread_group, stage_compute_thread_group) {
			delete(bytecode)
			delete(reflection)
			return {}, false
		}
	}

	if !write_stage_artifact(stage.reflection_path, reflection, "reflection") {
		delete(bytecode)
		delete(reflection)
		return {}, false
	}

	return Compiled_Stage {
		target = stage.target,
		stage = stage.stage,
		entry = stage.entry,
		bytecode = bytecode,
		reflection = reflection,
	}, true
}

get_modern_reflection_json :: proc(
	slang: ^Slang_API,
	linked: ^ISlangComponentType,
	target_index: SlangInt,
	out_layout: ^rawptr,
	out_blob: ^rawptr,
) -> ([]byte, bool) {
	diagnostics: ^ISlangBlob
	layout := linked.vtable.getLayout(linked, target_index, &diagnostics)
	if diagnostics != nil {
		if layout == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
	}
	if layout == nil {
		fmt.eprintln("ape_shaderc: modern Slang returned no program layout")
		return nil, false
	}
	out_layout^ = layout

	result := slang.spReflection_ToJson(layout, nil, out_blob)
	if slang_failed(result) || out_blob^ == nil {
		fmt.eprintln("ape_shaderc: failed to serialize modern Slang reflection JSON")
		return nil, false
	}

	reflection := copy_blob_bytes(out_blob^)
	if reflection == nil {
		fmt.eprintln("ape_shaderc: failed to copy modern Slang reflection JSON")
		return nil, false
	}

	return reflection, true
}

get_modern_entry_point_metadata :: proc(
	linked: ^ISlangComponentType,
	target_index: SlangInt,
	out_metadata: ^^ISlangMetadata,
) -> bool {
	diagnostics: ^ISlangBlob
	result := linked.vtable.getEntryPointMetadata(linked, 0, target_index, out_metadata, &diagnostics)
	if diagnostics != nil {
		if slang_failed(result) || out_metadata^ == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
	}
	if slang_failed(result) || out_metadata^ == nil {
		fmt.eprintln("ape_shaderc: modern Slang returned no entry-point metadata")
		return false
	}

	return true
}

slang_stage_for_stage :: proc(stage: Stage) -> (SlangStage, bool) {
	switch stage {
	case .Vertex:
		return SLANG_STAGE_VERTEX, true
	case .Fragment:
		return SLANG_STAGE_FRAGMENT, true
	case .Compute:
		return SLANG_STAGE_COMPUTE, true
	}

	return 0, false
}

modern_target_index :: proc(target: Target) -> (SlangInt, bool) {
	switch target {
	case .D3D11_DXBC:
		return 0, true
	case .Vulkan_SPIRV:
		return 1, true
	}

	return 0, false
}

append_stage_descs :: proc(stages: ^[dynamic]Stage_Desc, options: Options) {
	if options.kind == .Compute {
		append(stages, Stage_Desc {
			target = .D3D11_DXBC,
			stage = .Compute,
			entry = "cs_main",
			bytecode_path = filepath.join({options.build_dir, fmt.tprintf("%s.cs.dxbc", options.shader_name)}),
			reflection_path = filepath.join({options.build_dir, fmt.tprintf("%s.cs.dxbc.json", options.shader_name)}),
		})
		append(stages, Stage_Desc {
			target = .Vulkan_SPIRV,
			stage = .Compute,
			entry = "cs_main",
			bytecode_path = filepath.join({options.build_dir, fmt.tprintf("%s.cs.spv", options.shader_name)}),
			reflection_path = filepath.join({options.build_dir, fmt.tprintf("%s.cs.spv.json", options.shader_name)}),
		})
		return
	}

	append(stages, Stage_Desc {
		target = .D3D11_DXBC,
		stage = .Vertex,
		entry = "vs_main",
		bytecode_path = filepath.join({options.build_dir, fmt.tprintf("%s.vs.dxbc", options.shader_name)}),
		reflection_path = filepath.join({options.build_dir, fmt.tprintf("%s.vs.dxbc.json", options.shader_name)}),
	})
	append(stages, Stage_Desc {
		target = .D3D11_DXBC,
		stage = .Fragment,
		entry = "fs_main",
		bytecode_path = filepath.join({options.build_dir, fmt.tprintf("%s.fs.dxbc", options.shader_name)}),
		reflection_path = filepath.join({options.build_dir, fmt.tprintf("%s.fs.dxbc.json", options.shader_name)}),
	})
	append(stages, Stage_Desc {
		target = .Vulkan_SPIRV,
		stage = .Vertex,
		entry = "vs_main",
		bytecode_path = filepath.join({options.build_dir, fmt.tprintf("%s.vs.spv", options.shader_name)}),
		reflection_path = filepath.join({options.build_dir, fmt.tprintf("%s.vs.spv.json", options.shader_name)}),
	})
	append(stages, Stage_Desc {
		target = .Vulkan_SPIRV,
		stage = .Fragment,
		entry = "fs_main",
		bytecode_path = filepath.join({options.build_dir, fmt.tprintf("%s.fs.spv", options.shader_name)}),
		reflection_path = filepath.join({options.build_dir, fmt.tprintf("%s.fs.spv.json", options.shader_name)}),
	})
}

collect_bindings_from_reflection :: proc(
	slang: ^Slang_API,
	metadata: ^ISlangMetadata,
	reflection: rawptr,
	stage: Stage_Desc,
	reflection_model: Reflection_Model,
	bindings: ^[dynamic]Binding_Record,
	uniform_blocks: ^[dynamic]Uniform_Block,
) -> bool {
	parameter_count := slang.spReflection_GetParameterCount(reflection)
	for i in 0..<int(parameter_count) {
		parameter := slang.spReflection_GetParameterByIndex(reflection, u32(i))
		if parameter == nil {
			continue
		}

		type_layout := slang.spReflectionVariableLayout_GetTypeLayout(parameter)
		if type_layout == nil {
			continue
		}

		category := slang.spReflectionTypeLayout_GetParameterCategory(type_layout)
		slot := slang.spReflectionParameter_GetBindingIndex(parameter)
		space := slang.spReflectionParameter_GetBindingSpace(parameter)
		used := false
		result := metadata.vtable.isParameterLocationUsed(
			metadata,
			category,
			SlangUInt(space),
			SlangUInt(slot),
			&used,
		)
		if slang_failed(result) {
			fmt.eprintln("ape_shaderc: failed to query Slang entry-point parameter usage")
			return false
		}
		if !used {
			continue
		}

		variable := slang.spReflectionVariableLayout_GetVariable(parameter)
		name := "binding"
		if variable != nil {
			name_c := slang.spReflectionVariable_GetName(variable)
			if name_c != nil {
				cloned_name, err := strings.clone_from_cstring(name_c)
				if err == nil && cloned_name != "" {
					name = cloned_name
				}
			}
		}

		if name == "binding" {
			cloned_name, err := strings.clone(name)
			if err != nil {
				return false
			}
			name = cloned_name
		}

		kind, kind_ok := binding_kind_from_category(category)
		if !kind_ok && category == .Descriptor_Table_Slot {
			kind, kind_ok = binding_kind_from_descriptor_parameter(reflection_model, name, slot)
		}
		if !kind_ok {
			continue
		}

		binding_size: u32
		view_kind := Resource_View_Kind.Sampled
		access := Resource_Access.Unknown
		storage_image_format := Storage_Image_Format.Invalid
		storage_buffer_stride: u32
		if kind == .Uniform_Block {
			block_size, block_ok := collect_uniform_block(slang, type_layout, name, uniform_blocks)
			if !block_ok {
				return false
			}
			binding_size = block_size
		} else if kind == .Resource_View {
			metadata_kind, metadata_access, metadata_format, metadata_stride, metadata_ok := resource_view_metadata_from_reflection(
				reflection_model,
				name,
				category,
				slot,
			)
			if !metadata_ok {
				fmt.eprintln("ape_shaderc: failed to classify reflected resource view: ", name)
				return false
			}
			view_kind = metadata_kind
			access = metadata_access
			storage_image_format = metadata_format
			storage_buffer_stride = metadata_stride
		}

		append(bindings, Binding_Record {
			target = stage.target,
			stage = stage.stage,
			kind = kind,
			slot = slot,
			space = space,
			name = name,
			size = binding_size,
			view_kind = view_kind,
			access = access,
			storage_image_format = storage_image_format,
			storage_buffer_stride = storage_buffer_stride,
		})
	}

	return true
}

assign_logical_binding_slots :: proc(bindings: ^[dynamic]Binding_Record) -> bool {
	next_slots: [3]u32

	for i in 0..<len(bindings^) {
		binding := &bindings^[i]
		if slot, found := find_existing_logical_binding(bindings^[:i], binding.kind, binding.name); found {
			binding.logical_slot = slot
			continue
		}

		kind_index := int(binding.kind)
		if next_slots[kind_index] >= binding_kind_limit(binding.kind) {
			fmt.eprintln("ape_shaderc: too many reflected ", binding_prefix(binding.kind), " bindings")
			return false
		}

		binding.logical_slot = next_slots[kind_index]
		next_slots[kind_index] += 1
	}

	return true
}

find_existing_logical_binding :: proc(bindings: []Binding_Record, kind: Binding_Kind, name: string) -> (u32, bool) {
	for binding in bindings {
		if binding.kind == kind && binding.name == name {
			return binding.logical_slot, true
		}
	}

	return 0, false
}

binding_kind_limit :: proc(kind: Binding_Kind) -> u32 {
	switch kind {
	case .Uniform_Block:
		return 16
	case .Resource_View:
		return 32
	case .Sampler:
		return 16
	}

	return 0
}

parse_reflection_model :: proc(options: Options, stage: Stage_Desc, reflection_json: []byte) -> (Reflection_Model, bool) {
	value, err := json.parse(reflection_json)
	if err != nil {
		fmt.eprintln("ape_shaderc: failed to parse Slang reflection JSON: ", options.source_path, ":", stage.entry)
		return {}, false
	}

	root, root_ok := json_object(value)
	if !root_ok {
		json.destroy_value(value)
		fmt.eprintln("ape_shaderc: Slang reflection root is not an object: ", options.source_path, ":", stage.entry)
		return {}, false
	}

	model := Reflection_Model {
		value = value,
		root = root,
	}

	parameters_value, parameters_ok := json_field(root, "parameters")
	if !parameters_ok {
		return model, true
	}

	parameters, parameters_array_ok := json_array(parameters_value)
	if !parameters_array_ok {
		delete_reflection_model(&model)
		fmt.eprintln("ape_shaderc: Slang reflection parameters field is not an array: ", options.source_path, ":", stage.entry)
		return {}, false
	}

	for parameter_value in parameters {
		parameter, parameter_ok := json_object(parameter_value)
		if !parameter_ok {
			continue
		}

		name, name_ok := json_string_field(parameter, "name")
		if !name_ok || name == "" {
			continue
		}

		binding_value, binding_ok := json_field(parameter, "binding")
		if !binding_ok {
			continue
		}
		binding, binding_object_ok := json_object(binding_value)
		if !binding_object_ok {
			continue
		}

		binding_kind, binding_kind_ok := json_string_field(binding, "kind")
		slot, slot_ok := json_u32_field(binding, "index")
		type_value, type_ok := json_field(parameter, "type")
		if !binding_kind_ok || !slot_ok || !type_ok {
			continue
		}

		append(&model.parameters, Reflection_Parameter {
			name = name,
			binding_kind = binding_kind,
			slot = slot,
			type_value = type_value,
		})
	}

	return model, true
}

delete_reflection_model :: proc(model: ^Reflection_Model) {
	if model == nil {
		return
	}

	if model.parameters != nil {
		delete(model.parameters)
	}
	json.destroy_value(model.value)
	model^ = {}
}

reflection_parameter_by_binding :: proc(model: Reflection_Model, name: string, binding_kind: string, slot: u32) -> (Reflection_Parameter, bool) {
	for parameter in model.parameters {
		if parameter.name == name && parameter.binding_kind == binding_kind && parameter.slot == slot {
			return parameter, true
		}
	}

	return {}, false
}

collect_vertex_layout_from_reflection :: proc(
	options: Options,
	stage: Stage_Desc,
	root: json.Object,
	out_layout: ^Generated_Vertex_Layout,
) -> bool {
	entry_points_value, entry_points_ok := json_field(root, "entryPoints")
	if !entry_points_ok {
		fmt.eprintln("ape_shaderc: Slang reflection has no entryPoints array: ", options.source_path, ":", stage.entry)
		return false
	}

	entry_points, entry_points_array_ok := json_array(entry_points_value)
	if !entry_points_array_ok {
		fmt.eprintln("ape_shaderc: Slang reflection entryPoints field is not an array: ", options.source_path, ":", stage.entry)
		return false
	}

	for entry_point_value in entry_points {
		entry_point, entry_point_ok := json_object(entry_point_value)
		if !entry_point_ok {
			continue
		}

		name, name_ok := json_string_field(entry_point, "name")
		stage_name, stage_ok := json_string_field(entry_point, "stage")
		if !name_ok || !stage_ok || name != stage.entry || stage_name != "vertex" {
			continue
		}

		parameters_value, parameters_ok := json_field(entry_point, "parameters")
		if !parameters_ok {
			fmt.eprintln("ape_shaderc: vertex entry point has no parameters: ", options.source_path, ":", stage.entry)
			return false
		}

		parameters, parameters_array_ok := json_array(parameters_value)
		if !parameters_array_ok {
			fmt.eprintln("ape_shaderc: vertex entry point parameters field is not an array: ", options.source_path, ":", stage.entry)
			return false
		}

		for parameter_value in parameters {
			parameter, parameter_ok := json_object(parameter_value)
			if !parameter_ok {
				continue
			}

			binding_value, binding_ok := json_field(parameter, "binding")
			if !binding_ok {
				continue
			}

			binding, binding_object_ok := json_object(binding_value)
			if !binding_object_ok {
				continue
			}

			binding_kind, binding_kind_ok := json_string_field(binding, "kind")
			if !binding_kind_ok || binding_kind != "varyingInput" {
				continue
			}

			type_value, type_ok := json_field(parameter, "type")
			if !type_ok {
				fmt.eprintln("ape_shaderc: vertex input parameter has no type: ", options.source_path, ":", stage.entry)
				return false
			}

			if !collect_vertex_attributes_from_type(options, stage, type_value, out_layout) {
				return false
			}
		}

		return true
	}

	fmt.eprintln("ape_shaderc: Slang reflection has no vertex entry point named ", stage.entry, ": ", options.source_path)
	return false
}

collect_vertex_attributes_from_type :: proc(
	options: Options,
	stage: Stage_Desc,
	type_value: json.Value,
	out_layout: ^Generated_Vertex_Layout,
) -> bool {
	type_object, type_object_ok := json_object(type_value)
	if !type_object_ok {
		fmt.eprintln("ape_shaderc: vertex input type is not an object: ", options.source_path, ":", stage.entry)
		return false
	}

	kind, kind_ok := json_string_field(type_object, "kind")
	if !kind_ok {
		fmt.eprintln("ape_shaderc: vertex input type has no kind: ", options.source_path, ":", stage.entry)
		return false
	}
	if kind != "struct" {
		fmt.eprintln("ape_shaderc: generated vertex layouts only support struct vertex inputs: ", options.source_path, ":", stage.entry)
		return false
	}

	fields_value, fields_ok := json_field(type_object, "fields")
	if !fields_ok {
		fmt.eprintln("ape_shaderc: vertex input struct has no fields: ", options.source_path, ":", stage.entry)
		return false
	}

	fields, fields_array_ok := json_array(fields_value)
	if !fields_array_ok {
		fmt.eprintln("ape_shaderc: vertex input fields value is not an array: ", options.source_path, ":", stage.entry)
		return false
	}

	for field_value in fields {
		field, field_ok := json_object(field_value)
		if !field_ok {
			continue
		}

		semantic_name, semantic_ok := json_string_field(field, "semanticName")
		if !semantic_ok || semantic_name == "" {
			fmt.eprintln("ape_shaderc: vertex input field is missing a semanticName: ", options.source_path, ":", stage.entry)
			return false
		}

		semantic, semantic_index, semantic_parse_ok := parse_vertex_semantic(semantic_name)
		if !semantic_parse_ok {
			fmt.eprintln("ape_shaderc: failed to parse vertex semantic: ", semantic_name)
			return false
		}
		defer delete(semantic)

		if semantic_index != 0 {
			fmt.eprintln("ape_shaderc: generated vertex layouts do not support nonzero semantic indices yet: ", semantic_name)
			return false
		}
		if vertex_layout_has_semantic(out_layout^, semantic, semantic_index) {
			fmt.eprintln("ape_shaderc: generated vertex layouts do not support duplicate vertex semantics: ", semantic_name)
			return false
		}

		field_type_value, field_type_ok := json_field(field, "type")
		if !field_type_ok {
			fmt.eprintln("ape_shaderc: vertex input field has no type: ", semantic_name)
			return false
		}

		format, size, format_ok := generated_vertex_format_from_json(field_type_value)
		if !format_ok {
			fmt.eprintln("ape_shaderc: unsupported vertex input type for generated layout: ", semantic_name)
			return false
		}

		semantic_clone, clone_err := strings.clone(semantic)
		if clone_err != nil {
			return false
		}

		append(&out_layout.attrs, Generated_Vertex_Attribute {
			semantic = semantic_clone,
			semantic_index = semantic_index,
			format = format,
			offset = out_layout.stride,
			size = size,
		})
		out_layout.stride += size
	}

	return true
}

collect_compute_thread_group_from_reflection :: proc(
	options: Options,
	stage: Stage_Desc,
	root: json.Object,
	out_group: ^Compute_Thread_Group_Size,
) -> bool {
	entry_points_value, entry_points_ok := json_field(root, "entryPoints")
	if !entry_points_ok {
		fmt.eprintln("ape_shaderc: Slang reflection has no entryPoints array: ", options.source_path, ":", stage.entry)
		return false
	}

	entry_points, entry_points_array_ok := json_array(entry_points_value)
	if !entry_points_array_ok {
		fmt.eprintln("ape_shaderc: Slang reflection entryPoints field is not an array: ", options.source_path, ":", stage.entry)
		return false
	}

	for entry_point_value in entry_points {
		entry_point, entry_point_ok := json_object(entry_point_value)
		if !entry_point_ok {
			continue
		}

		name, name_ok := json_string_field(entry_point, "name")
		stage_name, stage_ok := json_string_field(entry_point, "stage")
		if !name_ok || !stage_ok || name != stage.entry || stage_name != "compute" {
			continue
		}

		thread_group_value, thread_group_ok := json_field(entry_point, "threadGroupSize")
		if !thread_group_ok {
			fmt.eprintln("ape_shaderc: compute entry point has no threadGroupSize: ", options.source_path, ":", stage.entry)
			return false
		}

		thread_group, thread_group_array_ok := json_array(thread_group_value)
		if !thread_group_array_ok || len(thread_group) != 3 {
			fmt.eprintln("ape_shaderc: compute entry point threadGroupSize must be a 3-element array: ", options.source_path, ":", stage.entry)
			return false
		}

		x, x_ok := json_u32(thread_group[0])
		y, y_ok := json_u32(thread_group[1])
		z, z_ok := json_u32(thread_group[2])
		if !x_ok || !y_ok || !z_ok || x == 0 || y == 0 || z == 0 {
			fmt.eprintln("ape_shaderc: compute threadGroupSize values must be positive integers: ", options.source_path, ":", stage.entry)
			return false
		}

		out_group^ = {valid = true, x = x, y = y, z = z}
		return true
	}

	fmt.eprintln("ape_shaderc: Slang reflection has no compute entry point named ", stage.entry, ": ", options.source_path)
	return false
}

merge_compute_thread_group :: proc(dst: ^Compute_Thread_Group_Size, src: Compute_Thread_Group_Size) -> bool {
	if dst == nil || !src.valid {
		return false
	}

	if !dst.valid {
		dst^ = src
		return true
	}

	if dst.x != src.x || dst.y != src.y || dst.z != src.z {
		fmt.eprintln("ape_shaderc: reflected compute thread group size differs across targets")
		return false
	}

	return true
}

generated_vertex_format_from_json :: proc(type_value: json.Value) -> (Generated_Vertex_Format, u32, bool) {
	type_object, type_object_ok := json_object(type_value)
	if !type_object_ok {
		return .Float32, 0, false
	}

	kind, kind_ok := json_string_field(type_object, "kind")
	if !kind_ok {
		return .Float32, 0, false
	}

	if kind == "scalar" {
		scalar_type, scalar_ok := json_string_field(type_object, "scalarType")
		if !scalar_ok || scalar_type != "float32" {
			return .Float32, 0, false
		}
		return .Float32, 4, true
	}

	if kind == "vector" {
		element_count, element_count_ok := json_u32_field(type_object, "elementCount")
		if !element_count_ok {
			return .Float32, 0, false
		}

		element_type_value, element_type_ok := json_field(type_object, "elementType")
		if !element_type_ok {
			return .Float32, 0, false
		}
		element_type, element_type_object_ok := json_object(element_type_value)
		if !element_type_object_ok {
			return .Float32, 0, false
		}
		scalar_type, scalar_ok := json_string_field(element_type, "scalarType")
		if !scalar_ok || scalar_type != "float32" {
			return .Float32, 0, false
		}

		switch element_count {
		case 1:
			return .Float32, 4, true
		case 2:
			return .Float32x2, 8, true
		case 3:
			return .Float32x3, 12, true
		case 4:
			return .Float32x4, 16, true
		}
	}

	return .Float32, 0, false
}

parse_vertex_semantic :: proc(semantic_name: string) -> (string, u32, bool) {
	if semantic_name == "" {
		return "", 0, false
	}

	end := len(semantic_name)
	start_digits := end
	for start_digits > 0 {
		c := semantic_name[start_digits - 1]
		if c < '0' || c > '9' {
			break
		}
		start_digits -= 1
	}

	semantic_index: u32
	if start_digits < end {
		for c in semantic_name[start_digits:end] {
			semantic_index = semantic_index * 10 + u32(c - '0')
		}
	}

	base := semantic_name[:start_digits]
	if base == "" {
		return "", 0, false
	}

	cloned, err := strings.clone(base)
	if err != nil {
		return "", 0, false
	}
	return cloned, semantic_index, true
}

merge_vertex_layout :: proc(dst, src: ^Generated_Vertex_Layout) -> bool {
	if dst == nil || src == nil {
		return false
	}

	if len(dst.attrs) == 0 {
		dst.attrs = src.attrs
		dst.stride = src.stride
		src.attrs = nil
		src.stride = 0
		return true
	}

	if !vertex_layout_matches(dst^, src^) {
		fmt.eprintln("ape_shaderc: reflected vertex input layout differs across targets")
		return false
	}

	return true
}

vertex_layout_matches :: proc(a, b: Generated_Vertex_Layout) -> bool {
	if a.stride != b.stride || len(a.attrs) != len(b.attrs) {
		return false
	}

	for attr, index in a.attrs {
		other := b.attrs[index]
		if attr.semantic != other.semantic ||
		   attr.semantic_index != other.semantic_index ||
		   attr.format != other.format ||
		   attr.offset != other.offset ||
		   attr.size != other.size {
			return false
		}
	}

	return true
}

vertex_layout_has_semantic :: proc(layout: Generated_Vertex_Layout, semantic: string, semantic_index: u32) -> bool {
	for attr in layout.attrs {
		if attr.semantic == semantic && attr.semantic_index == semantic_index {
			return true
		}
	}

	return false
}

json_field :: proc(object: json.Object, name: string) -> (json.Value, bool) {
	value, ok := object[name]
	return value, ok
}

json_object :: proc(value: json.Value) -> (json.Object, bool) {
	#partial switch object in value {
	case json.Object:
		return object, true
	}

	return nil, false
}

json_array :: proc(value: json.Value) -> (json.Array, bool) {
	#partial switch array in value {
	case json.Array:
		return array, true
	}

	return nil, false
}

json_string :: proc(value: json.Value) -> (string, bool) {
	#partial switch string_value in value {
	case json.String:
		return string(string_value), true
	}

	return "", false
}

json_string_field :: proc(object: json.Object, name: string) -> (string, bool) {
	value, ok := json_field(object, name)
	if !ok {
		return "", false
	}
	return json_string(value)
}

json_u32 :: proc(value: json.Value) -> (u32, bool) {
	#partial switch number in value {
	case json.Integer:
		if number < 0 || number > json.Integer(max(u32)) {
			return 0, false
		}
		return u32(number), true
	case json.Float:
		if number < 0 || number > f64(max(u32)) || number != f64(u32(number)) {
			return 0, false
		}
		return u32(number), true
	}

	return 0, false
}

json_u32_field :: proc(object: json.Object, name: string) -> (u32, bool) {
	value, ok := json_field(object, name)
	if !ok {
		return 0, false
	}
	return json_u32(value)
}

binding_kind_from_category :: proc(category: Slang_Parameter_Category) -> (Binding_Kind, bool) {
	#partial switch category {
	case .Constant_Buffer:
		return .Uniform_Block, true
	case .Shader_Resource, .Unordered_Access:
		return .Resource_View, true
	case .Sampler_State:
		return .Sampler, true
	}

	return .Uniform_Block, false
}

binding_kind_from_descriptor_parameter :: proc(reflection_model: Reflection_Model, name: string, slot: u32) -> (Binding_Kind, bool) {
	parameter, parameter_ok := reflection_parameter_by_binding(reflection_model, name, "descriptorTableSlot", slot)
	if !parameter_ok {
		return .Uniform_Block, false
	}

	return binding_kind_from_json_type(parameter.type_value)
}

binding_kind_from_json_type :: proc(type_value: json.Value) -> (Binding_Kind, bool) {
	type_object, type_object_ok := json_object(type_value)
	if !type_object_ok {
		return .Uniform_Block, false
	}

	type_kind, type_kind_ok := json_string_field(type_object, "kind")
	if !type_kind_ok {
		return .Uniform_Block, false
	}

	switch type_kind {
	case "constantBuffer", "parameterBlock":
		return .Uniform_Block, true
	case "samplerState":
		return .Sampler, true
	case "resource", "shaderStorageBuffer", "structuredBuffer":
		return .Resource_View, true
	}

	return .Uniform_Block, false
}

resource_view_metadata_from_reflection :: proc(
	reflection_model: Reflection_Model,
	name: string,
	category: Slang_Parameter_Category,
	slot: u32,
) -> (Resource_View_Kind, Resource_Access, Storage_Image_Format, u32, bool) {
	binding_kind, binding_kind_ok := json_binding_kind_from_category(category)
	if !binding_kind_ok {
		return .Sampled, .Unknown, .Invalid, 0, false
	}

	if parameter, parameter_ok := reflection_parameter_by_binding(reflection_model, name, binding_kind, slot); parameter_ok {
		return resource_view_metadata_from_type_json(parameter.type_value, binding_kind)
	}

	return .Sampled, .Unknown, .Invalid, 0, false
}

json_binding_kind_from_category :: proc(category: Slang_Parameter_Category) -> (string, bool) {
	#partial switch category {
	case .Shader_Resource:
		return "shaderResource", true
	case .Unordered_Access:
		return "unorderedAccess", true
	case .Descriptor_Table_Slot:
		return "descriptorTableSlot", true
	}

	return "", false
}

resource_view_metadata_from_type_json :: proc(type_value: json.Value, binding_kind: string) -> (Resource_View_Kind, Resource_Access, Storage_Image_Format, u32, bool) {
	type_object, type_object_ok := json_object(type_value)
	if !type_object_ok {
		return .Sampled, .Unknown, .Invalid, 0, false
	}

	type_kind, type_kind_ok := json_string_field(type_object, "kind")
	if !type_kind_ok {
		return .Sampled, .Unknown, .Invalid, 0, false
	}

	access := resource_access_from_json(type_object, binding_kind)
	if type_kind == "shaderStorageBuffer" || type_kind == "structuredBuffer" {
		stride, stride_ok := storage_buffer_stride_from_type_json(type_object)
		if !stride_ok {
			return .Storage_Buffer, access, .Invalid, 0, false
		}
		return .Storage_Buffer, access, .Invalid, stride, true
	}

	base_shape, base_shape_ok := json_string_field(type_object, "baseShape")
	if type_kind == "resource" && base_shape_ok {
		if resource_shape_is_texture(base_shape) {
			if binding_kind == "unorderedAccess" || access == .Write || access == .Read_Write {
				format, format_ok := storage_image_format_from_type_json(type_object)
				if !format_ok {
					return .Storage_Image, access, .Invalid, 0, false
				}
				return .Storage_Image, access, format, 0, true
			}
			return .Sampled, access, .Invalid, 0, true
		}
		if resource_shape_is_buffer(base_shape) {
			stride: u32
			if base_shape == "structuredBuffer" {
				stride_ok: bool
				stride, stride_ok = storage_buffer_stride_from_type_json(type_object)
				if !stride_ok {
					return .Storage_Buffer, access, .Invalid, 0, false
				}
			}
			return .Storage_Buffer, access, .Invalid, stride, true
		}
	}

	if binding_kind == "unorderedAccess" {
		return .Storage_Buffer, access, .Invalid, 0, true
	}
	if binding_kind == "shaderResource" {
		return .Sampled, access, .Invalid, 0, true
	}

	return .Sampled, .Unknown, .Invalid, 0, false
}

storage_image_format_from_type_json :: proc(type_object: json.Object) -> (Storage_Image_Format, bool) {
	result_type_value, result_type_ok := json_field(type_object, "resultType")
	if !result_type_ok {
		fmt.eprintln("ape_shaderc: storage image resource has no reflected resultType")
		return .Invalid, false
	}

	result_type, result_type_object_ok := json_object(result_type_value)
	if !result_type_object_ok {
		fmt.eprintln("ape_shaderc: storage image resultType is not an object")
		return .Invalid, false
	}

	kind, kind_ok := json_string_field(result_type, "kind")
	if !kind_ok {
		fmt.eprintln("ape_shaderc: storage image resultType has no kind")
		return .Invalid, false
	}

	if kind == "scalar" {
		scalar_type, scalar_ok := json_string_field(result_type, "scalarType")
		if scalar_ok && scalar_type == "float32" {
			return .R32F, true
		}
	} else if kind == "vector" {
		element_count, element_count_ok := json_u32_field(result_type, "elementCount")
		element_type_value, element_type_ok := json_field(result_type, "elementType")
		if element_count_ok && element_type_ok {
			element_type, element_type_object_ok := json_object(element_type_value)
			if element_type_object_ok {
				scalar_type, scalar_ok := json_string_field(element_type, "scalarType")
				if scalar_ok && scalar_type == "float32" && element_count == 4 {
					return .RGBA32F, true
				}
			}
		}
	}

	fmt.eprintln("ape_shaderc: unsupported storage image result type; supported generated formats are float and float4")
	return .Invalid, false
}

storage_buffer_stride_from_type_json :: proc(type_object: json.Object) -> (u32, bool) {
	result_type_value, result_type_ok := json_field(type_object, "resultType")
	if !result_type_ok {
		fmt.eprintln("ape_shaderc: structured storage buffer has no reflected resultType")
		return 0, false
	}

	stride, stride_ok := storage_buffer_element_size_from_json(result_type_value)
	if !stride_ok || stride == 0 {
		fmt.eprintln("ape_shaderc: unsupported structured storage buffer element type")
		return 0, false
	}
	if stride % 4 != 0 {
		fmt.eprintln("ape_shaderc: structured storage buffer element stride must be 4-byte aligned")
		return 0, false
	}

	return stride, true
}

storage_buffer_element_size_from_json :: proc(type_value: json.Value) -> (u32, bool) {
	type_object, type_object_ok := json_object(type_value)
	if !type_object_ok {
		return 0, false
	}

	kind, kind_ok := json_string_field(type_object, "kind")
	if !kind_ok {
		return 0, false
	}

	switch kind {
	case "scalar":
		scalar_type, scalar_ok := json_string_field(type_object, "scalarType")
		if !scalar_ok {
			return 0, false
		}
		return storage_scalar_size(scalar_type)
	case "vector":
		element_count, element_count_ok := json_u32_field(type_object, "elementCount")
		element_type_value, element_type_ok := json_field(type_object, "elementType")
		if !element_count_ok || !element_type_ok || element_count == 0 {
			return 0, false
		}
		element_size, element_size_ok := storage_buffer_element_size_from_json(element_type_value)
		if !element_size_ok {
			return 0, false
		}
		return element_size * element_count, true
	case "struct":
		fields_value, fields_ok := json_field(type_object, "fields")
		if !fields_ok {
			return 0, false
		}
		fields, fields_array_ok := json_array(fields_value)
		if !fields_array_ok {
			return 0, false
		}

		stride: u32
		for field_value in fields {
			field, field_ok := json_object(field_value)
			if !field_ok {
				continue
			}

			binding_value, binding_ok := json_field(field, "binding")
			if !binding_ok {
				return 0, false
			}
			binding, binding_object_ok := json_object(binding_value)
			if !binding_object_ok {
				return 0, false
			}

			offset, offset_ok := json_u32_field(binding, "offset")
			size, size_ok := json_u32_field(binding, "size")
			if !offset_ok || !size_ok {
				return 0, false
			}
			end := offset + size
			if end < offset {
				return 0, false
			}
			if end > stride {
				stride = end
			}
		}

		return stride, stride > 0
	}

	return 0, false
}

storage_scalar_size :: proc(scalar_type: string) -> (u32, bool) {
	switch scalar_type {
	case "float32", "int32", "uint32":
		return 4, true
	case "float16", "int16", "uint16":
		return 2, true
	case "int64", "uint64", "float64":
		return 8, true
	case "int8", "uint8":
		return 1, true
	}

	return 0, false
}

resource_access_from_json :: proc(type_object: json.Object, binding_kind: string) -> Resource_Access {
	if access, access_ok := json_string_field(type_object, "access"); access_ok {
		switch access {
		case "read":
			return .Read
		case "write":
			return .Write
		case "readWrite":
			return .Read_Write
		}
	}

	if binding_kind == "shaderResource" {
		return .Read
	}
	if binding_kind == "unorderedAccess" {
		return .Read_Write
	}
	if binding_kind == "descriptorTableSlot" {
		return .Read
	}

	return .Unknown
}

resource_shape_is_texture :: proc(shape: string) -> bool {
	if shape == "textureBuffer" {
		return false
	}

	return string_has_prefix(shape, "texture")
}

resource_shape_is_buffer :: proc(shape: string) -> bool {
	return shape == "buffer" ||
	       shape == "rawBuffer" ||
	       shape == "structuredBuffer" ||
	       shape == "byteAddressBuffer" ||
	       shape == "textureBuffer" ||
	       string_has_suffix(shape, "Buffer")
}

string_has_prefix :: proc(s, prefix: string) -> bool {
	if len(prefix) > len(s) {
		return false
	}

	return s[:len(prefix)] == prefix
}

string_has_suffix :: proc(s, suffix: string) -> bool {
	if len(suffix) > len(s) {
		return false
	}

	return s[len(s) - len(suffix):] == suffix
}

collect_uniform_block :: proc(
	slang: ^Slang_API,
	type_layout: rawptr,
	name: string,
	uniform_blocks: ^[dynamic]Uniform_Block,
) -> (u32, bool) {
	element_layout := slang.spReflectionTypeLayout_GetElementTypeLayout(type_layout)
	if element_layout == nil {
		element_layout = type_layout
	}

	block_size := u32(slang.spReflectionTypeLayout_GetSize(element_layout, .Uniform))
	alignment_i32 := slang.spReflectionTypeLayout_getAlignment(element_layout, .Uniform)
	alignment := u32(1)
	if alignment_i32 > 0 {
		alignment = u32(alignment_i32)
	}

	fields: [dynamic]Uniform_Field
	field_count := slang.spReflectionTypeLayout_GetFieldCount(element_layout)
	for i in 0..<int(field_count) {
		field_layout := slang.spReflectionTypeLayout_GetFieldByIndex(element_layout, u32(i))
		if field_layout == nil {
			continue
		}

		variable := slang.spReflectionVariableLayout_GetVariable(field_layout)
		if variable == nil {
			continue
		}

		name_c := slang.spReflectionVariable_GetName(variable)
		if name_c == nil {
			continue
		}

		field_name, field_name_err := strings.clone_from_cstring(name_c)
		if field_name_err != nil {
			delete_uniform_fields(fields[:])
			delete(fields)
			return 0, false
		}

		field_type_layout := slang.spReflectionVariableLayout_GetTypeLayout(field_layout)
		odin_type, host_size, type_ok := odin_type_for_uniform_field(slang, field_type_layout)
		if !type_ok {
			delete(field_name)
			delete_uniform_fields(fields[:])
			delete(fields)
			fmt.eprintln("ape_shaderc: uniform field has unsupported host layout: ", name, ".", string(name_c))
			return 0, false
		}

		append(&fields, Uniform_Field {
			name = field_name,
			odin_type = odin_type,
			offset = u32(slang.spReflectionVariableLayout_GetOffset(field_layout, .Uniform)),
			size = u32(slang.spReflectionTypeLayout_GetSize(field_type_layout, .Uniform)),
			host_size = host_size,
		})
	}

	block_name, block_name_err := strings.clone(name)
	if block_name_err != nil {
		delete_uniform_fields(fields[:])
		delete(fields)
		return 0, false
	}

	block := Uniform_Block {
		name = block_name,
		size = block_size,
		alignment = alignment,
		fields = fields,
	}

	for existing in uniform_blocks^ {
		if existing.name == block.name {
			match := uniform_block_layout_matches(existing, block)
			delete_uniform_block(&block)
			if !match {
				fmt.eprintln("ape_shaderc: uniform block layout differs across stages or targets: ", name)
				return 0, false
			}
			return existing.size, true
		}
	}

	append(uniform_blocks, block)
	return block_size, true
}

uniform_block_layout_matches :: proc(a, b: Uniform_Block) -> bool {
	if a.size != b.size || a.alignment != b.alignment || len(a.fields) != len(b.fields) {
		return false
	}

	for field, index in a.fields {
		other := b.fields[index]
		if field.name != other.name ||
		   field.odin_type != other.odin_type ||
		   field.offset != other.offset ||
		   field.size != other.size ||
		   field.host_size != other.host_size {
			return false
		}
	}

	return true
}

odin_type_for_uniform_field :: proc(slang: ^Slang_API, type_layout: rawptr) -> (string, u32, bool) {
	if type_layout == nil {
		return "", 0, false
	}

	typ := slang.spReflectionTypeLayout_GetType(type_layout)
	if typ == nil {
		return "", 0, false
	}

	kind := slang.spReflectionType_GetKind(typ)
	#partial switch kind {
	case .Scalar:
		scalar_type, scalar_size, scalar_ok := odin_scalar_type(slang.spReflectionType_GetScalarType(typ))
		if !scalar_ok {
			return "", 0, false
		}
		cloned_type, clone_err := strings.clone(scalar_type)
		if clone_err != nil {
			return "", 0, false
		}
		return cloned_type, scalar_size, true
	case .Vector:
		element_type := slang.spReflectionType_GetElementType(typ)
		if element_type == nil {
			return "", 0, false
		}

		scalar_type, scalar_size, scalar_ok := odin_scalar_type(slang.spReflectionType_GetScalarType(element_type))
		if !scalar_ok {
			return "", 0, false
		}

		count := u32(slang.spReflectionType_GetElementCount(typ))
		if count == 0 {
			return "", 0, false
		}
		return fmt.aprintf("[%d]%s", count, scalar_type), count * scalar_size, true
	case .Matrix:
		element_type := slang.spReflectionType_GetElementType(typ)
		if element_type == nil {
			return "", 0, false
		}

		scalar_type, scalar_size, scalar_ok := odin_scalar_type(slang.spReflectionType_GetScalarType(element_type))
		if !scalar_ok {
			return "", 0, false
		}

		row_count := slang.spReflectionType_GetRowCount(typ)
		column_count := slang.spReflectionType_GetColumnCount(typ)
		if row_count == 0 || column_count == 0 {
			return "", 0, false
		}
		return fmt.aprintf("[%d][%d]%s", row_count, column_count, scalar_type), row_count * column_count * scalar_size, true
	}

	return "", 0, false
}

odin_scalar_type :: proc(scalar: Slang_Scalar_Type) -> (string, u32, bool) {
	#partial switch scalar {
	case .Float32:
		return "f32", 4, true
	case .Int32:
		return "i32", 4, true
	case .Uint32:
		return "u32", 4, true
	}

	return "", 0, false
}

write_stage_artifact :: proc(path: string, bytes: []byte, label: string) -> bool {
	dir, _ := filepath.split(path)
	if dir != "" && !ensure_directory(dir) {
		return false
	}
	if !os.write_entire_file(path, bytes) {
		fmt.eprintln("ape_shaderc: failed to write ", label, ": ", path)
		return false
	}

	return true
}

copy_raw_bytes :: proc(ptr: rawptr, size: uint) -> []byte {
	if ptr == nil || size == 0 {
		return nil
	}

	bytes := mem.ptr_to_bytes(cast(^byte)ptr, int(size))
	out := make([]byte, len(bytes))
	copy(out, bytes)
	return out
}

copy_blob_bytes :: proc(blob: rawptr) -> []byte {
	if blob == nil {
		return nil
	}

	blob_iface := cast(^ISlangBlob)blob
	ptr := blob_iface.vtable.getBufferPointer(blob_iface)
	size := blob_iface.vtable.getBufferSize(blob_iface)
	return copy_raw_bytes(ptr, size)
}

print_slang_blob_diagnostics :: proc(blob: ^ISlangBlob) {
	if blob == nil {
		return
	}

	bytes := copy_blob_bytes(cast(rawptr)blob)
	if bytes == nil {
		return
	}
	defer delete(bytes)

	message := string(bytes)
	if message != "" {
		fmt.eprintln(message)
	}
}

release_slang_blob :: proc(blob: rawptr) {
	if blob == nil {
		return
	}

	blob_iface := cast(^ISlangBlob)blob
	blob_iface.vtable.release(blob_iface)
}

delete_compiled_stages :: proc(stages: []Compiled_Stage) {
	for &stage in stages {
		if stage.bytecode != nil {
			delete(stage.bytecode)
		}
		if stage.reflection != nil {
			delete(stage.reflection)
		}
	}
}

delete_shader_build_result :: proc(result: ^Shader_Build_Result) {
	if result == nil {
		return
	}

	if result.compiled != nil {
		delete_compiled_stages(result.compiled[:])
		delete(result.compiled)
	}
	delete_bindings(&result.bindings)
	delete_uniform_blocks(&result.uniform_blocks)
	delete_vertex_layout(&result.vertex_layout)

	result^ = {}
}

delete_bindings :: proc(bindings: ^[dynamic]Binding_Record) {
	for binding in bindings^ {
		if binding.name != "" {
			delete(binding.name)
		}
	}
	delete(bindings^)
}

delete_uniform_blocks :: proc(blocks: ^[dynamic]Uniform_Block) {
	for &block in blocks^ {
		delete_uniform_block(&block)
	}
	delete(blocks^)
}

delete_uniform_block :: proc(block: ^Uniform_Block) {
	if block.name != "" {
		delete(block.name)
	}
	delete_uniform_fields(block.fields[:])
	if block.fields != nil {
		delete(block.fields)
	}
}

delete_uniform_fields :: proc(fields: []Uniform_Field) {
	for field in fields {
		if field.name != "" {
			delete(field.name)
		}
		if field.odin_type != "" {
			delete(field.odin_type)
		}
	}
}

delete_vertex_layout :: proc(layout: ^Generated_Vertex_Layout) {
	if layout == nil {
		return
	}

	for attr in layout.attrs {
		if attr.semantic != "" {
			delete(attr.semantic)
		}
	}
	if layout.attrs != nil {
		delete(layout.attrs)
		layout.attrs = nil
	}
	layout.stride = 0
}

write_generated_bindings :: proc(
	options: Options,
	bindings: []Binding_Record,
	uniform_blocks: []Uniform_Block,
	vertex_layout: Generated_Vertex_Layout,
	compute_thread_group: Compute_Thread_Group_Size,
) -> bool {
	dir, _ := filepath.split(options.generated_path)
	if dir != "" && !ensure_directory(dir) {
		return false
	}

	out: [dynamic]byte
	defer delete(out)

	package_name := fmt.tprintf("%s_shader", odin_identifier(options.shader_name))
	append_string(&out, fmt.tprintf("package %s\n\n", package_name))
	if len(vertex_layout.attrs) > 0 || len(bindings) > 0 || compute_thread_group.valid {
		append_string(&out, "import gfx \"ape:gfx\"\n\n")
	}
	append_string(&out, "// Generated by tools/ape_shaderc. Do not edit by hand.\n\n")

	if compute_thread_group.valid {
		append_compute_thread_group_odin(&out, compute_thread_group)
	}

	if len(uniform_blocks) > 0 {
		for block in uniform_blocks {
			if !append_uniform_block_odin(&out, block) {
				return false
			}
		}
	}

	if len(vertex_layout.attrs) > 0 {
		if !append_vertex_layout_odin(&out, vertex_layout) {
			return false
		}
	}

	emitted_native := make(map[string]bool)
	defer delete(emitted_native)
	emitted_logical := make(map[string]bool)
	defer delete(emitted_logical)
	emitted_resource_metadata := make(map[string]bool)
	defer delete(emitted_resource_metadata)

	for binding in bindings {
		prefix := binding_prefix(binding.kind)
		target_prefix := target_prefix(binding.target)
		stage_prefix := stage_prefix(binding.stage)
		name := odin_identifier(binding.name)
		native_constant_name := fmt.tprintf("%s_%s_%s_%s", target_prefix, stage_prefix, prefix, name)
		native_key := fmt.tprintf("%s:%d:%d", native_constant_name, binding.slot, binding.space)
		if !(native_key in emitted_native) {
			append_string(&out, fmt.tprintf("%s :: %d\n", native_constant_name, binding.slot))
			append_string(&out, fmt.tprintf("%s_SPACE :: %d\n", native_constant_name, binding.space))
			emitted_native[native_key] = true
		}

		logical_constant_name := fmt.tprintf("%s_%s", prefix, name)
		logical_key := fmt.tprintf("%s:%d", logical_constant_name, binding.logical_slot)
		if !(logical_key in emitted_logical) {
			append_string(&out, fmt.tprintf("%s :: %d\n", logical_constant_name, binding.logical_slot))
			emitted_logical[logical_key] = true
		}

		if binding.kind == .Resource_View {
			metadata_key := fmt.tprintf("VIEW_META:%s", name)
			if !(metadata_key in emitted_resource_metadata) {
				append_string(&out, fmt.tprintf("VIEW_KIND_%s :: gfx.View_Kind.%s\n", name, resource_view_kind_odin(binding.view_kind)))
				append_string(&out, fmt.tprintf("VIEW_ACCESS_%s :: gfx.Shader_Resource_Access.%s\n", name, resource_access_odin(binding.access)))
				if binding.view_kind == .Storage_Image && binding.storage_image_format != .Invalid {
					append_string(&out, fmt.tprintf("VIEW_FORMAT_%s :: gfx.Pixel_Format.%s\n", name, storage_image_format_odin(binding.storage_image_format)))
				}
				if binding.view_kind == .Storage_Buffer {
					append_string(&out, fmt.tprintf("VIEW_STRIDE_%s :: %d\n", name, binding.storage_buffer_stride))
				}
				emitted_resource_metadata[metadata_key] = true
			}
		}
	}

	if len(bindings) == 0 {
		append_string(&out, "// This shader currently has no reflected resource bindings.\n")
	} else {
		if !append_binding_contract_odin(&out, bindings) {
			return false
		}
		if !append_binding_group_layout_odin(&out, bindings) {
			return false
		}
		if !append_binding_helpers_odin(&out, bindings, uniform_blocks) {
			return false
		}
	}

	trim_trailing_blank_lines(&out)

	if !os.write_entire_file(options.generated_path, out[:]) {
		fmt.eprintln("ape_shaderc: failed to write generated bindings: ", options.generated_path)
		return false
	}

	return true
}

append_compute_thread_group_odin :: proc(out: ^[dynamic]byte, group: Compute_Thread_Group_Size) {
	append_string(out, fmt.tprintf("COMPUTE_THREAD_GROUP_SIZE_X :: %d\n", group.x))
	append_string(out, fmt.tprintf("COMPUTE_THREAD_GROUP_SIZE_Y :: %d\n", group.y))
	append_string(out, fmt.tprintf("COMPUTE_THREAD_GROUP_SIZE_Z :: %d\n", group.z))
	append_string(out, fmt.tprintf("COMPUTE_THREAD_GROUP_INVOCATIONS :: %d\n\n", group.x * group.y * group.z))

	append_string(out, "dispatch_group_count :: proc(thread_count: u32, group_size: u32) -> u32 {\n")
	append_string(out, "\tif thread_count == 0 || group_size == 0 {\n")
	append_string(out, "\t\treturn 0\n")
	append_string(out, "\t}\n")
	append_string(out, "\treturn 1 + (thread_count - 1) / group_size\n")
	append_string(out, "}\n\n")

	append_string(out, "dispatch_groups_for_threads :: proc(thread_count_x: u32, thread_count_y: u32 = 1, thread_count_z: u32 = 1) -> (u32, u32, u32) {\n")
	append_string(out, "\treturn ")
	append_string(out, "dispatch_group_count(thread_count_x, COMPUTE_THREAD_GROUP_SIZE_X), ")
	append_string(out, "dispatch_group_count(thread_count_y, COMPUTE_THREAD_GROUP_SIZE_Y), ")
	append_string(out, "dispatch_group_count(thread_count_z, COMPUTE_THREAD_GROUP_SIZE_Z)\n")
	append_string(out, "}\n\n")

	append_string(out, "dispatch_threads :: proc(ctx: ^gfx.Context, thread_count_x: u32, thread_count_y: u32 = 1, thread_count_z: u32 = 1) -> bool {\n")
	append_string(out, "\tgroup_count_x, group_count_y, group_count_z := dispatch_groups_for_threads(thread_count_x, thread_count_y, thread_count_z)\n")
	append_string(out, "\treturn gfx.dispatch(ctx, group_count_x, group_count_y, group_count_z)\n")
	append_string(out, "}\n\n")
}

trim_trailing_blank_lines :: proc(out: ^[dynamic]byte) {
	for len(out^) >= 2 &&
	    out^[len(out^) - 1] == byte('\n') &&
	    out^[len(out^) - 2] == byte('\n') {
		pop(out)
	}

	if len(out^) == 0 || out^[len(out^) - 1] != byte('\n') {
		append(out, byte('\n'))
	}
}

append_binding_contract_odin :: proc(out: ^[dynamic]byte, bindings: []Binding_Record) -> bool {
	append_string(out, "\n")
	append_string(out, fmt.tprintf("BINDING_RECORD_COUNT :: %d\n\n", len(bindings)))
	append_string(out, "Binding_Uniform_Block_Desc :: struct {\n")
	append_string(out, "\tsize: u32,\n")
	append_string(out, "}\n\n")
	append_string(out, "Binding_Resource_View_Desc :: struct {\n")
	append_string(out, "\tview_kind: gfx.View_Kind,\n")
	append_string(out, "\taccess: gfx.Shader_Resource_Access,\n")
	append_string(out, "\tstorage_image_format: gfx.Pixel_Format,\n")
	append_string(out, "\tstorage_buffer_stride: u32,\n")
	append_string(out, "}\n\n")
	append_string(out, "Binding_Record_Desc :: struct {\n")
	append_string(out, "\ttarget: gfx.Backend,\n")
	append_string(out, "\tstage: gfx.Shader_Stage,\n")
	append_string(out, "\tkind: gfx.Shader_Binding_Kind,\n")
	append_string(out, "\tname: cstring,\n")
	append_string(out, "\tlogical_slot: u32,\n")
	append_string(out, "\tnative_slot: u32,\n")
	append_string(out, "\tnative_space: u32,\n")
	append_string(out, "\tuniform_block: Binding_Uniform_Block_Desc,\n")
	append_string(out, "\tresource_view: Binding_Resource_View_Desc,\n")
	append_string(out, "}\n\n")

	append_string(out, "binding_records :: proc() -> [BINDING_RECORD_COUNT]Binding_Record_Desc {\n")
	append_string(out, "\trecords: [BINDING_RECORD_COUNT]Binding_Record_Desc\n")
	for binding, index in bindings {
		append_string(out, fmt.tprintf("\trecords[%d] = ", index))
		append_string(out, "{\n")
		append_string(out, fmt.tprintf("\t\ttarget = gfx.Backend.%s,\n", backend_odin(binding.target)))
		append_string(out, fmt.tprintf("\t\tstage = gfx.Shader_Stage.%s,\n", stage_odin(binding.stage)))
		append_string(out, fmt.tprintf("\t\tkind = gfx.Shader_Binding_Kind.%s,\n", binding_kind_odin(binding.kind)))
		append_string(out, fmt.tprintf("\t\tname = cstring(\"%s\"),\n", binding.name))
		append_string(out, fmt.tprintf("\t\tlogical_slot = %d,\n", binding.logical_slot))
		append_string(out, fmt.tprintf("\t\tnative_slot = %d,\n", binding.slot))
		append_string(out, fmt.tprintf("\t\tnative_space = %d,\n", binding.space))
		switch binding.kind {
		case .Uniform_Block:
			append_string(out, "\t\tuniform_block = {\n")
			append_string(out, fmt.tprintf("\t\t\tsize = %d,\n", binding.size))
			append_string(out, "\t\t},\n")
		case .Resource_View:
			append_string(out, "\t\tresource_view = {\n")
			append_string(out, fmt.tprintf("\t\t\tview_kind = gfx.View_Kind.%s,\n", resource_view_kind_odin(binding.view_kind)))
			append_string(out, fmt.tprintf("\t\t\taccess = gfx.Shader_Resource_Access.%s,\n", resource_access_odin(binding.access)))
			append_string(out, fmt.tprintf("\t\t\tstorage_image_format = gfx.Pixel_Format.%s,\n", storage_image_format_odin(binding.storage_image_format)))
			append_string(out, fmt.tprintf("\t\t\tstorage_buffer_stride = %d,\n", binding.storage_buffer_stride))
			append_string(out, "\t\t},\n")
		case .Sampler:
		}
		append_string(out, "\t}\n")
	}
	append_string(out, "\treturn records\n")
	append_string(out, "}\n\n")

	return true
}

append_binding_group_layout_odin :: proc(out: ^[dynamic]byte, bindings: []Binding_Record) -> bool {
	entries: [dynamic]Binding_Group_Layout_Entry
	defer delete(entries)

	if !collect_binding_group_layout_entries(&entries, bindings) {
		return false
	}

	append_string(out, "binding_group_layout_desc :: proc(label: string = \"\") -> gfx.Binding_Group_Layout_Desc {\n")
	append_string(out, "\tdesc: gfx.Binding_Group_Layout_Desc\n")
	append_string(out, "\tdesc.label = label\n")

	for entry, index in entries {
		append_string(out, fmt.tprintf("\tdesc.entries[%d] = ", index))
		append_string(out, "{\n")
		append_string(out, "\t\tactive = true,\n")
		append_string(out, "\t\tstages = ")
		append_stage_set_odin(out, entry.stages)
		append_string(out, ",\n")
		append_string(out, fmt.tprintf("\t\tkind = gfx.Shader_Binding_Kind.%s,\n", binding_kind_odin(entry.kind)))
		append_string(out, fmt.tprintf("\t\tslot = %d,\n", entry.logical_slot))
		append_string(out, fmt.tprintf("\t\tname = \"%s\",\n", entry.name))

		switch entry.kind {
		case .Uniform_Block:
			append_string(out, "\t\tuniform_block = {\n")
			append_string(out, fmt.tprintf("\t\t\tsize = %d,\n", entry.size))
			append_string(out, "\t\t},\n")
		case .Resource_View:
			append_string(out, "\t\tresource_view = {\n")
			append_string(out, fmt.tprintf("\t\t\tview_kind = gfx.View_Kind.%s,\n", resource_view_kind_odin(entry.view_kind)))
			append_string(out, fmt.tprintf("\t\t\taccess = gfx.Shader_Resource_Access.%s,\n", resource_access_odin(entry.access)))
			append_string(out, fmt.tprintf("\t\t\tstorage_image_format = gfx.Pixel_Format.%s,\n", storage_image_format_odin(entry.storage_image_format)))
			append_string(out, fmt.tprintf("\t\t\tstorage_buffer_stride = %d,\n", entry.storage_buffer_stride))
			append_string(out, "\t\t},\n")
		case .Sampler:
		}

		append_string(out, "\t}\n")
	}

	for binding, index in bindings {
		append_string(out, fmt.tprintf("\tdesc.native_bindings[%d] = ", index))
		append_string(out, "{\n")
		append_string(out, "\t\tactive = true,\n")
		append_string(out, fmt.tprintf("\t\ttarget = gfx.Backend.%s,\n", backend_odin(binding.target)))
		append_string(out, fmt.tprintf("\t\tstage = gfx.Shader_Stage.%s,\n", stage_odin(binding.stage)))
		append_string(out, fmt.tprintf("\t\tkind = gfx.Shader_Binding_Kind.%s,\n", binding_kind_odin(binding.kind)))
		append_string(out, fmt.tprintf("\t\tslot = %d,\n", binding.logical_slot))
		append_string(out, fmt.tprintf("\t\tnative_slot = %d,\n", binding.slot))
		append_string(out, fmt.tprintf("\t\tnative_space = %d,\n", binding.space))
		append_string(out, "\t}\n")
	}

	append_string(out, "\treturn desc\n")
	append_string(out, "}\n\n")

	return true
}

collect_binding_group_layout_entries :: proc(entries: ^[dynamic]Binding_Group_Layout_Entry, bindings: []Binding_Record) -> bool {
	for binding in bindings {
		entry_index, entry_found := binding_group_layout_entry_index(entries[:], binding)
		if !entry_found {
			entry := Binding_Group_Layout_Entry {
				kind = binding.kind,
				logical_slot = binding.logical_slot,
				name = binding.name,
				size = binding.size,
				view_kind = binding.view_kind,
				access = binding.access,
				storage_image_format = binding.storage_image_format,
				storage_buffer_stride = binding.storage_buffer_stride,
			}
			entry.stages[int(binding.stage)] = true
			append(entries, entry)
			continue
		}

		entry := &entries^[entry_index]
		if !binding_group_layout_entry_payload_matches(entry^, binding) {
			fmt.eprintln("ape_shaderc: inconsistent reflected binding payload for generated group entry: ", binding.name)
			return false
		}
		entry.stages[int(binding.stage)] = true
	}

	return true
}

binding_group_layout_entry_index :: proc(entries: []Binding_Group_Layout_Entry, binding: Binding_Record) -> (int, bool) {
	for entry, index in entries {
		if entry.kind == binding.kind &&
		   entry.logical_slot == binding.logical_slot &&
		   entry.name == binding.name {
			return index, true
		}
	}

	return -1, false
}

binding_group_layout_entry_payload_matches :: proc(entry: Binding_Group_Layout_Entry, binding: Binding_Record) -> bool {
	if entry.kind != binding.kind || entry.logical_slot != binding.logical_slot || entry.name != binding.name {
		return false
	}

	switch binding.kind {
	case .Uniform_Block:
		return entry.size == binding.size
	case .Resource_View:
		return entry.view_kind == binding.view_kind &&
		       entry.access == binding.access &&
		       entry.storage_image_format == binding.storage_image_format &&
		       entry.storage_buffer_stride == binding.storage_buffer_stride
	case .Sampler:
		return true
	}

	return false
}

append_stage_set_odin :: proc(out: ^[dynamic]byte, stages: [3]bool) {
	append_string(out, "{")
	wrote_stage := false
	for has_stage, index in stages {
		if !has_stage {
			continue
		}
		if wrote_stage {
			append_string(out, ", ")
		}
		append_string(out, ".")
		append_string(out, stage_odin(Stage(index)))
		wrote_stage = true
	}
	append_string(out, "}")
}

append_binding_helpers_odin :: proc(out: ^[dynamic]byte, bindings: []Binding_Record, uniform_blocks: []Uniform_Block) -> bool {
	emitted := make(map[string]bool)
	defer delete(emitted)

	append_string(out, "\n")
	for binding in bindings {
		prefix := binding_prefix(binding.kind)
		name := odin_identifier(binding.name)
		key := fmt.tprintf("%s:%s", prefix, name)
		if key in emitted {
			continue
		}
		emitted[key] = true

		switch binding.kind {
		case .Uniform_Block:
			block, block_ok := uniform_block_by_name(uniform_blocks, binding.name)
			if !block_ok {
				fmt.eprintln("ape_shaderc: missing generated uniform block helper target: ", binding.name)
				return false
			}

			block_name := odin_identifier(block.name)
			append_string(out, fmt.tprintf("apply_uniform_%s :: proc(ctx: ^gfx.Context, value: ^$T) -> bool ", block_name))
			append_string(out, "{\n")
			append_string(out, fmt.tprintf("\t#assert(size_of(T) == SIZE_%s)\n", block_name))
			append_string(out, fmt.tprintf("\treturn gfx.apply_uniform(ctx, UB_%s, value)\n", name))
			append_string(out, "}\n\n")
		case .Resource_View:
			append_string(out, fmt.tprintf("set_view_%s :: proc(bindings: ^gfx.Bindings, view: gfx.View) ", name))
			append_string(out, "{\n")
			append_string(out, "\tif bindings == nil {\n\t\treturn\n\t}\n")
			append_string(out, fmt.tprintf("\tbindings.views[VIEW_%s] = view\n", name))
			append_string(out, "}\n\n")
		case .Sampler:
			append_string(out, fmt.tprintf("set_sampler_%s :: proc(bindings: ^gfx.Bindings, sampler: gfx.Sampler) ", name))
			append_string(out, "{\n")
			append_string(out, "\tif bindings == nil {\n\t\treturn\n\t}\n")
			append_string(out, fmt.tprintf("\tbindings.samplers[SMP_%s] = sampler\n", name))
			append_string(out, "}\n\n")
		}
	}

	return true
}

uniform_block_by_name :: proc(blocks: []Uniform_Block, name: string) -> (Uniform_Block, bool) {
	for block in blocks {
		if block.name == name {
			return block, true
		}
	}

	return {}, false
}

append_vertex_layout_odin :: proc(out: ^[dynamic]byte, layout: Generated_Vertex_Layout) -> bool {
	append_string(out, fmt.tprintf("VERTEX_STRIDE :: %d\n", layout.stride))

	for attr in layout.attrs {
		prefix := vertex_attribute_constant_prefix(attr)
		append_string(out, fmt.tprintf("%s_OFFSET :: %d\n", prefix, attr.offset))
		append_string(out, fmt.tprintf("%s_SIZE :: %d\n", prefix, attr.size))
		append_string(out, fmt.tprintf("%s_FORMAT :: gfx.Vertex_Format.%s\n", prefix, generated_vertex_format_odin(attr.format)))
	}

	append_string(out, "\n")
	append_string(out, "layout_desc :: proc(buffer_slot: u32 = 0, stride: u32 = VERTEX_STRIDE, step_func: gfx.Vertex_Step_Function = .Per_Vertex, step_rate: u32 = 0) -> gfx.Layout_Desc {\n")
	append_string(out, "\tlayout: gfx.Layout_Desc\n")
	append_string(out, "\tlayout.buffers[buffer_slot] = {\n")
	append_string(out, "\t\tstride = stride,\n")
	append_string(out, "\t\tstep_func = step_func,\n")
	append_string(out, "\t\tstep_rate = step_rate,\n")
	append_string(out, "\t}\n\n")

	for attr, index in layout.attrs {
		prefix := vertex_attribute_constant_prefix(attr)
		append_string(out, fmt.tprintf("\tlayout.attrs[%d] = ", index))
		append_string(out, "{\n")
		append_string(out, fmt.tprintf("\t\tsemantic = cstring(\"%s\"),\n", attr.semantic))
		append_string(out, fmt.tprintf("\t\tsemantic_index = %d,\n", attr.semantic_index))
		append_string(out, fmt.tprintf("\t\tformat = %s_FORMAT,\n", prefix))
		append_string(out, "\t\tbuffer_slot = buffer_slot,\n")
		append_string(out, fmt.tprintf("\t\toffset = %s_OFFSET,\n", prefix))
		append_string(out, "\t}\n")
	}

	append_string(out, "\n\treturn layout\n")
	append_string(out, "}\n\n")
	return true
}

append_uniform_block_odin :: proc(out: ^[dynamic]byte, block: Uniform_Block) -> bool {
	block_name := odin_identifier(block.name)
	append_string(out, block_name)
	append_string(out, " :: struct {\n")

	current_offset := u32(0)
	pad_index := 0
	for field in block.fields {
		if field.offset < current_offset {
			fmt.eprintln("ape_shaderc: cannot represent overlapping uniform field layout: ", block.name, ".", field.name)
			return false
		}
		if field.offset > current_offset {
			pad_size := field.offset - current_offset
			append_string(out, fmt.tprintf("\t_pad%d: [%d]u8,\n", pad_index, pad_size))
			pad_index += 1
			current_offset += pad_size
		}

		field_name := odin_identifier(field.name)
		append_string(out, fmt.tprintf("\t%s: %s,\n", field_name, field.odin_type))
		current_offset += field.host_size
	}

	if block.size < current_offset {
		fmt.eprintln("ape_shaderc: generated uniform block is larger than reflected layout: ", block.name)
		return false
	}
	if block.size > current_offset {
		pad_size := block.size - current_offset
		append_string(out, fmt.tprintf("\t_pad%d: [%d]u8,\n", pad_index, pad_size))
	}
	append_string(out, "}\n\n")

	append_string(out, fmt.tprintf("SIZE_%s :: %d\n", block_name, block.size))
	append_string(out, fmt.tprintf("ALIGN_%s :: %d\n", block_name, block.alignment))
	append_string(out, fmt.tprintf("#assert(size_of(%s) == SIZE_%s)\n", block_name, block_name))
	for field in block.fields {
		field_name := odin_identifier(field.name)
		append_string(out, fmt.tprintf("OFFSET_%s_%s :: %d\n", block_name, field_name, field.offset))
		append_string(out, fmt.tprintf("SIZE_%s_%s :: %d\n", block_name, field_name, field.size))
		append_string(out, fmt.tprintf("#assert(offset_of(%s, %s) == OFFSET_%s_%s)\n", block_name, field_name, block_name, field_name))
	}
	append_string(out, "\n")

	return true
}

write_package :: proc(
	options: Options,
	stages: []Compiled_Stage,
	bindings: []Binding_Record,
	vertex_layout: Generated_Vertex_Layout,
) -> bool {
	stage_records := make([]Stage_Record, len(stages))
	defer delete(stage_records)

	binding_records := make([]Binding_Record, len(bindings))
	defer delete(binding_records)
	copy(binding_records, bindings)

	payload: [dynamic]byte
	defer delete(payload)

	payload_start := PACKAGE_HEADER_SIZE +
	                 PACKAGE_STAGE_RECORD_SIZE * len(stages) +
	                 PACKAGE_BINDING_RECORD_SIZE * len(bindings) +
	                 PACKAGE_VERTEX_INPUT_RECORD_SIZE * len(vertex_layout.attrs)
	for stage, index in stages {
		entry_offset := payload_start + len(payload)
		append_string(&payload, stage.entry)

		bytecode_offset := payload_start + len(payload)
		append_bytes(&payload, stage.bytecode)

		reflection_offset := payload_start + len(payload)
		append_bytes(&payload, stage.reflection)

		stage_records[index] = Stage_Record {
			target = stage.target,
			stage = stage.stage,
			entry_offset = u32(entry_offset),
			entry_size = u32(len(stage.entry)),
			bytecode_offset = u64(bytecode_offset),
			bytecode_size = u64(len(stage.bytecode)),
			reflection_offset = u64(reflection_offset),
			reflection_size = u64(len(stage.reflection)),
		}
	}

	for &binding in binding_records {
		name_offset := payload_start + len(payload)
		append_string(&payload, binding.name)
		binding.name_offset = u32(name_offset)
		binding.name_size = u32(len(binding.name))
	}

	vertex_semantic_offsets := make([]u32, len(vertex_layout.attrs))
	defer delete(vertex_semantic_offsets)
	for attr, index in vertex_layout.attrs {
		vertex_semantic_offsets[index] = u32(payload_start + len(payload))
		append_string(&payload, attr.semantic)
	}

	output: [dynamic]byte
	defer delete(output)

	write_u32(&output, PACKAGE_MAGIC)
	write_u32(&output, PACKAGE_VERSION)
	write_u32(&output, u32(len(stage_records)))
	write_u32(&output, u32(len(binding_records)))
	write_u32(&output, u32(len(vertex_layout.attrs)))

	for record in stage_records {
		write_u32(&output, u32(record.target))
		write_u32(&output, u32(record.stage))
		write_u32(&output, record.entry_offset)
		write_u32(&output, record.entry_size)
		write_u64(&output, record.bytecode_offset)
		write_u64(&output, record.bytecode_size)
		write_u64(&output, record.reflection_offset)
		write_u64(&output, record.reflection_size)
	}

	for record in binding_records {
		write_u32(&output, u32(record.target))
		write_u32(&output, u32(record.stage))
		write_u32(&output, u32(record.kind))
		write_u32(&output, record.slot)
		write_u32(&output, record.name_offset)
		write_u32(&output, record.name_size)
		write_u32(&output, 1)
		write_u32(&output, record.size)
		write_u32(&output, record.logical_slot)
		write_u32(&output, u32(record.view_kind))
		write_u32(&output, u32(record.access))
		write_u32(&output, u32(record.storage_image_format))
		write_u32(&output, record.storage_buffer_stride)
		write_u32(&output, record.space)
	}

	for attr, index in vertex_layout.attrs {
		write_u32(&output, vertex_semantic_offsets[index])
		write_u32(&output, u32(len(attr.semantic)))
		write_u32(&output, attr.semantic_index)
		write_u32(&output, package_vertex_format(attr.format))
		write_u32(&output, 1)
	}

	append_bytes(&output, payload[:])

	dir, _ := filepath.split(options.package_path)
	if dir != "" && !ensure_directory(dir) {
		return false
	}
	if !os.write_entire_file(options.package_path, output[:]) {
		fmt.eprintln("ape_shaderc: failed to write package: ", options.package_path)
		return false
	}

	return true
}

package_vertex_format :: proc(format: Generated_Vertex_Format) -> u32 {
	switch format {
	case .Float32:
		return 1
	case .Float32x2:
		return 2
	case .Float32x3:
		return 3
	case .Float32x4:
		return 4
	}

	return 0
}

write_u32 :: proc(out: ^[dynamic]byte, value: u32) {
	append(out, byte(value & 0xff))
	append(out, byte((value >> 8) & 0xff))
	append(out, byte((value >> 16) & 0xff))
	append(out, byte((value >> 24) & 0xff))
}

write_u64 :: proc(out: ^[dynamic]byte, value: u64) {
	write_u32(out, u32(value & 0xffffffff))
	write_u32(out, u32(value >> 32))
}

append_bytes :: proc(out: ^[dynamic]byte, data: []byte) {
	for b in data {
		append(out, b)
	}
}

ensure_directory :: proc(path: string) -> bool {
	normalized := trim_trailing_path_separators(path)
	if normalized == "" || os.exists(normalized) {
		return true
	}

	parent, _ := filepath.split(normalized)
	parent = trim_trailing_path_separators(parent)
	if parent != "" && parent != normalized && !os.exists(parent) {
		if !ensure_directory(parent) {
			return false
		}
	}

	err := os.make_directory(normalized)
	if err != nil && !os.exists(normalized) {
		fmt.eprintln("ape_shaderc: failed to create directory: ", normalized)
		return false
	}

	return true
}

trim_trailing_path_separators :: proc(path: string) -> string {
	end := len(path)
	for end > 0 {
		c := path[end - 1]
		if c != '/' && c != '\\' {
			break
		}
		if end == 3 && path[1] == ':' {
			break
		}
		end -= 1
	}

	return path[:end]
}

binding_prefix :: proc(kind: Binding_Kind) -> string {
	switch kind {
	case .Uniform_Block:
		return "UB"
	case .Resource_View:
		return "VIEW"
	case .Sampler:
		return "SMP"
	}

	return "BINDING"
}

resource_view_kind_odin :: proc(kind: Resource_View_Kind) -> string {
	switch kind {
	case .Sampled:
		return "Sampled"
	case .Storage_Image:
		return "Storage_Image"
	case .Storage_Buffer:
		return "Storage_Buffer"
	}

	return "Sampled"
}

resource_access_odin :: proc(access: Resource_Access) -> string {
	switch access {
	case .Unknown:
		return "Unknown"
	case .Read:
		return "Read"
	case .Write:
		return "Write"
	case .Read_Write:
		return "Read_Write"
	}

	return "Unknown"
}

storage_image_format_odin :: proc(format: Storage_Image_Format) -> string {
	switch format {
	case .RGBA32F:
		return "RGBA32F"
	case .R32F:
		return "R32F"
	case .Invalid:
		return "Invalid"
	}

	return "Invalid"
}

binding_kind_odin :: proc(kind: Binding_Kind) -> string {
	switch kind {
	case .Uniform_Block:
		return "Uniform_Block"
	case .Resource_View:
		return "Resource_View"
	case .Sampler:
		return "Sampler"
	}

	return "Uniform_Block"
}

backend_odin :: proc(target: Target) -> string {
	switch target {
	case .D3D11_DXBC:
		return "D3D11"
	case .Vulkan_SPIRV:
		return "Vulkan"
	}

	return "Auto"
}

stage_odin :: proc(stage: Stage) -> string {
	switch stage {
	case .Vertex:
		return "Vertex"
	case .Fragment:
		return "Fragment"
	case .Compute:
		return "Compute"
	}

	return "Vertex"
}

target_prefix :: proc(target: Target) -> string {
	switch target {
	case .D3D11_DXBC:
		return "D3D11"
	case .Vulkan_SPIRV:
		return "VK"
	}

	return "TARGET"
}

stage_prefix :: proc(stage: Stage) -> string {
	switch stage {
	case .Vertex:
		return "VS"
	case .Fragment:
		return "FS"
	case .Compute:
		return "CS"
	}

	return "STAGE"
}

generated_vertex_format_odin :: proc(format: Generated_Vertex_Format) -> string {
	switch format {
	case .Float32:
		return "Float32"
	case .Float32x2:
		return "Float32x2"
	case .Float32x3:
		return "Float32x3"
	case .Float32x4:
		return "Float32x4"
	}

	return "Invalid"
}

vertex_attribute_constant_prefix :: proc(attr: Generated_Vertex_Attribute) -> string {
	name := odin_identifier(attr.semantic)
	if attr.semantic_index == 0 {
		return fmt.tprintf("ATTR_%s", name)
	}

	return fmt.tprintf("ATTR_%s_%d", name, attr.semantic_index)
}

odin_identifier :: proc(name: string) -> string {
	if name == "" {
		return "binding"
	}

	out: [dynamic]byte
	for c in name {
		if ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || ('0' <= c && c <= '9') || c == '_' {
			append(&out, byte(c))
		} else {
			append(&out, '_')
		}
	}

	for len(out) > 0 && out[0] == '_' {
		ordered_remove(&out, 0)
	}
	for len(out) > 0 && out[len(out) - 1] == '_' {
		pop(&out)
	}

	if len(out) == 0 {
		append_string(&out, "binding")
	}
	if '0' <= out[0] && out[0] <= '9' {
		inject_at(&out, 0, byte('_'))
	}

	return string(out[:])
}
