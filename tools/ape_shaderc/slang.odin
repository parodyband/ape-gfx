package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"

SlangResult :: i32
SlangInt :: i64
SlangUInt :: u64

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

Slang_API :: struct {
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
	return api.spCreateSession != nil &&
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
