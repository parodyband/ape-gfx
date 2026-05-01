package main

import "core:fmt"
import "core:os"
import os2 "core:os/os2"
import "core:path/filepath"
import "core:strings"

Shader_Test_Options :: struct {
	root_path: string,
	name: string,
	all: bool,
}

Shader_Test_Context :: struct {
	root: string,
	shaderc_path: string,
	base_dir: string,
}

parse_shader_test_options :: proc(args: []string) -> (Shader_Test_Options, bool) {
	options := Shader_Test_Options {
		root_path = ".",
		name = "all",
		all = true,
	}

	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		switch arg {
		case "-all", "-All":
			options.all = true
			options.name = "all"
		case "-root", "-Root":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.root_path = args[i]
		case "-name", "-Name":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.name = args[i]
			options.all = options.name == "all"
		case:
			return {}, false
		}
	}

	return options, true
}

run_shader_tests :: proc(options: Shader_Test_Options) -> bool {
	root, root_ok := filepath.abs(options.root_path, context.temp_allocator)
	if !root_ok {
		fmt.eprintln("ape: failed to resolve repo root: ", options.root_path)
		return false
	}

	tool_dir := repo_path(root, "build/tools")
	if !ensure_directory(tool_dir) {
		return false
	}

	shaderc_path := filepath.join({tool_dir, fmt.tprintf("ape_shaderc%s", EXE_SUFFIX)}, context.temp_allocator)
	if !build_shaderc(root, shaderc_path) {
		return false
	}

	test_ctx := Shader_Test_Context {
		root = root,
		shaderc_path = shaderc_path,
		base_dir = repo_path(root, "build/validation_tests"),
	}
	if !ensure_directory(test_ctx.base_dir) {
		return false
	}

	if options.all {
		tests := [?]string {
			"modern-api-probe",
			"register-free-samples",
			"descriptor-table-slots",
			"parameter-block-groups",
			"resource-arrays",
			"invalid-vertex-layout",
			"uniform-host-layout",
			"storage-resource-metadata",
			"ashader-roundtrip",
		}
		for test in tests {
			if !run_shader_test_by_name(&test_ctx, test) {
				return false
			}
		}
		fmt.println("Shaderc validation tests passed")
		return true
	}

	return run_shader_test_by_name(&test_ctx, options.name)
}

run_shader_test_by_name :: proc(ctx: ^Shader_Test_Context, name: string) -> bool {
	switch name {
	case "modern-api-probe":
		return test_shaderc_modern_api_probe(ctx)
	case "register-free-samples":
		return test_shaderc_register_free_samples(ctx)
	case "descriptor-table-slots":
		return test_shaderc_descriptor_table_slots(ctx)
	case "parameter-block-groups":
		return test_shaderc_parameter_block_groups(ctx)
	case "resource-arrays":
		return test_shaderc_resource_arrays(ctx)
	case "invalid-vertex-layout":
		return test_shaderc_invalid_vertex_layout(ctx)
	case "uniform-host-layout":
		return test_shaderc_uniform_host_layout(ctx)
	case "storage-resource-metadata":
		return test_shaderc_storage_resource_metadata(ctx)
	case "ashader-roundtrip":
		return test_ashader_roundtrip(ctx)
	case:
		fmt.eprintln("ape: unknown shader test: ", name)
		return false
	}
}

test_shaderc_modern_api_probe :: proc(ctx: ^Shader_Test_Context) -> bool {
	command := [?]string {ctx.shaderc_path, "-probe-modern-api"}
	if !run_command("shader test modern-api-probe", command[:], ctx.root) {
		return false
	}
	fmt.println("Shaderc modern Slang API probe passed")
	return true
}

Register_Free_Walk_State :: struct {
	ok: bool,
}

test_shaderc_register_free_samples :: proc(ctx: ^Shader_Test_Context) -> bool {
	state := Register_Free_Walk_State {ok = true}
	shader_dir := repo_path(ctx.root, "assets/shaders")
	err := filepath.walk(shader_dir, register_free_walk_proc, &state)
	if err != nil {
		fmt.eprintln("ape: failed to scan sample shaders for register annotations")
		return false
	}
	if !state.ok {
		return false
	}

	fmt.println("Sample Slang shaders are register-free")
	return true
}

register_free_walk_proc :: proc(info: os.File_Info, in_err: os.Error, user_data: rawptr) -> (err: os.Error, skip_dir: bool) {
	state := cast(^Register_Free_Walk_State)user_data
	if in_err != nil || info.is_dir || !strings.has_suffix(info.name, ".slang") {
		return nil, false
	}

	bytes, ok := os.read_entire_file(info.fullpath)
	if !ok {
		fmt.eprintln("ape: failed to read shader source: ", info.fullpath)
		state.ok = false
		return nil, false
	}
	defer delete(bytes)

	source := string(bytes)
	if strings.contains(source, "register(") || strings.contains(source, "register (") {
		fmt.eprintln("Sample Slang shaders should not use routine manual register annotations: ", info.fullpath)
		state.ok = false
	}
	return nil, false
}

test_shaderc_descriptor_table_slots :: proc(ctx: ^Shader_Test_Context) -> bool {
	test_dir := shader_test_dir(ctx, "shaderc_descriptor_table_slots")
	source_path := filepath.join({test_dir, "descriptor_table_slots.slang"}, context.temp_allocator)
	package_path := filepath.join({test_dir, "descriptor_table_slots.ashader"}, context.temp_allocator)
	generated_path := filepath.join({test_dir, "bindings.odin"}, context.temp_allocator)

	source := `struct Item
{
	float4 value;
	uint id;
};

cbuffer FrameUniforms
{
	float4 tint;
};

Texture2D<float4> input_texture;
SamplerState input_sampler;
RWTexture2D<float4> output_image;
RWStructuredBuffer<Item> output_items;

[shader("compute")]
[numthreads(8, 4, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	float2 uv = float2(0.5, 0.5);
	float4 color = input_texture.SampleLevel(input_sampler, uv, 0.0) * tint;

	output_image[dispatch_id.xy] = color;

	Item item;
	item.value = color;
	item.id = dispatch_id.x;
	output_items[dispatch_id.y * 1024 + dispatch_id.x] = item;
}
`
	if strings.contains(source, "register(") || strings.contains(source, "register (") {
		fmt.eprintln("descriptor table slot test shader must stay register-free")
		return false
	}
	if !write_text_file(source_path, source) {
		return false
	}
	if !run_shaderc_success(ctx, "descriptor_table_slots", .Compute, source_path, package_path, generated_path, test_dir) {
		return false
	}

	generated, generated_ok := read_text_file(generated_path)
	if !generated_ok {
		return false
	}
	defer delete(generated)

	expected := [?]string {
		"BINDING_RECORD_COUNT :: 10",
		"GROUP_0 :: 0",
		"D3D12_CS_UB_FrameUniforms :: 0",
		"D3D12_CS_VIEW_input_texture :: 0",
		"D3D12_CS_SMP_input_sampler :: 0",
		"D3D12_CS_VIEW_output_image :: 0",
		"D3D12_CS_VIEW_output_items :: 1",
		"VK_CS_UB_FrameUniforms :: 0",
		"VK_CS_VIEW_input_texture :: 1",
		"VK_CS_SMP_input_sampler :: 2",
		"VK_CS_VIEW_output_image :: 3",
		"VK_CS_VIEW_output_items :: 4",
		"UB_FrameUniforms :: 0",
		"VIEW_input_texture :: 0",
		"VIEW_output_image :: 1",
		"VIEW_output_items :: 2",
		"SMP_input_sampler :: 0",
		"VIEW_KIND_input_texture :: gfx.View_Kind.Sampled",
		"VIEW_ACCESS_input_texture :: gfx.Shader_Resource_Access.Read",
		"VIEW_KIND_output_image :: gfx.View_Kind.Storage_Image",
		"VIEW_ACCESS_output_image :: gfx.Shader_Resource_Access.Read_Write",
		"VIEW_FORMAT_output_image :: gfx.Pixel_Format.RGBA32F",
		"VIEW_KIND_output_items :: gfx.View_Kind.Storage_Buffer",
		"VIEW_ACCESS_output_items :: gfx.Shader_Resource_Access.Read_Write",
		"VIEW_STRIDE_output_items :: 20",
		"Binding_Uniform_Block_Desc :: struct",
		"Binding_Resource_View_Desc :: struct",
		"uniform_block: Binding_Uniform_Block_Desc",
		"resource_view: Binding_Resource_View_Desc",
		"group: u32,",
		"uniform_block = {",
		"resource_view = {",
		"storage_buffer_stride = 20",
		`binding_group_layout_desc :: proc(group: u32 = 0, label: string = "") -> gfx.Binding_Group_Layout_Desc`,
		"pipeline_layout_desc :: proc(",
		"group_0: gfx.Binding_Group_Layout = gfx.Binding_Group_Layout_Invalid",
		"desc.group_layouts[0] = group_0",
		"desc.entries[0] = {",
		"stages = {.Compute}",
		"desc.native_bindings[0] = {",
		"target = gfx.Backend.D3D12",
		"target = gfx.Backend.Vulkan",
		"native_space = 0",
		"set_group_view_input_texture :: proc(group: ^gfx.Binding_Group_Desc, view: gfx.View)",
		"set_group_sampler_input_sampler :: proc(group: ^gfx.Binding_Group_Desc, sampler: gfx.Sampler)",
		"bindings.views[GROUP_0][VIEW_input_texture] = view",
		"bindings.samplers[GROUP_0][SMP_input_sampler] = sampler",
		"native_slot = 4",
	}
	if !assert_contains_all(generated, expected[:], "generated descriptor-table metadata") {
		return false
	}
	if strings.contains(generated, "native_space: u32,\n\tsize: u32,") {
		fmt.eprintln("ape: generated binding records still expose flat uniform-block payload fields")
		return false
	}

	fmt.println("Shaderc descriptor-table slot reflection test passed")
	return true
}

test_shaderc_parameter_block_groups :: proc(ctx: ^Shader_Test_Context) -> bool {
	test_dir := shader_test_dir(ctx, "shaderc_parameter_block_groups")
	source_path := filepath.join({test_dir, "parameter_block_groups.slang"}, context.temp_allocator)
	package_path := filepath.join({test_dir, "parameter_block_groups.ashader"}, context.temp_allocator)
	generated_path := filepath.join({test_dir, "bindings.odin"}, context.temp_allocator)

	source := `struct VS_Input
{
	float3 position : POSITION;
	float2 uv : TEXCOORD;
};

struct VS_Output
{
	float4 position : SV_Position;
	float2 uv : TEXCOORD;
};

cbuffer FrameUniforms
{
	float4 tint;
};

struct Material_Params
{
	Texture2D<float4> diffuse_texture;
	SamplerState diffuse_sampler;
};

struct Shadow_Params
{
	Texture2D<float> shadow_map;
	SamplerState shadow_sampler;
};

ParameterBlock<Material_Params> material;
ParameterBlock<Shadow_Params> shadow_resources;

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	output.uv = input.uv;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	float4 color = material.diffuse_texture.Sample(material.diffuse_sampler, input.uv);
	float shadow = shadow_resources.shadow_map.Sample(shadow_resources.shadow_sampler, input.uv);
	return color * tint * shadow;
}
`
	if strings.contains(source, "register(") || strings.contains(source, "register (") {
		fmt.eprintln("ParameterBlock group test shader must stay register-free")
		return false
	}
	if !write_text_file(source_path, source) {
		return false
	}
	if !run_shaderc_success(ctx, "parameter_block_groups", .Graphics, source_path, package_path, generated_path, test_dir) {
		return false
	}

	generated, generated_ok := read_text_file(generated_path)
	if !generated_ok {
		return false
	}
	defer delete(generated)

	expected := [?]string {
		"GROUP_0 :: 0",
		"GROUP_1 :: 1",
		"GROUP_2 :: 2",
		"UB_FrameUniforms :: 0",
		"VIEW_material_diffuse_texture :: 0",
		"SMP_material_diffuse_sampler :: 0",
		"VIEW_shadow_resources_shadow_map :: 0",
		"SMP_shadow_resources_shadow_sampler :: 0",
		"D3D12_FS_VIEW_material_diffuse_texture :: 0",
		"D3D12_FS_SMP_material_diffuse_sampler :: 0",
		"D3D12_FS_VIEW_material_diffuse_texture_SPACE :: 1",
		"D3D12_FS_SMP_material_diffuse_sampler_SPACE :: 1",
		"D3D12_FS_VIEW_shadow_resources_shadow_map :: 0",
		"D3D12_FS_SMP_shadow_resources_shadow_sampler :: 0",
		"D3D12_FS_VIEW_shadow_resources_shadow_map_SPACE :: 2",
		"D3D12_FS_SMP_shadow_resources_shadow_sampler_SPACE :: 2",
		"VK_FS_VIEW_material_diffuse_texture_SPACE :: 1",
		"VK_FS_SMP_material_diffuse_sampler_SPACE :: 1",
		"VK_FS_VIEW_shadow_resources_shadow_map_SPACE :: 2",
		"VK_FS_SMP_shadow_resources_shadow_sampler_SPACE :: 2",
		`name = cstring("material.diffuse_texture")`,
		"group = 1,",
		`name = cstring("shadow_resources.shadow_map")`,
		"group = 2,",
		`binding_group_layout_desc :: proc(group: u32 = 0, label: string = "") -> gfx.Binding_Group_Layout_Desc`,
		"pipeline_layout_desc :: proc(",
		"group_2: gfx.Binding_Group_Layout = gfx.Binding_Group_Layout_Invalid",
		"desc.group_layouts[2] = group_2",
		"desc.group = group",
		"set_group_view_material_diffuse_texture :: proc(group: ^gfx.Binding_Group_Desc, view: gfx.View)",
		"set_group_sampler_material_diffuse_sampler :: proc(group: ^gfx.Binding_Group_Desc, sampler: gfx.Sampler)",
		"set_group_view_shadow_resources_shadow_map :: proc(group: ^gfx.Binding_Group_Desc, view: gfx.View)",
		"set_group_sampler_shadow_resources_shadow_sampler :: proc(group: ^gfx.Binding_Group_Desc, sampler: gfx.Sampler)",
		"bindings.views[GROUP_1][VIEW_material_diffuse_texture] = view",
		"bindings.views[GROUP_2][VIEW_shadow_resources_shadow_map] = view",
	}
	if !assert_contains_all(generated, expected[:], "generated ParameterBlock metadata") {
		return false
	}

	if !expect_shaderc_failure(ctx, test_dir, "invalid_parameter_block_data", .Graphics, "ParameterBlock ordinary data is not supported yet", INVALID_PARAMETER_BLOCK_DATA) {
		return false
	}
	if !expect_shaderc_failure(ctx, test_dir, "invalid_parameter_block_array", .Graphics, "ParameterBlock arrays are not supported yet", INVALID_PARAMETER_BLOCK_ARRAY) {
		return false
	}
	if !expect_shaderc_failure(ctx, test_dir, "invalid_parameter_block_nested", .Graphics, "nested ParameterBlock fields are not supported yet", INVALID_PARAMETER_BLOCK_NESTED) {
		return false
	}
	if !expect_shaderc_failure(ctx, test_dir, "invalid_parameter_block_constant_buffer", .Graphics, "ParameterBlock constant buffer fields are not supported yet", INVALID_PARAMETER_BLOCK_CONSTANT_BUFFER) {
		return false
	}
	if !expect_shaderc_failure(ctx, test_dir, "invalid_parameter_block_texture_shape", .Graphics, "unsupported resource texture shape", INVALID_PARAMETER_BLOCK_TEXTURE_SHAPE) {
		return false
	}

	fmt.println("Shaderc ParameterBlock group reflection test passed")
	return true
}

test_shaderc_resource_arrays :: proc(ctx: ^Shader_Test_Context) -> bool {
	test_dir := shader_test_dir(ctx, "shaderc_resource_arrays")

	if !expect_shaderc_failure(ctx, test_dir, "global_texture_array", .Graphics, "resource arrays are not supported yet", GLOBAL_TEXTURE_ARRAY) {
		return false
	}
	if !expect_shaderc_failure(ctx, test_dir, "global_sampler_array", .Graphics, "resource arrays are not supported yet", GLOBAL_SAMPLER_ARRAY) {
		return false
	}
	if !expect_shaderc_failure(ctx, test_dir, "global_storage_array", .Compute, "resource arrays are not supported yet", GLOBAL_STORAGE_ARRAY) {
		return false
	}

	fmt.println("Shaderc resource-array rejection test passed")
	return true
}

test_shaderc_invalid_vertex_layout :: proc(ctx: ^Shader_Test_Context) -> bool {
	test_dir := shader_test_dir(ctx, "shaderc_invalid_vertex_layout")
	if !expect_shaderc_failure(ctx, test_dir, "invalid_vertex_layout", .Graphics, "unsupported vertex input type", INVALID_VERTEX_LAYOUT) {
		return false
	}

	fmt.println("Invalid vertex layout shader failed as expected")
	return true
}

test_shaderc_uniform_host_layout :: proc(ctx: ^Shader_Test_Context) -> bool {
	test_dir := shader_test_dir(ctx, "shaderc_uniform_host_layout")

	if !expect_shaderc_failure(ctx, test_dir, "invalid_uniform_array", .Graphics, "uniform arrays are not supported yet", INVALID_UNIFORM_ARRAY) {
		return false
	}
	if !expect_shaderc_failure(ctx, test_dir, "invalid_uniform_nested_struct", .Graphics, "nested uniform structs are not supported yet", INVALID_UNIFORM_NESTED_STRUCT) {
		return false
	}
	if !expect_shaderc_failure(ctx, test_dir, "invalid_uniform_bool", .Graphics, "bool uniform fields are not supported yet", INVALID_UNIFORM_BOOL) {
		return false
	}
	if !expect_shaderc_failure(ctx, test_dir, "invalid_uniform_double", .Graphics, "64-bit uniform fields are not supported yet", INVALID_UNIFORM_DOUBLE) {
		return false
	}
	if !expect_shaderc_failure(ctx, test_dir, "invalid_uniform_host_padding", .Graphics, "unsupported host padding before", INVALID_UNIFORM_HOST_PADDING) {
		return false
	}

	fmt.println("Shaderc uniform host-layout rejection test passed")
	return true
}

test_shaderc_storage_resource_metadata :: proc(ctx: ^Shader_Test_Context) -> bool {
	test_dir := shader_test_dir(ctx, "shaderc_storage_resource_metadata")
	source_path := filepath.join({test_dir, "storage_metadata.slang"}, context.temp_allocator)
	package_path := filepath.join({test_dir, "storage_metadata.ashader"}, context.temp_allocator)
	generated_path := filepath.join({test_dir, "bindings.odin"}, context.temp_allocator)

	if !write_text_file(source_path, STORAGE_METADATA) {
		return false
	}
	if !run_shaderc_success(ctx, "storage_metadata", .Graphics, source_path, package_path, generated_path, test_dir) {
		return false
	}

	generated, generated_ok := read_text_file(generated_path)
	if !generated_ok {
		return false
	}
	defer delete(generated)

	expected := [?]string {
		"VIEW_KIND_output_image :: gfx.View_Kind.Storage_Image",
		"VIEW_ACCESS_output_image :: gfx.Shader_Resource_Access.Read_Write",
		"VIEW_FORMAT_output_image :: gfx.Pixel_Format.RGBA32F",
		"VIEW_KIND_output_buffer :: gfx.View_Kind.Storage_Buffer",
		"VIEW_ACCESS_output_buffer :: gfx.Shader_Resource_Access.Read_Write",
		"VIEW_STRIDE_output_buffer :: 0",
		"Binding_Resource_View_Desc :: struct",
		"resource_view: Binding_Resource_View_Desc",
		"resource_view = {",
		"storage_image_format = gfx.Pixel_Format.RGBA32F",
		"storage_buffer_stride = 0",
		"GROUP_0 :: 0",
		"group: u32,",
		`binding_group_layout_desc :: proc(group: u32 = 0, label: string = "") -> gfx.Binding_Group_Layout_Desc`,
		"pipeline_layout_desc :: proc(",
		"desc.group_layouts[0] = group_0",
		"desc.entries[0] = {",
		"stages = {.Fragment}",
		"desc.native_bindings[0] = {",
		"set_group_view_output_image :: proc(group: ^gfx.Binding_Group_Desc, view: gfx.View)",
		"bindings.views[GROUP_0][VIEW_output_image] = view",
	}
	if !assert_contains_all(generated, expected[:], "generated storage metadata") {
		return false
	}

	structured_source_path := filepath.join({test_dir, "structured_storage_metadata.slang"}, context.temp_allocator)
	structured_package_path := filepath.join({test_dir, "structured_storage_metadata.ashader"}, context.temp_allocator)
	structured_generated_path := filepath.join({test_dir, "structured_bindings.odin"}, context.temp_allocator)
	if !write_text_file(structured_source_path, STRUCTURED_STORAGE_METADATA) {
		return false
	}
	if !run_shaderc_success(ctx, "structured_storage_metadata", .Compute, structured_source_path, structured_package_path, structured_generated_path, test_dir) {
		return false
	}

	structured_generated, structured_ok := read_text_file(structured_generated_path)
	if !structured_ok {
		return false
	}
	defer delete(structured_generated)
	structured_expected := [?]string {
		"VIEW_KIND_output_items :: gfx.View_Kind.Storage_Buffer",
		"VIEW_ACCESS_output_items :: gfx.Shader_Resource_Access.Read_Write",
		"VIEW_STRIDE_output_items :: 20",
		"resource_view = {",
		"storage_buffer_stride = 20",
	}
	if !assert_contains_all(structured_generated, structured_expected[:], "generated structured storage metadata") {
		return false
	}

	if !expect_shaderc_failure(ctx, test_dir, "invalid_storage_image_format", .Compute, "unsupported storage image result type", INVALID_STORAGE_IMAGE_FORMAT) {
		return false
	}

	fmt.println("Shaderc storage resource metadata test passed")
	return true
}

ASHADER_ROUNDTRIP_SOURCE :: `cbuffer FrameUniforms
{
	float4 tint;
};

Texture2D<float4> input_texture;
SamplerState input_sampler;
RWTexture2D<float4> output_image;

[shader("compute")]
[numthreads(8, 4, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	float2 uv = float2(0.5, 0.5);
	float4 color = input_texture.SampleLevel(input_sampler, uv, 0.0) * tint;
	output_image[dispatch_id.xy] = color;
}
`

test_ashader_roundtrip :: proc(ctx: ^Shader_Test_Context) -> bool {
	test_dir := shader_test_dir(ctx, "shaderc_ashader_roundtrip")
	source_path := filepath.join({test_dir, "ashader_roundtrip.slang"}, context.temp_allocator)
	package_path := filepath.join({test_dir, "ashader_roundtrip.ashader"}, context.temp_allocator)
	generated_path := filepath.join({test_dir, "bindings.odin"}, context.temp_allocator)

	if !write_text_file(source_path, ASHADER_ROUNDTRIP_SOURCE) {
		return false
	}
	if !run_shaderc_success(ctx, "ashader_roundtrip", .Compute, source_path, package_path, generated_path, test_dir) {
		return false
	}

	tool_dir := repo_path(ctx.root, "build/tools")
	if !ensure_directory(tool_dir) {
		return false
	}
	checker_path := filepath.join({tool_dir, fmt.tprintf("ape_ashader_roundtrip_test%s", EXE_SUFFIX)}, context.temp_allocator)
	build_command := [?]string {
		"odin",
		"build",
		repo_path(ctx.root, "tools/ape_ashader_roundtrip_test"),
		fmt.tprintf("-collection:ape=%s", ctx.root),
		fmt.tprintf("-out:%s", checker_path),
	}
	if !run_command("build ape_ashader_roundtrip_test", build_command[:], ctx.root) {
		return false
	}

	check_command := [?]string {checker_path, package_path}
	if !run_command("ashader round-trip checker", check_command[:], ctx.root) {
		return false
	}

	fmt.println("Shaderc .ashader round-trip test passed")
	return true
}

shader_test_dir :: proc(ctx: ^Shader_Test_Context, name: string) -> string {
	dir := filepath.join({ctx.base_dir, name}, context.temp_allocator)
	_ = ensure_directory(dir)
	return dir
}

run_shaderc_success :: proc(
	ctx: ^Shader_Test_Context,
	name: string,
	kind: Shader_Kind,
	source_path: string,
	package_path: string,
	generated_path: string,
	build_dir: string,
) -> bool {
	command := [?]string {
		ctx.shaderc_path,
		"-shader-name",
		name,
		"-kind",
		shader_kind_arg(kind),
		"-source",
		source_path,
		"-build-dir",
		build_dir,
		"-package",
		package_path,
		"-generated",
		generated_path,
	}
	return run_command(fmt.tprintf("shaderc %s", name), command[:], ctx.root)
}

expect_shaderc_failure :: proc(ctx: ^Shader_Test_Context, test_dir: string, name: string, kind: Shader_Kind, expected: string, source: string) -> bool {
	source_path := filepath.join({test_dir, fmt.tprintf("%s.slang", name)}, context.temp_allocator)
	package_path := filepath.join({test_dir, fmt.tprintf("%s.ashader", name)}, context.temp_allocator)
	generated_path := filepath.join({test_dir, fmt.tprintf("%s_bindings.odin", name)}, context.temp_allocator)
	if !remove_shaderc_failure_outputs(test_dir, name, kind, package_path, generated_path) {
		return false
	}
	if !write_text_file(source_path, source) {
		return false
	}

	command := [?]string {
		ctx.shaderc_path,
		"-shader-name",
		name,
		"-kind",
		shader_kind_arg(kind),
		"-source",
		source_path,
		"-build-dir",
		test_dir,
		"-package",
		package_path,
		"-generated",
		generated_path,
	}

	process_desc := os2.Process_Desc {
		working_dir = ctx.root,
		command = command[:],
	}
	state, stdout, stderr, err := os2.process_exec(process_desc, context.allocator)
	defer if stdout != nil {
		delete(stdout)
	}
	defer if stderr != nil {
		delete(stderr)
	}

	if err != nil {
		fmt.eprintln("ape: failed to run shaderc failure case ", name, ": ", err)
		return false
	}
	if state.exited && state.exit_code == 0 {
		fmt.eprintln("ape: shaderc unexpectedly accepted ", name)
		return false
	}

	stdout_text := string(stdout)
	stderr_text := string(stderr)
	if !strings.contains(stdout_text, expected) && !strings.contains(stderr_text, expected) {
		fmt.print(stdout_text)
		fmt.eprint(stderr_text)
		fmt.eprintln("ape: shaderc failed ", name, " for the wrong reason; expected: ", expected)
		return false
	}
	if !assert_shaderc_failure_outputs_absent(test_dir, name, kind, package_path, generated_path) {
		return false
	}

	return true
}

remove_shaderc_failure_outputs :: proc(test_dir: string, name: string, kind: Shader_Kind, package_path: string, generated_path: string) -> bool {
	if !remove_file_if_exists(package_path) || !remove_file_if_exists(generated_path) {
		return false
	}

	switch kind {
	case .Compute:
		if !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.cs.dxil", name)}, context.temp_allocator)) ||
		   !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.cs.dxil.json", name)}, context.temp_allocator)) ||
		   !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.cs.spv", name)}, context.temp_allocator)) ||
		   !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.cs.spv.json", name)}, context.temp_allocator)) {
			return false
		}
	case .Graphics:
		if !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.vs.dxil", name)}, context.temp_allocator)) ||
		   !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.vs.dxil.json", name)}, context.temp_allocator)) ||
		   !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.fs.dxil", name)}, context.temp_allocator)) ||
		   !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.fs.dxil.json", name)}, context.temp_allocator)) ||
		   !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.vs.spv", name)}, context.temp_allocator)) ||
		   !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.vs.spv.json", name)}, context.temp_allocator)) ||
		   !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.fs.spv", name)}, context.temp_allocator)) ||
		   !remove_file_if_exists(filepath.join({test_dir, fmt.tprintf("%s.fs.spv.json", name)}, context.temp_allocator)) {
			return false
		}
	}

	return true
}

remove_file_if_exists :: proc(path: string) -> bool {
	if path == "" || !os.exists(path) {
		return true
	}
	err := os.remove(path)
	if err != nil && os.exists(path) {
		fmt.eprintln("ape: failed to remove stale shaderc failure output: ", path)
		return false
	}
	return true
}

assert_shaderc_failure_outputs_absent :: proc(test_dir: string, name: string, kind: Shader_Kind, package_path: string, generated_path: string) -> bool {
	if !assert_file_absent(package_path, "package") || !assert_file_absent(generated_path, "generated bindings") {
		return false
	}

	switch kind {
	case .Compute:
		if !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.cs.dxil", name)}, context.temp_allocator), "D3D12 compute bytecode") ||
		   !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.cs.dxil.json", name)}, context.temp_allocator), "D3D12 compute reflection") ||
		   !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.cs.spv", name)}, context.temp_allocator), "Vulkan compute bytecode") ||
		   !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.cs.spv.json", name)}, context.temp_allocator), "Vulkan compute reflection") {
			return false
		}
	case .Graphics:
		if !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.vs.dxil", name)}, context.temp_allocator), "D3D12 vertex bytecode") ||
		   !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.vs.dxil.json", name)}, context.temp_allocator), "D3D12 vertex reflection") ||
		   !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.fs.dxil", name)}, context.temp_allocator), "D3D12 fragment bytecode") ||
		   !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.fs.dxil.json", name)}, context.temp_allocator), "D3D12 fragment reflection") ||
		   !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.vs.spv", name)}, context.temp_allocator), "Vulkan vertex bytecode") ||
		   !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.vs.spv.json", name)}, context.temp_allocator), "Vulkan vertex reflection") ||
		   !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.fs.spv", name)}, context.temp_allocator), "Vulkan fragment bytecode") ||
		   !assert_file_absent(filepath.join({test_dir, fmt.tprintf("%s.fs.spv.json", name)}, context.temp_allocator), "Vulkan fragment reflection") {
			return false
		}
	}

	return true
}

assert_file_absent :: proc(path: string, label: string) -> bool {
	if !os.exists(path) {
		return true
	}
	fmt.eprintln("ape: shaderc failure wrote ", label, " before rejecting the shader: ", path)
	return false
}

assert_contains_all :: proc(text: string, snippets: []string, label: string) -> bool {
	for snippet in snippets {
		if !strings.contains(text, snippet) {
			fmt.eprintln("ape: missing ", label, ": ", snippet)
			return false
		}
	}
	return true
}

write_text_file :: proc(path: string, text: string) -> bool {
	dir, _ := filepath.split(path)
	if dir != "" && !ensure_directory(dir) {
		return false
	}
	if !os.write_entire_file(path, transmute([]byte)text) {
		fmt.eprintln("ape: failed to write file: ", path)
		return false
	}
	return true
}

read_text_file :: proc(path: string) -> (string, bool) {
	bytes, ok := os.read_entire_file(path)
	if !ok {
		fmt.eprintln("ape: failed to read file: ", path)
		return "", false
	}
	return string(bytes), true
}

INVALID_PARAMETER_BLOCK_DATA :: `struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

struct Bad_Params
{
	float4 solid_color;
};

ParameterBlock<Bad_Params> bad_data;

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return bad_data.solid_color;
}
`

INVALID_PARAMETER_BLOCK_ARRAY :: `struct VS_Input
{
	float3 position : POSITION;
	float2 uv : TEXCOORD;
};

struct VS_Output
{
	float4 position : SV_Position;
	float2 uv : TEXCOORD;
};

struct Bad_Params
{
	Texture2D<float4> textures[2];
	SamplerState sampler;
};

ParameterBlock<Bad_Params> bad_array;

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	output.uv = input.uv;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return bad_array.textures[0].Sample(bad_array.sampler, input.uv);
}
`

INVALID_PARAMETER_BLOCK_NESTED :: `struct VS_Input
{
	float3 position : POSITION;
	float2 uv : TEXCOORD;
};

struct VS_Output
{
	float4 position : SV_Position;
	float2 uv : TEXCOORD;
};

struct Inner_Params
{
	Texture2D<float4> texture;
	SamplerState sampler;
};

struct Outer_Params
{
	ParameterBlock<Inner_Params> inner;
};

ParameterBlock<Outer_Params> bad_nested;

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	output.uv = input.uv;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return bad_nested.inner.texture.Sample(bad_nested.inner.sampler, input.uv);
}
`

INVALID_PARAMETER_BLOCK_CONSTANT_BUFFER :: `struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

struct Data
{
	float4 tint;
};

struct Bad_Params
{
	ConstantBuffer<Data> data;
};

ParameterBlock<Bad_Params> bad_constant_buffer;

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return bad_constant_buffer.data.tint;
}
`

INVALID_PARAMETER_BLOCK_TEXTURE_SHAPE :: `struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

struct Bad_Params
{
	TextureCube<float4> cube_texture;
	SamplerState sampler;
};

ParameterBlock<Bad_Params> bad_texture_shape;

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return bad_texture_shape.cube_texture.Sample(bad_texture_shape.sampler, float3(1.0, 0.0, 0.0));
}
`

GLOBAL_TEXTURE_ARRAY :: `struct VS_Input
{
	float3 position : POSITION;
	float2 uv : TEXCOORD;
};

struct VS_Output
{
	float4 position : SV_Position;
	float2 uv : TEXCOORD;
};

Texture2D<float4> textures[2];
SamplerState sampler;

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	output.uv = input.uv;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return textures[0].Sample(sampler, input.uv);
}
`

GLOBAL_SAMPLER_ARRAY :: `struct VS_Input
{
	float3 position : POSITION;
	float2 uv : TEXCOORD;
};

struct VS_Output
{
	float4 position : SV_Position;
	float2 uv : TEXCOORD;
};

Texture2D<float4> texture;
SamplerState samplers[2];

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	output.uv = input.uv;
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return texture.Sample(samplers[0], input.uv);
}
`

GLOBAL_STORAGE_ARRAY :: `struct Item
{
	float4 value;
	uint id;
};

RWStructuredBuffer<Item> output_items[2];

[shader("compute")]
[numthreads(8, 4, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	Item item;
	item.value = float4(1.0, 0.0, 0.0, 1.0);
	item.id = dispatch_id.x;
	output_items[0][dispatch_id.x] = item;
}
`

INVALID_VERTEX_LAYOUT :: `struct VS_Input
{
	uint id : COLOR0;
};

struct VS_Output
{
	float4 position : SV_Position;
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(float(input.id), 0.0, 0.0, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return float4(1.0, 0.0, 1.0, 1.0);
}
`

INVALID_UNIFORM_ARRAY :: `struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

cbuffer FrameUniforms
{
	float4 colors[2];
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return colors[0];
}
`

INVALID_UNIFORM_NESTED_STRUCT :: `struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

struct Color_Data
{
	float4 color;
};

cbuffer FrameUniforms
{
	Color_Data data;
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return data.color;
}
`

INVALID_UNIFORM_BOOL :: `struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

cbuffer FrameUniforms
{
	bool enabled;
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return enabled ? float4(1.0, 0.0, 0.0, 1.0) : float4(0.0, 0.0, 1.0, 1.0);
}
`

INVALID_UNIFORM_DOUBLE :: `struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

cbuffer FrameUniforms
{
	double intensity;
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return float4((float)intensity, 0.0, 0.0, 1.0);
}
`

INVALID_UNIFORM_HOST_PADDING :: `struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

cbuffer FrameUniforms
{
	float2 offset;
	float3 color;
};

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position.xy + offset, input.position.z, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	return float4(color, 1.0);
}
`

STORAGE_METADATA :: `struct VS_Input
{
	float3 position : POSITION;
};

struct VS_Output
{
	float4 position : SV_Position;
};

RWTexture2D<float4> output_image : register(u1);
RWByteAddressBuffer output_buffer : register(u2);

[shader("vertex")]
VS_Output vs_main(VS_Input input)
{
	VS_Output output;
	output.position = float4(input.position, 1.0);
	return output;
}

[shader("fragment")]
float4 fs_main(VS_Output input) : SV_Target
{
	output_image[uint2(0, 0)] = float4(1.0, 0.0, 0.0, 1.0);
	output_buffer.Store(0, 7);
	return float4(0.0, 0.0, 0.0, 1.0);
}
`

STRUCTURED_STORAGE_METADATA :: `struct Item
{
	float4 value;
	uint id;
};

RWStructuredBuffer<Item> output_items : register(u0);

[shader("compute")]
[numthreads(1, 1, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	Item item;
	item.value = float4(1.0, 0.0, 0.0, 1.0);
	item.id = 7;
	output_items[0] = item;
}
`

INVALID_STORAGE_IMAGE_FORMAT :: `RWTexture2D<float2> bad_output : register(u0);

[shader("compute")]
[numthreads(1, 1, 1)]
void cs_main(uint3 dispatch_id : SV_DispatchThreadID)
{
	bad_output[dispatch_id.xy] = float2(1.0, 0.0);
}
`
