package ape_sample

import "core:fmt"
import "core:os"
import os2 "core:os/os2"
import "core:time"
import gfx "ape:gfx"
import shader_assets "ape:shader"

SHADER_RELOAD_DEFAULT_DEBOUNCE :: 250 * time.Millisecond

Shader_Reload_Status :: enum {
	None,
	Pending,
	Recompiled,
	Failed,
}

Shader_Reload_Desc :: struct {
	shader_name: string,
	source_path: string,
	package_path: string,
	compile_script_path: string,
	working_dir: string,
	debounce: time.Duration,
}

Shader_Reload_Result :: struct {
	status: Shader_Reload_Status,
}

Shader_Program_Desc :: struct {
	package_path: string,
	shader_label: string,
	pipeline_desc: gfx.Pipeline_Desc,
	binding_group_layout_desc: proc(group: u32, label: string) -> gfx.Binding_Group_Layout_Desc,
	target: shader_assets.Backend_Target,
}

Shader_Program :: struct {
	shader_package: shader_assets.Package,
	shader: gfx.Shader,
	pipeline: gfx.Pipeline,
	pipeline_layout: gfx.Pipeline_Layout,
	binding_group_layouts: [gfx.MAX_BINDING_GROUPS]gfx.Binding_Group_Layout,
}

Reloadable_Shader_Program :: struct {
	desc: Shader_Program_Desc,
	program: Shader_Program,
	reloader: Shader_Reloader,
	reload_active: bool,
}

Shader_Reloader :: struct {
	desc: Shader_Reload_Desc,
	initialized: bool,
	last_source_time_ns: i64,
	pending: bool,
	pending_source_time_ns: i64,
	pending_since: time.Time,
	last_error: string,
	last_error_storage: [2048]u8,
}

reloadable_shader_program_init :: proc(
	ctx: ^gfx.Context,
	reloadable: ^Reloadable_Shader_Program,
	program_desc: Shader_Program_Desc,
	reload_desc: Shader_Reload_Desc,
) -> bool {
	if reloadable == nil {
		return false
	}

	reloadable^ = {}
	reloadable.desc = normalize_shader_program_desc(program_desc)

	program, program_ok := shader_program_load(ctx, reloadable.desc)
	if !program_ok {
		return false
	}
	reloadable.program = program

	reloadable.reload_active = shader_reload_init(&reloadable.reloader, reload_desc)
	if !reloadable.reload_active {
		fmt.eprintln("shader hot reload disabled: ", shader_reload_last_error(&reloadable.reloader))
	}

	return true
}

reloadable_shader_program_destroy :: proc(ctx: ^gfx.Context, reloadable: ^Reloadable_Shader_Program) {
	if reloadable == nil {
		return
	}

	shader_program_destroy(ctx, &reloadable.program)
	reloadable^ = {}
}

reloadable_shader_program_pipeline :: proc(reloadable: ^Reloadable_Shader_Program) -> gfx.Pipeline {
	if reloadable == nil {
		return gfx.Pipeline_Invalid
	}

	return reloadable.program.pipeline
}

reloadable_shader_program_binding_group_layout :: proc(reloadable: ^Reloadable_Shader_Program, group: u32) -> gfx.Binding_Group_Layout {
	if reloadable == nil || group >= gfx.MAX_BINDING_GROUPS {
		return gfx.Binding_Group_Layout_Invalid
	}

	return reloadable.program.binding_group_layouts[group]
}

shader_program_binding_group_layout :: proc(program: ^Shader_Program, group: u32) -> gfx.Binding_Group_Layout {
	if program == nil || group >= gfx.MAX_BINDING_GROUPS {
		return gfx.Binding_Group_Layout_Invalid
	}

	return program.binding_group_layouts[group]
}

reloadable_shader_program_poll :: proc(ctx: ^gfx.Context, reloadable: ^Reloadable_Shader_Program) -> Shader_Reload_Status {
	if reloadable == nil || !reloadable.reload_active {
		return .None
	}

	result := shader_reload_poll(&reloadable.reloader)
	switch result.status {
	case .Recompiled:
		if shader_program_reload(ctx, &reloadable.program, reloadable.desc) {
			fmt.println("shader hot reload applied: ", reloadable.reloader.desc.shader_name)
			return .Recompiled
		}
		fmt.eprintln("shader hot reload: keeping previous pipeline for ", reloadable.reloader.desc.shader_name)
		return .Failed
	case .Failed:
		fmt.eprintln(shader_reload_last_error(&reloadable.reloader))
		return .Failed
	case .None, .Pending:
		return result.status
	}

	return .None
}

shader_program_load :: proc(ctx: ^gfx.Context, desc: Shader_Program_Desc) -> (Shader_Program, bool) {
	desc := normalize_shader_program_desc(desc)

	if desc.package_path == "" {
		fmt.eprintln("shader program load failed: package_path is required")
		return {}, false
	}

	shader_package, package_ok := shader_assets.load(desc.package_path)
	if !package_ok {
		fmt.eprintln("failed to read ", desc.package_path)
		return {}, false
	}

	pipeline_layout, binding_group_layouts, layouts_ok := shader_program_create_pipeline_layout(ctx, desc)
	if !layouts_ok {
		shader_assets.unload(&shader_package)
		return {}, false
	}

	return shader_program_load_with_layouts(ctx, desc, shader_package, pipeline_layout, binding_group_layouts, true)
}

@(private)
shader_program_load_with_layouts :: proc(
	ctx: ^gfx.Context,
	desc: Shader_Program_Desc,
	package_value: shader_assets.Package,
	pipeline_layout: gfx.Pipeline_Layout,
	binding_group_layouts: [gfx.MAX_BINDING_GROUPS]gfx.Binding_Group_Layout,
	destroy_layouts_on_failure: bool,
) -> (Shader_Program, bool) {
	shader_package := package_value
	shader_desc, shader_desc_ok := shader_assets.shader_desc(&shader_package, desc.target, desc.shader_label)
	if !shader_desc_ok {
		fmt.eprintln("failed to build shader desc from ", desc.package_path)
		if destroy_layouts_on_failure {
			shader_program_destroy_layouts(ctx, pipeline_layout, binding_group_layouts)
		}
		shader_assets.unload(&shader_package)
		return {}, false
	}

	shader, shader_ok := gfx.create_shader(ctx, shader_desc)
	if !shader_ok {
		fmt.eprintln("shader creation failed: ", gfx.last_error(ctx))
		if destroy_layouts_on_failure {
			shader_program_destroy_layouts(ctx, pipeline_layout, binding_group_layouts)
		}
		shader_assets.unload(&shader_package)
		return {}, false
	}

	pipeline_desc := desc.pipeline_desc
	pipeline_desc.shader = shader
	pipeline_desc.pipeline_layout = pipeline_layout
	pipeline, pipeline_ok := gfx.create_pipeline(ctx, pipeline_desc)
	if !pipeline_ok {
		fmt.eprintln("pipeline creation failed: ", gfx.last_error(ctx))
		gfx.destroy(ctx, shader)
		if destroy_layouts_on_failure {
			shader_program_destroy_layouts(ctx, pipeline_layout, binding_group_layouts)
		}
		shader_assets.unload(&shader_package)
		return {}, false
	}

	return {
		shader_package = shader_package,
		shader = shader,
		pipeline = pipeline,
		pipeline_layout = pipeline_layout,
		binding_group_layouts = binding_group_layouts,
	}, true
}

shader_program_reload :: proc(ctx: ^gfx.Context, program: ^Shader_Program, desc: Shader_Program_Desc) -> bool {
	normalized_desc := normalize_shader_program_desc(desc)
	shader_package, package_ok := shader_assets.load(normalized_desc.package_path)
	if !package_ok {
		fmt.eprintln("failed to read ", normalized_desc.package_path)
		return false
	}

	next_program, ok := shader_program_load_with_layouts(ctx, normalized_desc, shader_package, program.pipeline_layout, program.binding_group_layouts, false)
	if !ok {
		shader_assets.unload(&shader_package)
		return false
	}

	old_program := program^
	program^ = next_program
	shader_program_destroy_pipeline_and_shader(ctx, &old_program)
	return true
}

shader_program_destroy :: proc(ctx: ^gfx.Context, program: ^Shader_Program) {
	if program == nil {
		return
	}

	if gfx.pipeline_valid(program.pipeline) {
		gfx.destroy(ctx, program.pipeline)
	}
	if gfx.shader_valid(program.shader) {
		gfx.destroy(ctx, program.shader)
	}
	shader_program_destroy_layouts(ctx, program.pipeline_layout, program.binding_group_layouts)
	shader_assets.unload(&program.shader_package)
	program^ = {}
}

@(private)
shader_program_destroy_pipeline_and_shader :: proc(ctx: ^gfx.Context, program: ^Shader_Program) {
	if program == nil {
		return
	}

	if gfx.pipeline_valid(program.pipeline) {
		gfx.destroy(ctx, program.pipeline)
	}
	if gfx.shader_valid(program.shader) {
		gfx.destroy(ctx, program.shader)
	}
	shader_assets.unload(&program.shader_package)
	program.pipeline = gfx.Pipeline_Invalid
	program.shader = gfx.Shader_Invalid
	program.shader_package = {}
}

@(private)
shader_program_create_pipeline_layout :: proc(
	ctx: ^gfx.Context,
	desc: Shader_Program_Desc,
) -> (gfx.Pipeline_Layout, [gfx.MAX_BINDING_GROUPS]gfx.Binding_Group_Layout, bool) {
	group_layouts: [gfx.MAX_BINDING_GROUPS]gfx.Binding_Group_Layout
	pipeline_layout_desc: gfx.Pipeline_Layout_Desc
	pipeline_layout_desc.label = desc.pipeline_desc.label
	has_group_layout := false

	if desc.binding_group_layout_desc == nil {
		return gfx.Pipeline_Layout_Invalid, group_layouts, true
	}

	for group in 0..<gfx.MAX_BINDING_GROUPS {
		group_desc := desc.binding_group_layout_desc(u32(group), desc.pipeline_desc.label)
		if !shader_program_binding_group_layout_desc_active(group_desc) {
			continue
		}

		group_layout, group_layout_ok := gfx.create_binding_group_layout(ctx, group_desc)
		if !group_layout_ok {
			fmt.eprintln("binding group layout creation failed: ", gfx.last_error(ctx))
			shader_program_destroy_layouts(ctx, gfx.Pipeline_Layout_Invalid, group_layouts)
			return gfx.Pipeline_Layout_Invalid, {}, false
		}

		group_layouts[group] = group_layout
		pipeline_layout_desc.group_layouts[group] = group_layout
		has_group_layout = true
	}

	if !has_group_layout {
		return gfx.Pipeline_Layout_Invalid, group_layouts, true
	}

	pipeline_layout, pipeline_layout_ok := gfx.create_pipeline_layout(ctx, pipeline_layout_desc)
	if !pipeline_layout_ok {
		fmt.eprintln("pipeline layout creation failed: ", gfx.last_error(ctx))
		shader_program_destroy_layouts(ctx, gfx.Pipeline_Layout_Invalid, group_layouts)
		return gfx.Pipeline_Layout_Invalid, {}, false
	}

	return pipeline_layout, group_layouts, true
}

@(private)
shader_program_destroy_layouts :: proc(
	ctx: ^gfx.Context,
	pipeline_layout: gfx.Pipeline_Layout,
	group_layouts: [gfx.MAX_BINDING_GROUPS]gfx.Binding_Group_Layout,
) {
	if gfx.pipeline_layout_valid(pipeline_layout) {
		gfx.destroy(ctx, pipeline_layout)
	}
	for group_layout in group_layouts {
		if gfx.binding_group_layout_valid(group_layout) {
			gfx.destroy(ctx, group_layout)
		}
	}
}

@(private)
shader_program_binding_group_layout_desc_active :: proc(desc: gfx.Binding_Group_Layout_Desc) -> bool {
	for entry in desc.entries {
		if entry.active {
			return true
		}
	}
	for native in desc.native_bindings {
		if native.active {
			return true
		}
	}

	return false
}

shader_reload_init :: proc(reloader: ^Shader_Reloader, desc: Shader_Reload_Desc) -> bool {
	if reloader == nil {
		return false
	}

	reloader^ = {}
	reloader.desc = normalize_shader_reload_desc(desc)

	if reloader.desc.shader_name == "" {
		set_shader_reload_error(reloader, "shader hot reload: shader_name is required")
		return false
	}
	if reloader.desc.source_path == "" {
		set_shader_reload_error(reloader, "shader hot reload: source_path is required")
		return false
	}
	if reloader.desc.package_path == "" {
		set_shader_reload_error(reloader, "shader hot reload: package_path is required")
		return false
	}

	source_time_ns, source_ok := file_modification_time_ns(reloader.desc.source_path)
	if !source_ok {
		set_shader_reload_errorf(reloader, "shader hot reload: could not stat source %s", reloader.desc.source_path)
		return false
	}

	reloader.last_source_time_ns = source_time_ns
	reloader.initialized = true
	return true
}

shader_reload_enabled :: proc(reloader: ^Shader_Reloader) -> bool {
	return reloader != nil && reloader.initialized
}

shader_reload_last_error :: proc(reloader: ^Shader_Reloader) -> string {
	if reloader == nil {
		return "shader hot reload: nil reloader"
	}
	return reloader.last_error
}

shader_reload_poll :: proc(reloader: ^Shader_Reloader) -> Shader_Reload_Result {
	if reloader == nil || !reloader.initialized {
		return {status = .Failed}
	}

	source_time_ns, source_ok := file_modification_time_ns(reloader.desc.source_path)
	if !source_ok {
		set_shader_reload_errorf(reloader, "shader hot reload: could not stat source %s", reloader.desc.source_path)
		return {status = .Failed}
	}

	if source_time_ns == reloader.last_source_time_ns {
		reloader.pending = false
		return {status = .None}
	}

	if !reloader.pending || source_time_ns != reloader.pending_source_time_ns {
		reloader.pending = true
		reloader.pending_source_time_ns = source_time_ns
		reloader.pending_since = time.now()
		return {status = .Pending}
	}

	if time.since(reloader.pending_since) < reloader.desc.debounce {
		return {status = .Pending}
	}

	reloader.pending = false
	reloader.last_source_time_ns = source_time_ns

	if !shader_reload_compile(reloader) {
		return {status = .Failed}
	}

	_, package_ok := file_modification_time_ns(reloader.desc.package_path)
	if !package_ok {
		set_shader_reload_errorf(reloader, "shader hot reload: compile succeeded but package is missing: %s", reloader.desc.package_path)
		return {status = .Failed}
	}

	reloader.last_error = ""
	return {status = .Recompiled}
}

normalize_shader_reload_desc :: proc(desc: Shader_Reload_Desc) -> Shader_Reload_Desc {
	result := desc
	if result.compile_script_path == "" {
		result.compile_script_path = "tools/compile_shaders.ps1"
	}
	if result.working_dir == "" {
		result.working_dir = "."
	}
	if result.debounce == 0 {
		result.debounce = SHADER_RELOAD_DEFAULT_DEBOUNCE
	}
	return result
}

normalize_shader_program_desc :: proc(desc: Shader_Program_Desc) -> Shader_Program_Desc {
	return desc
}

shader_reload_compile :: proc(reloader: ^Shader_Reloader) -> bool {
	command := [?]string {
		"powershell.exe",
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		reloader.desc.compile_script_path,
		"-ShaderName",
		reloader.desc.shader_name,
	}

	process_desc := os2.Process_Desc {
		working_dir = reloader.desc.working_dir,
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
		set_shader_reload_errorf(reloader, "shader hot reload: failed to run compiler for %s: %v", reloader.desc.shader_name, err)
		return false
	}

	if !state.exited || state.exit_code != 0 {
		output := string(stderr)
		if len(output) == 0 {
			output = string(stdout)
		}
		set_shader_reload_errorf(
			reloader,
			"shader hot reload: compiler failed for %s with exit code %d\n%s",
			reloader.desc.shader_name,
			state.exit_code,
			output,
		)
		return false
	}

	return true
}

file_modification_time_ns :: proc(path: string) -> (i64, bool) {
	info, err := os.stat(path)
	if err != nil {
		return 0, false
	}
	defer os.file_info_delete(info)

	return time.to_unix_nanoseconds(info.modification_time), true
}

set_shader_reload_error :: proc(reloader: ^Shader_Reloader, message: string) {
	if reloader == nil {
		return
	}
	reloader.last_error = message
}

set_shader_reload_errorf :: proc(reloader: ^Shader_Reloader, format: string, args: ..any) {
	if reloader == nil {
		return
	}
	reloader.last_error = fmt.bprintf(reloader.last_error_storage[:], format, ..args)
}
