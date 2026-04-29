package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"

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
	createCompileRequest: rawptr,
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
	getTargetMetadata: rawptr,
	getEntryPointMetadata: rawptr,
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
	spCreateSession: proc "c" (deprecated: cstring) -> rawptr,
	spDestroySession: proc "c" (session: rawptr),
	spCreateCompileRequest: proc "c" (session: rawptr) -> rawptr,
	spDestroyCompileRequest: proc "c" (request: rawptr),
	spProcessCommandLineArguments: proc "c" (request: rawptr, args: [^]cstring, arg_count: i32) -> SlangResult,
	spCompile: proc "c" (request: rawptr) -> SlangResult,
	spGetEntryPointCodeBlob: proc "c" (request: rawptr, entry_point_index: i32, target_index: i32, out_blob: ^rawptr) -> SlangResult,
	spGetDiagnosticOutput: proc "c" (request: rawptr) -> cstring,
	spGetReflection: proc "c" (request: rawptr) -> rawptr,
	spReflection_ToJson: proc "c" (reflection: rawptr, request: rawptr, out_blob: ^rawptr) -> SlangResult,
	spReflection_GetParameterCount: proc "c" (reflection: rawptr) -> u32,
	spReflection_GetParameterByIndex: proc "c" (reflection: rawptr, index: u32) -> rawptr,
	spReflectionParameter_GetBindingIndex: proc "c" (parameter: rawptr) -> u32,
	spReflectionParameter_GetBindingSpace: proc "c" (parameter: rawptr) -> u32,
	spReflectionVariableLayout_GetVariable: proc "c" (variable_layout: rawptr) -> rawptr,
	spReflectionVariableLayout_GetTypeLayout: proc "c" (variable_layout: rawptr) -> rawptr,
	spReflectionVariableLayout_GetOffset: proc "c" (variable_layout: rawptr, category: Slang_Parameter_Category) -> uint,
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
	spIsParameterLocationUsed: proc "c" (
		request: rawptr,
		entry_point_index: SlangInt,
		target_index: SlangInt,
		category: Slang_Parameter_Category,
		space_index: SlangUInt,
		register_index: SlangUInt,
		out_used: ^bool,
	) -> SlangResult,
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
	       api.spCreateSession != nil &&
	       api.spDestroySession != nil &&
	       api.spCreateCompileRequest != nil &&
	       api.spDestroyCompileRequest != nil &&
	       api.spProcessCommandLineArguments != nil &&
	       api.spCompile != nil &&
	       api.spGetEntryPointCodeBlob != nil &&
	       api.spGetDiagnosticOutput != nil &&
	       api.spGetReflection != nil &&
	       api.spReflection_ToJson != nil &&
	       api.spReflection_GetParameterCount != nil &&
	       api.spReflection_GetParameterByIndex != nil &&
	       api.spReflectionParameter_GetBindingIndex != nil &&
	       api.spReflectionParameter_GetBindingSpace != nil &&
	       api.spReflectionVariableLayout_GetVariable != nil &&
	       api.spReflectionVariableLayout_GetTypeLayout != nil &&
	       api.spReflectionVariableLayout_GetOffset != nil &&
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
	       api.spIsParameterLocationUsed != nil
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

	fmt.println("Modern Slang API probe passed")
	return true
}

release_slang_unknown :: proc(object: ^ISlangUnknown) {
	if object == nil {
		return
	}

	object.vtable.release(object)
}
