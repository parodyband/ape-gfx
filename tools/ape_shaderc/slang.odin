package main

import "core:dynlib"
import json "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

SlangResult :: i32
SlangInt :: i64
SlangUInt :: u64
SlangProfileID :: u32
SlangCompileTarget :: i32
SlangStage :: u32
SlangTargetFlags :: u32
SlangFloatingPointMode :: u32
SlangLineDirectiveMode :: u32
SlangMatrixLayoutMode :: u32
SlangSessionFlags :: u32

SLANG_API_VERSION :: u32(0)
SLANG_LANGUAGE_VERSION_2025 :: u32(2025)
SLANG_PROFILE_UNKNOWN :: SlangProfileID(0)
SLANG_TARGET_DXBC :: SlangCompileTarget(8)
SLANG_TARGET_SPIRV :: SlangCompileTarget(6)
SLANG_STAGE_VERTEX :: SlangStage(1)
SLANG_STAGE_FRAGMENT :: SlangStage(5)
SLANG_STAGE_COMPUTE :: SlangStage(6)
SLANG_MATRIX_LAYOUT_ROW_MAJOR :: SlangMatrixLayoutMode(1)

Slang_Type_Kind :: enum u32 {
	None,
	Struct,
	Array,
	Matrix,
	Vector,
	Scalar,
	Constant_Buffer,
	Resource,
	Sampler_State,
	Texture_Buffer,
	Shader_Storage_Buffer,
	Parameter_Block,
	Generic_Type_Parameter,
	Interface,
	Output_Stream,
	Mesh_Output,
	Specialized,
	Feedback,
	Pointer,
	Dynamic_Resource,
}

Slang_Scalar_Type :: enum u32 {
	None,
	Void,
	Bool,
	Int32,
	Uint32,
	Int64,
	Uint64,
	Float16,
	Float32,
	Float64,
	Int8,
	Uint8,
	Int16,
	Uint16,
	Intptr,
	Uintptr,
}

Slang_Parameter_Category :: enum u32 {
	None,
	Mixed,
	Constant_Buffer,
	Shader_Resource,
	Unordered_Access,
	Varying_Input,
	Varying_Output,
	Sampler_State,
	Uniform,
	Descriptor_Table_Slot,
	Specialization_Constant,
	Push_Constant_Buffer,
	Register_Space,
	Generic,
	Ray_Payload,
	Hit_Attributes,
	Callable_Payload,
	Shader_Record,
	Existential_Type_Param,
	Existential_Object_Param,
	Sub_Element_Register_Space,
	Subpass,
	Metal_Argument_Buffer_Element,
	Metal_Attribute,
	Metal_Payload,
}

Slang_Layout_Parameter_Info :: struct {
	name: string,
	category: Slang_Parameter_Category,
	binding_index: u32,
	binding_space: u32,
	semantic_name: string,
	semantic_index: u32,
	type_kind: Slang_Type_Kind,
	scalar_type: Slang_Scalar_Type,
	element_count: uint,
	row_count: u32,
	column_count: u32,
	fields: [dynamic]Slang_Layout_Parameter_Info,
}

Slang_Entry_Point_Layout_Info :: struct {
	name: string,
	stage: SlangStage,
	has_default_constant_buffer: bool,
	compute_thread_group_size: [3]u32,
	parameters: [dynamic]Slang_Layout_Parameter_Info,
}

Slang_Program_Layout_Info :: struct {
	parameter_count: u32,
	entry_points: [dynamic]Slang_Entry_Point_Layout_Info,
}

ISlangUnknown :: struct #raw_union {
	using vtable: ^ISlangUnknown_VTable,
}

ISlangUnknown_VTable :: struct {
	queryInterface: proc "system" (this: ^ISlangUnknown, uuid: rawptr, out_object: ^rawptr) -> SlangResult,
	addRef: proc "system" (this: ^ISlangUnknown) -> u32,
	release: proc "system" (this: ^ISlangUnknown) -> u32,
}

ISlangBlob :: struct #raw_union {
	#subtype unknown: ISlangUnknown,
	using vtable: ^ISlangBlob_VTable,
}

ISlangBlob_VTable :: struct {
	using unknown_vtable: ISlangUnknown_VTable,
	getBufferPointer: proc "system" (this: ^ISlangBlob) -> rawptr,
	getBufferSize: proc "system" (this: ^ISlangBlob) -> uint,
}

ISlangCastable :: struct #raw_union {
	#subtype unknown: ISlangUnknown,
	using vtable: ^ISlangCastable_VTable,
}

ISlangCastable_VTable :: struct {
	using unknown_vtable: ISlangUnknown_VTable,
	castAs: proc "system" (this: ^ISlangCastable, uuid: rawptr) -> rawptr,
}

ISlangGlobalSession :: struct #raw_union {
	#subtype unknown: ISlangUnknown,
	using vtable: ^ISlangGlobalSession_VTable,
}

ISlangSession :: struct #raw_union {
	#subtype unknown: ISlangUnknown,
	using vtable: ^ISlangSession_VTable,
}

ISlangComponentType :: struct #raw_union {
	#subtype unknown: ISlangUnknown,
	using vtable: ^ISlangComponentType_VTable,
}

ISlangEntryPoint :: struct #raw_union {
	#subtype component: ISlangComponentType,
	using vtable: ^ISlangEntryPoint_VTable,
}

ISlangModule :: struct #raw_union {
	#subtype component: ISlangComponentType,
	using vtable: ^ISlangModule_VTable,
}

ISlangMetadata :: struct #raw_union {
	#subtype castable: ISlangCastable,
	using vtable: ^ISlangMetadata_VTable,
}

ISlangGlobalSession_VTable :: struct {
	using unknown_vtable: ISlangUnknown_VTable,
	createSession: proc "system" (this: ^ISlangGlobalSession, desc: ^Slang_Session_Desc, out_session: ^^ISlangSession) -> SlangResult,
	findProfile: proc "system" (this: ^ISlangGlobalSession, name: cstring) -> SlangProfileID,
}

ISlangSession_VTable :: struct {
	using unknown_vtable: ISlangUnknown_VTable,
	getGlobalSession: proc "system" (this: ^ISlangSession) -> ^ISlangGlobalSession,
	loadModule: proc "system" (this: ^ISlangSession, module_name: cstring, out_diagnostics: ^^ISlangBlob) -> ^ISlangModule,
	loadModuleFromSource: proc "system" (this: ^ISlangSession, module_name: cstring, path: cstring, source: ^ISlangBlob, out_diagnostics: ^^ISlangBlob) -> ^ISlangModule,
	createCompositeComponentType: proc "system" (
		this: ^ISlangSession,
		component_types: [^]^ISlangComponentType,
		component_type_count: SlangInt,
		out_composite_component_type: ^^ISlangComponentType,
		out_diagnostics: ^^ISlangBlob,
	) -> SlangResult,
	specializeType: rawptr,
	getTypeLayout: rawptr,
	getContainerType: rawptr,
	getDynamicType: rawptr,
	getTypeRTTIMangledName: rawptr,
	getTypeConformanceWitnessMangledName: rawptr,
	getTypeConformanceWitnessSequentialID: rawptr,
	reserved_interface_slot_11: rawptr,
	createTypeConformanceComponentType: rawptr,
	loadModuleFromIRBlob: rawptr,
	getLoadedModuleCount: rawptr,
	getLoadedModule: rawptr,
	isBinaryModuleUpToDate: rawptr,
	loadModuleFromSourceString: proc "system" (
		this: ^ISlangSession,
		module_name: cstring,
		path: cstring,
		source: cstring,
		out_diagnostics: ^^ISlangBlob,
	) -> ^ISlangModule,
}

ISlangComponentType_VTable :: struct {
	using unknown_vtable: ISlangUnknown_VTable,
	getSession: proc "system" (this: ^ISlangComponentType) -> ^ISlangSession,
	getLayout: proc "system" (this: ^ISlangComponentType, target_index: SlangInt, out_diagnostics: ^^ISlangBlob) -> rawptr,
	getSpecializationParamCount: proc "system" (this: ^ISlangComponentType) -> SlangInt,
	getEntryPointCode: proc "system" (
		this: ^ISlangComponentType,
		entry_point_index: SlangInt,
		target_index: SlangInt,
		out_code: ^^ISlangBlob,
		out_diagnostics: ^^ISlangBlob,
	) -> SlangResult,
	getResultAsFileSystem: rawptr,
	getEntryPointHash: rawptr,
	specialize: rawptr,
	link: proc "system" (
		this: ^ISlangComponentType,
		out_linked_component_type: ^^ISlangComponentType,
		out_diagnostics: ^^ISlangBlob,
	) -> SlangResult,
	getEntryPointHostCallable: rawptr,
	renameEntryPoint: rawptr,
	linkWithOptions: rawptr,
	getTargetCode: rawptr,
	getTargetMetadata: proc "system" (
		this: ^ISlangComponentType,
		target_index: SlangInt,
		out_metadata: ^^ISlangMetadata,
		out_diagnostics: ^^ISlangBlob,
	) -> SlangResult,
	getEntryPointMetadata: proc "system" (
		this: ^ISlangComponentType,
		entry_point_index: SlangInt,
		target_index: SlangInt,
		out_metadata: ^^ISlangMetadata,
		out_diagnostics: ^^ISlangBlob,
	) -> SlangResult,
}

ISlangMetadata_VTable :: struct {
	using castable_vtable: ISlangCastable_VTable,
	isParameterLocationUsed: proc "system" (
		this: ^ISlangMetadata,
		category: Slang_Parameter_Category,
		space_index: SlangUInt,
		register_index: SlangUInt,
		out_used: ^bool,
	) -> SlangResult,
}

ISlangEntryPoint_VTable :: struct {
	using component_vtable: ISlangComponentType_VTable,
	getFunctionReflection: proc "system" (this: ^ISlangEntryPoint) -> rawptr,
}

ISlangModule_VTable :: struct {
	using component_vtable: ISlangComponentType_VTable,
	findEntryPointByName: proc "system" (this: ^ISlangModule, name: cstring, out_entry_point: ^^ISlangEntryPoint) -> SlangResult,
	getDefinedEntryPointCount: proc "system" (this: ^ISlangModule) -> i32,
	getDefinedEntryPoint: proc "system" (this: ^ISlangModule, index: i32, out_entry_point: ^^ISlangEntryPoint) -> SlangResult,
	serialize: rawptr,
	writeToFile: rawptr,
	getName: proc "system" (this: ^ISlangModule) -> cstring,
	getFilePath: proc "system" (this: ^ISlangModule) -> cstring,
	getUniqueIdentity: proc "system" (this: ^ISlangModule) -> cstring,
	findAndCheckEntryPoint: proc "system" (
		this: ^ISlangModule,
		name: cstring,
		stage: SlangStage,
		out_entry_point: ^^ISlangEntryPoint,
		out_diagnostics: ^^ISlangBlob,
	) -> SlangResult,
	getDependencyFileCount: rawptr,
	getDependencyFilePath: rawptr,
	getModuleReflection: rawptr,
}

Slang_Global_Session_Desc :: struct {
	structureSize: u32,
	apiVersion: u32,
	languageVersion: u32,
	enableGLSL: bool,
	reserved: [16]u32,
}

Slang_Target_Desc :: struct {
	structureSize: uint,
	format: SlangCompileTarget,
	profile: SlangProfileID,
	flags: SlangTargetFlags,
	floatingPointMode: SlangFloatingPointMode,
	lineDirectiveMode: SlangLineDirectiveMode,
	forceGLSLScalarBufferLayout: bool,
	compilerOptionEntries: rawptr,
	compilerOptionEntryCount: u32,
}

Slang_Session_Desc :: struct {
	structureSize: uint,
	targets: ^Slang_Target_Desc,
	targetCount: SlangInt,
	flags: SlangSessionFlags,
	defaultMatrixLayoutMode: SlangMatrixLayoutMode,
	searchPaths: rawptr,
	searchPathCount: SlangInt,
	preprocessorMacros: rawptr,
	preprocessorMacroCount: SlangInt,
	fileSystem: rawptr,
	enableEffectAnnotations: bool,
	allowGLSLSyntax: bool,
	compilerOptionEntries: rawptr,
	compilerOptionEntryCount: u32,
}

Slang_API :: struct {
	slang_createGlobalSession2: proc "c" (desc: ^Slang_Global_Session_Desc, out_global_session: ^^ISlangGlobalSession) -> SlangResult,
	spReflection_ToJson: proc "c" (reflection: rawptr, request: rawptr, out_blob: ^rawptr) -> SlangResult,
	spReflection_GetParameterCount: proc "c" (reflection: rawptr) -> u32,
	spReflection_GetParameterByIndex: proc "c" (reflection: rawptr, index: u32) -> rawptr,
	spReflectionParameter_GetBindingIndex: proc "c" (parameter: rawptr) -> u32,
	spReflectionParameter_GetBindingSpace: proc "c" (parameter: rawptr) -> u32,
	spReflectionVariableLayout_GetVariable: proc "c" (variable_layout: rawptr) -> rawptr,
	spReflectionVariableLayout_GetTypeLayout: proc "c" (variable_layout: rawptr) -> rawptr,
	spReflectionVariableLayout_GetOffset: proc "c" (variable_layout: rawptr, category: Slang_Parameter_Category) -> uint,
	spReflectionVariableLayout_GetSemanticName: proc "c" (variable_layout: rawptr) -> cstring,
	spReflectionVariableLayout_GetSemanticIndex: proc "c" (variable_layout: rawptr) -> uint,
	spReflectionVariable_GetName: proc "c" (variable: rawptr) -> cstring,
	spReflectionTypeLayout_GetType: proc "c" (type_layout: rawptr) -> rawptr,
	spReflectionTypeLayout_getKind: proc "c" (type_layout: rawptr) -> Slang_Type_Kind,
	spReflectionTypeLayout_GetSize: proc "c" (type_layout: rawptr, category: Slang_Parameter_Category) -> uint,
	spReflectionTypeLayout_getAlignment: proc "c" (type_layout: rawptr, category: Slang_Parameter_Category) -> i32,
	spReflectionTypeLayout_GetFieldCount: proc "c" (type_layout: rawptr) -> u32,
	spReflectionTypeLayout_GetFieldByIndex: proc "c" (type_layout: rawptr, index: u32) -> rawptr,
	spReflectionTypeLayout_GetElementTypeLayout: proc "c" (type_layout: rawptr) -> rawptr,
	spReflectionTypeLayout_GetParameterCategory: proc "c" (type_layout: rawptr) -> Slang_Parameter_Category,
	spReflectionType_GetKind: proc "c" (typ: rawptr) -> Slang_Type_Kind,
	spReflectionType_GetElementCount: proc "c" (typ: rawptr) -> uint,
	spReflectionType_GetElementType: proc "c" (typ: rawptr) -> rawptr,
	spReflectionType_GetRowCount: proc "c" (typ: rawptr) -> u32,
	spReflectionType_GetColumnCount: proc "c" (typ: rawptr) -> u32,
	spReflectionType_GetScalarType: proc "c" (typ: rawptr) -> Slang_Scalar_Type,
	spReflection_getEntryPointCount: proc "c" (reflection: rawptr) -> SlangUInt,
	spReflection_getEntryPointByIndex: proc "c" (reflection: rawptr, index: SlangUInt) -> rawptr,
	spReflection_findEntryPointByName: proc "c" (reflection: rawptr, name: cstring) -> rawptr,
	spReflectionEntryPoint_getName: proc "c" (entry_point: rawptr) -> cstring,
	spReflectionEntryPoint_getParameterCount: proc "c" (entry_point: rawptr) -> u32,
	spReflectionEntryPoint_getParameterByIndex: proc "c" (entry_point: rawptr, index: u32) -> rawptr,
	spReflectionEntryPoint_getStage: proc "c" (entry_point: rawptr) -> SlangStage,
	spReflectionEntryPoint_getComputeThreadGroupSize: proc "c" (entry_point: rawptr, axis_count: SlangUInt, out_size_along_axis: ^SlangUInt),
	spReflectionEntryPoint_hasDefaultConstantBuffer: proc "c" (entry_point: rawptr) -> i32,
	handle: dynlib.Library,
}

load_slang_api :: proc(api: ^Slang_API) -> bool {
	candidates: [dynamic]string
	defer delete(candidates)

	if vulkan_sdk := os.get_env("VULKAN_SDK", context.temp_allocator); vulkan_sdk != "" {
		append(&candidates, filepath.join({vulkan_sdk, "Bin", "slang.dll"}))
	}
	append(&candidates, "slang.dll")

	for path in candidates {
		api^ = {}
		count, ok := dynlib.initialize_symbols(api, path, "", "handle")
		if ok && slang_api_valid(api) {
			return true
		}

		if api.handle != nil {
			dynlib.unload_library(api.handle)
			api.handle = nil
		}

		if count >= 0 {
			fmt.eprintln("ape_shaderc: incomplete Slang API load from ", path)
		}
	}

	fmt.eprintln("ape_shaderc: failed to load slang.dll. Install the Vulkan SDK or put slang.dll on PATH.")
	return false
}

unload_slang_api :: proc(api: ^Slang_API) {
	if api != nil && api.handle != nil {
		dynlib.unload_library(api.handle)
		api.handle = nil
	}
}

slang_api_valid :: proc(api: ^Slang_API) -> bool {
	return api.slang_createGlobalSession2 != nil &&
	       api.spReflection_ToJson != nil &&
	       api.spReflection_GetParameterCount != nil &&
	       api.spReflection_GetParameterByIndex != nil &&
	       api.spReflectionParameter_GetBindingIndex != nil &&
	       api.spReflectionParameter_GetBindingSpace != nil &&
	       api.spReflectionVariableLayout_GetVariable != nil &&
	       api.spReflectionVariableLayout_GetTypeLayout != nil &&
	       api.spReflectionVariableLayout_GetOffset != nil &&
	       api.spReflectionVariableLayout_GetSemanticName != nil &&
	       api.spReflectionVariableLayout_GetSemanticIndex != nil &&
	       api.spReflectionVariable_GetName != nil &&
	       api.spReflectionTypeLayout_GetType != nil &&
	       api.spReflectionTypeLayout_getKind != nil &&
	       api.spReflectionTypeLayout_GetSize != nil &&
	       api.spReflectionTypeLayout_getAlignment != nil &&
	       api.spReflectionTypeLayout_GetFieldCount != nil &&
	       api.spReflectionTypeLayout_GetFieldByIndex != nil &&
	       api.spReflectionTypeLayout_GetElementTypeLayout != nil &&
	       api.spReflectionTypeLayout_GetParameterCategory != nil &&
	       api.spReflectionType_GetKind != nil &&
	       api.spReflectionType_GetElementCount != nil &&
	       api.spReflectionType_GetElementType != nil &&
	       api.spReflectionType_GetRowCount != nil &&
	       api.spReflectionType_GetColumnCount != nil &&
	       api.spReflectionType_GetScalarType != nil &&
	       api.spReflection_getEntryPointCount != nil &&
	       api.spReflection_getEntryPointByIndex != nil &&
	       api.spReflection_findEntryPointByName != nil &&
	       api.spReflectionEntryPoint_getName != nil &&
	       api.spReflectionEntryPoint_getParameterCount != nil &&
	       api.spReflectionEntryPoint_getParameterByIndex != nil &&
	       api.spReflectionEntryPoint_getStage != nil &&
	       api.spReflectionEntryPoint_getComputeThreadGroupSize != nil &&
	       api.spReflectionEntryPoint_hasDefaultConstantBuffer != nil
}

slang_failed :: proc(result: SlangResult) -> bool {
	return result < 0
}

run_modern_slang_api_probe :: proc() -> bool {
	slang: Slang_API
	if !load_slang_api(&slang) {
		return false
	}
	defer unload_slang_api(&slang)

	return probe_modern_slang_api(&slang)
}

probe_modern_slang_api :: proc(api: ^Slang_API) -> bool {
	global_desc := Slang_Global_Session_Desc {
		structureSize = u32(size_of(Slang_Global_Session_Desc)),
		apiVersion = SLANG_API_VERSION,
		languageVersion = SLANG_LANGUAGE_VERSION_2025,
	}

	global_session: ^ISlangGlobalSession
	result := api.slang_createGlobalSession2(&global_desc, &global_session)
	if slang_failed(result) || global_session == nil {
		fmt.eprintln("ape_shaderc: slang_createGlobalSession2 failed")
		return false
	}
	defer release_slang_unknown(cast(^ISlangUnknown)global_session)

	dxbc_profile := global_session.vtable.findProfile(global_session, cstring("sm_5_0"))
	if dxbc_profile == SLANG_PROFILE_UNKNOWN {
		fmt.eprintln("ape_shaderc: Slang could not resolve profile sm_5_0")
		return false
	}

	spirv_profile := global_session.vtable.findProfile(global_session, cstring("glsl_450"))
	if spirv_profile == SLANG_PROFILE_UNKNOWN {
		fmt.eprintln("ape_shaderc: Slang could not resolve profile glsl_450")
		return false
	}

	targets := [?]Slang_Target_Desc {
		{
			structureSize = uint(size_of(Slang_Target_Desc)),
			format = SLANG_TARGET_DXBC,
			profile = dxbc_profile,
		},
		{
			structureSize = uint(size_of(Slang_Target_Desc)),
			format = SLANG_TARGET_SPIRV,
			profile = spirv_profile,
		},
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
		fmt.eprintln("ape_shaderc: modern Slang createSession failed")
		return false
	}
	defer release_slang_unknown(cast(^ISlangUnknown)session)

	if !probe_slang_program_layout_reflection(api, session) {
		return false
	}

	fmt.println("Modern Slang API probe passed")
	return true
}

probe_slang_program_layout_reflection :: proc(api: ^Slang_API, session: ^ISlangSession) -> bool {
	source := `
struct VS_Output
{
	float4 position : SV_Position;
	float3 color : COLOR0;
};

[shader("vertex")]
VS_Output vs_main(float3 position : POSITION, float3 color : COLOR0)
{
	VS_Output output;
	output.position = float4(position, 1.0);
	output.color = color;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return float4(input.color, 1.0);
}

[shader("compute")]
[numthreads(8, 4, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
}
`

	source_c, source_err := strings.clone_to_cstring(source, context.temp_allocator)
	if source_err != nil {
		fmt.eprintln("ape_shaderc: failed to prepare Slang reflection probe source")
		return false
	}

	diagnostics: ^ISlangBlob
	module := session.vtable.loadModuleFromSourceString(
		session,
		cstring("ape_reflection_probe"),
		cstring("ape_reflection_probe.slang"),
		source_c,
		&diagnostics,
	)
	if diagnostics != nil {
		if module == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
	}
	if module == nil {
		fmt.eprintln("ape_shaderc: failed to load Slang reflection probe module")
		return false
	}
	defer release_slang_unknown(cast(^ISlangUnknown)module)

	if !probe_slang_entry_layout(api, session, module, "vs_main", SLANG_STAGE_VERTEX, [3]u32{0, 0, 0}) {
		return false
	}
	if !probe_slang_entry_layout(api, session, module, "cs_main", SLANG_STAGE_COMPUTE, [3]u32{8, 4, 1}) {
		return false
	}

	return true
}

probe_slang_entry_layout :: proc(
	api: ^Slang_API,
	session: ^ISlangSession,
	module: ^ISlangModule,
	entry_name: string,
	stage: SlangStage,
	expected_thread_group: [3]u32,
) -> bool {
	entry_name_c, entry_name_err := strings.clone_to_cstring(entry_name, context.temp_allocator)
	if entry_name_err != nil {
		fmt.eprintln("ape_shaderc: failed to prepare Slang reflection entry name")
		return false
	}

	diagnostics: ^ISlangBlob
	entry_point: ^ISlangEntryPoint
	result := module.vtable.findAndCheckEntryPoint(module, entry_name_c, stage, &entry_point, &diagnostics)
	if diagnostics != nil {
		if slang_failed(result) || entry_point == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
		diagnostics = nil
	}
	if slang_failed(result) || entry_point == nil {
		fmt.eprintln("ape_shaderc: failed to find Slang reflection probe entry point: ", entry_name)
		return false
	}
	defer release_slang_unknown(cast(^ISlangUnknown)entry_point)

	component_types := [?]^ISlangComponentType {
		cast(^ISlangComponentType)module,
		cast(^ISlangComponentType)entry_point,
	}

	composite: ^ISlangComponentType
	result = session.vtable.createCompositeComponentType(session, raw_data(component_types[:]), SlangInt(len(component_types)), &composite, &diagnostics)
	if diagnostics != nil {
		if slang_failed(result) || composite == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
		diagnostics = nil
	}
	if slang_failed(result) || composite == nil {
		fmt.eprintln("ape_shaderc: failed to create Slang reflection probe composite: ", entry_name)
		return false
	}
	// Match the production compile path: the linked component keeps internal
	// ownership tied to the composite, so keep a defensive reference alive.
	_ = (cast(^ISlangUnknown)composite).vtable.addRef(cast(^ISlangUnknown)composite)
	defer release_slang_unknown(cast(^ISlangUnknown)composite)

	linked: ^ISlangComponentType
	result = composite.vtable.link(composite, &linked, &diagnostics)
	if diagnostics != nil {
		if slang_failed(result) || linked == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
		diagnostics = nil
	}
	if slang_failed(result) || linked == nil {
		fmt.eprintln("ape_shaderc: failed to link Slang reflection probe component: ", entry_name)
		return false
	}
	defer release_slang_unknown(cast(^ISlangUnknown)linked)

	layout := linked.vtable.getLayout(linked, 0, &diagnostics)
	if diagnostics != nil {
		if layout == nil {
			print_slang_blob_diagnostics(diagnostics)
		}
		release_slang_unknown(cast(^ISlangUnknown)diagnostics)
	}
	if layout == nil {
		fmt.eprintln("ape_shaderc: Slang reflection probe returned no layout: ", entry_name)
		return false
	}

	info: Slang_Program_Layout_Info
	if !collect_slang_program_layout_info(api, layout, &info) {
		return false
	}
	defer delete_slang_program_layout_info(&info)

	if len(info.entry_points) != 1 {
		fmt.eprintln("ape_shaderc: Slang reflection probe expected one entry point for ", entry_name)
		return false
	}
	entry_info := info.entry_points[0]
	if entry_info.name != entry_name || entry_info.stage != stage {
		fmt.eprintln("ape_shaderc: Slang reflection probe entry point mismatch for ", entry_name)
		return false
	}

	if stage == SLANG_STAGE_VERTEX {
		if !slang_entry_has_semantic(entry_info, "POSITION", 0) || !slang_entry_has_semantic(entry_info, "COLOR", 0) {
			fmt.eprintln("ape_shaderc: Slang reflection probe did not expose expected vertex input semantics")
			return false
		}
	}

	if stage == SLANG_STAGE_COMPUTE {
		if entry_info.compute_thread_group_size != expected_thread_group {
			fmt.eprintln("ape_shaderc: Slang reflection probe compute thread-group size mismatch")
			return false
		}
	}

	if !compare_slang_api_entry_layout_with_json(api, layout, entry_info, entry_name, stage, expected_thread_group) {
		return false
	}

	return true
}

compare_slang_api_entry_layout_with_json :: proc(
	api: ^Slang_API,
	layout: rawptr,
	api_entry: Slang_Entry_Point_Layout_Info,
	entry_name: string,
	slang_stage: SlangStage,
	expected_thread_group: [3]u32,
) -> bool {
	json_blob: rawptr
	result := api.spReflection_ToJson(layout, nil, &json_blob)
	if slang_failed(result) || json_blob == nil {
		fmt.eprintln("ape_shaderc: Slang reflection probe failed to serialize JSON")
		return false
	}
	defer release_slang_blob(json_blob)

	json_bytes := copy_blob_bytes(json_blob)
	if json_bytes == nil {
		fmt.eprintln("ape_shaderc: Slang reflection probe failed to copy JSON")
		return false
	}
	defer delete(json_bytes)

	stage, stage_ok := stage_for_slang_stage(slang_stage)
	if !stage_ok {
		return false
	}

	stage_desc := Stage_Desc {
		stage = stage,
		entry = entry_name,
	}
	options := Options {
		source_path = "ape_reflection_probe.slang",
	}

	model, model_ok := parse_reflection_model(options, stage_desc, json_bytes)
	if !model_ok {
		return false
	}
	defer delete_reflection_model(&model)

	entry_point, entry_ok := json_entry_point_by_name_stage(model.root, entry_name, stage_name_for_slang_stage(slang_stage))
	if !entry_ok {
		fmt.eprintln("ape_shaderc: Slang reflection probe JSON has no matching entry point: ", entry_name)
		return false
	}

	if api_entry.name != entry_name {
		fmt.eprintln("ape_shaderc: Slang API reflection entry name disagrees with JSON: ", entry_name)
		return false
	}

	if slang_stage == SLANG_STAGE_VERTEX {
		api_has_position := slang_entry_has_semantic(api_entry, "POSITION", 0)
		api_has_color := slang_entry_has_semantic(api_entry, "COLOR", 0)
		json_has_position := json_entry_has_semantic(entry_point, "POSITION", 0)
		json_has_color := json_entry_has_semantic(entry_point, "COLOR", 0)
		if api_has_position != json_has_position || api_has_color != json_has_color {
			fmt.eprintln("ape_shaderc: Slang API and JSON vertex semantic reflection disagree")
			return false
		}
	}

	if slang_stage == SLANG_STAGE_COMPUTE {
		json_group: Compute_Thread_Group_Size
		if !collect_compute_thread_group_from_json_reflection(options, stage_desc, model.root, &json_group) {
			return false
		}
		if api_entry.compute_thread_group_size != expected_thread_group ||
		   api_entry.compute_thread_group_size[0] != json_group.x ||
		   api_entry.compute_thread_group_size[1] != json_group.y ||
		   api_entry.compute_thread_group_size[2] != json_group.z {
			fmt.eprintln("ape_shaderc: Slang API and JSON compute thread-group reflection disagree")
			return false
		}
	}

	return true
}

json_entry_point_by_name_stage :: proc(root: json.Object, name: string, stage: string) -> (json.Object, bool) {
	entry_points_value, entry_points_ok := json_field(root, "entryPoints")
	if !entry_points_ok {
		return {}, false
	}
	entry_points, entry_points_array_ok := json_array(entry_points_value)
	if !entry_points_array_ok {
		return {}, false
	}

	for entry_point_value in entry_points {
		entry_point, entry_point_ok := json_object(entry_point_value)
		if !entry_point_ok {
			continue
		}
		entry_name, entry_name_ok := json_string_field(entry_point, "name")
		entry_stage, entry_stage_ok := json_string_field(entry_point, "stage")
		if entry_name_ok && entry_stage_ok && entry_name == name && entry_stage == stage {
			return entry_point, true
		}
	}

	return {}, false
}

json_entry_has_semantic :: proc(entry_point: json.Object, semantic_name: string, semantic_index: u32) -> bool {
	parameters_value, parameters_ok := json_field(entry_point, "parameters")
	if !parameters_ok {
		return false
	}
	parameters, parameters_array_ok := json_array(parameters_value)
	if !parameters_array_ok {
		return false
	}

	for parameter_value in parameters {
		parameter, parameter_ok := json_object(parameter_value)
		if !parameter_ok {
			continue
		}

		if json_object_has_semantic(parameter, semantic_name, semantic_index) {
			return true
		}

		if type_value, type_ok := json_field(parameter, "type"); type_ok &&
		   json_type_has_semantic(type_value, semantic_name, semantic_index) {
			return true
		}
	}

	return false
}

json_type_has_semantic :: proc(type_value: json.Value, semantic_name: string, semantic_index: u32) -> bool {
	type_object, type_object_ok := json_object(type_value)
	if !type_object_ok {
		return false
	}

	if json_object_has_semantic(type_object, semantic_name, semantic_index) {
		return true
	}

	fields_value, fields_ok := json_field(type_object, "fields")
	if !fields_ok {
		return false
	}
	fields, fields_array_ok := json_array(fields_value)
	if !fields_array_ok {
		return false
	}

	for field_value in fields {
		field, field_ok := json_object(field_value)
		if !field_ok {
			continue
		}
		if json_object_has_semantic(field, semantic_name, semantic_index) {
			return true
		}
		if field_type_value, field_type_ok := json_field(field, "type"); field_type_ok &&
		   json_type_has_semantic(field_type_value, semantic_name, semantic_index) {
			return true
		}
	}

	return false
}

json_object_has_semantic :: proc(object: json.Object, semantic_name: string, semantic_index: u32) -> bool {
	reflected_semantic, semantic_ok := json_string_field(object, "semanticName")
	if !semantic_ok {
		return false
	}

	base, index, parse_ok := parse_vertex_semantic(reflected_semantic)
	if !parse_ok {
		return false
	}
	defer delete(base)

	return base == semantic_name && index == semantic_index
}

stage_for_slang_stage :: proc(stage: SlangStage) -> (Stage, bool) {
	switch stage {
	case SLANG_STAGE_VERTEX:
		return .Vertex, true
	case SLANG_STAGE_FRAGMENT:
		return .Fragment, true
	case SLANG_STAGE_COMPUTE:
		return .Compute, true
	}
	return .Vertex, false
}

stage_name_for_slang_stage :: proc(stage: SlangStage) -> string {
	switch stage {
	case SLANG_STAGE_VERTEX:
		return "vertex"
	case SLANG_STAGE_FRAGMENT:
		return "fragment"
	case SLANG_STAGE_COMPUTE:
		return "compute"
	}
	return ""
}

collect_slang_program_layout_info :: proc(api: ^Slang_API, layout: rawptr, out_info: ^Slang_Program_Layout_Info) -> bool {
	out_info^ = {}
	if layout == nil {
		return false
	}

	out_info.parameter_count = api.spReflection_GetParameterCount(layout)
	entry_point_count := api.spReflection_getEntryPointCount(layout)
	for i in 0..<int(entry_point_count) {
		entry_point := api.spReflection_getEntryPointByIndex(layout, SlangUInt(i))
		if entry_point == nil {
			continue
		}

		entry_info: Slang_Entry_Point_Layout_Info
		if !collect_slang_entry_point_layout_info(api, entry_point, &entry_info) {
			delete_slang_program_layout_info(out_info)
			return false
		}
		append(&out_info.entry_points, entry_info)
	}

	return true
}

collect_slang_entry_point_layout_info :: proc(api: ^Slang_API, entry_point: rawptr, out_info: ^Slang_Entry_Point_Layout_Info) -> bool {
	out_info^ = {}
	if entry_point == nil {
		return false
	}

	out_info.name = slang_clone_cstring_owned(api.spReflectionEntryPoint_getName(entry_point))
	out_info.stage = api.spReflectionEntryPoint_getStage(entry_point)
	out_info.has_default_constant_buffer = api.spReflectionEntryPoint_hasDefaultConstantBuffer(entry_point) != 0

	thread_group: [3]SlangUInt
	api.spReflectionEntryPoint_getComputeThreadGroupSize(entry_point, 3, &thread_group[0])
	out_info.compute_thread_group_size = {
		u32(thread_group[0]),
		u32(thread_group[1]),
		u32(thread_group[2]),
	}

	parameter_count := api.spReflectionEntryPoint_getParameterCount(entry_point)
	for i in 0..<int(parameter_count) {
		parameter := api.spReflectionEntryPoint_getParameterByIndex(entry_point, u32(i))
		if parameter == nil {
			continue
		}

		parameter_info := collect_slang_layout_parameter_info(api, parameter)
		append(&out_info.parameters, parameter_info)
	}

	return true
}

collect_slang_layout_parameter_info :: proc(api: ^Slang_API, parameter: rawptr) -> Slang_Layout_Parameter_Info {
	info: Slang_Layout_Parameter_Info

	variable := api.spReflectionVariableLayout_GetVariable(parameter)
	if variable != nil {
		info.name = slang_replace_owned(info.name, api.spReflectionVariable_GetName(variable))
	}

	info.binding_index = api.spReflectionParameter_GetBindingIndex(parameter)
	info.binding_space = api.spReflectionParameter_GetBindingSpace(parameter)
	info.semantic_name = slang_replace_owned(info.semantic_name, api.spReflectionVariableLayout_GetSemanticName(parameter))
	info.semantic_index = u32(api.spReflectionVariableLayout_GetSemanticIndex(parameter))

	type_layout := api.spReflectionVariableLayout_GetTypeLayout(parameter)
	if type_layout == nil {
		return info
	}

	info.category = api.spReflectionTypeLayout_GetParameterCategory(type_layout)
	info.type_kind = api.spReflectionTypeLayout_getKind(type_layout)

	typ := api.spReflectionTypeLayout_GetType(type_layout)
	if typ != nil {
		slang_fill_type_info(api, typ, &info)
	}

	field_count := api.spReflectionTypeLayout_GetFieldCount(type_layout)
	for i in 0..<int(field_count) {
		field_layout := api.spReflectionTypeLayout_GetFieldByIndex(type_layout, u32(i))
		if field_layout == nil {
			continue
		}
		field_info := collect_slang_layout_parameter_info(api, field_layout)
		append(&info.fields, field_info)
	}

	return info
}

slang_fill_type_info :: proc(api: ^Slang_API, typ: rawptr, info: ^Slang_Layout_Parameter_Info) {
	if typ == nil {
		return
	}

	info.type_kind = api.spReflectionType_GetKind(typ)
	info.element_count = api.spReflectionType_GetElementCount(typ)
	info.row_count = api.spReflectionType_GetRowCount(typ)
	info.column_count = api.spReflectionType_GetColumnCount(typ)

	#partial switch info.type_kind {
	case .Scalar:
		info.scalar_type = api.spReflectionType_GetScalarType(typ)
		if info.element_count == 0 {
			info.element_count = 1
		}
	case .Vector, .Matrix:
		element_type := api.spReflectionType_GetElementType(typ)
		if element_type != nil {
			info.scalar_type = api.spReflectionType_GetScalarType(element_type)
		}
	case:
		info.scalar_type = api.spReflectionType_GetScalarType(typ)
	}
}

slang_entry_has_semantic :: proc(entry: Slang_Entry_Point_Layout_Info, semantic_name: string, semantic_index: u32) -> bool {
	for parameter in entry.parameters {
		if slang_parameter_has_semantic(parameter, semantic_name, semantic_index) {
			return true
		}
	}
	return false
}

slang_parameter_has_semantic :: proc(parameter: Slang_Layout_Parameter_Info, semantic_name: string, semantic_index: u32) -> bool {
	if parameter.semantic_name == semantic_name && parameter.semantic_index == semantic_index {
		return true
	}
	for field in parameter.fields {
		if slang_parameter_has_semantic(field, semantic_name, semantic_index) {
			return true
		}
	}
	return false
}

delete_slang_program_layout_info :: proc(info: ^Slang_Program_Layout_Info) {
	for &entry in info.entry_points {
		delete_slang_entry_point_layout_info(&entry)
	}
	delete(info.entry_points)
	info^ = {}
}

delete_slang_entry_point_layout_info :: proc(info: ^Slang_Entry_Point_Layout_Info) {
	if info.name != "" {
		delete(info.name)
	}
	for &parameter in info.parameters {
		delete_slang_layout_parameter_info(&parameter)
	}
	delete(info.parameters)
	info^ = {}
}

delete_slang_layout_parameter_info :: proc(info: ^Slang_Layout_Parameter_Info) {
	if info.name != "" {
		delete(info.name)
	}
	if info.semantic_name != "" {
		delete(info.semantic_name)
	}
	for &field in info.fields {
		delete_slang_layout_parameter_info(&field)
	}
	delete(info.fields)
	info^ = {}
}

slang_replace_owned :: proc(old: string, value: cstring) -> string {
	if old != "" {
		delete(old)
	}
	return slang_clone_cstring_owned(value)
}

slang_clone_cstring_owned :: proc(value: cstring) -> string {
	if value == nil {
		return ""
	}
	cloned, err := strings.clone_from_cstring(value)
	if err != nil {
		return ""
	}
	return cloned
}

release_slang_unknown :: proc(object: ^ISlangUnknown) {
	if object == nil {
		return
	}

	object.vtable.release(object)
}
