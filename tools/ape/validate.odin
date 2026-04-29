package main

import "core:fmt"
import os2 "core:os/os2"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"

Validate_Core_Options :: struct {
	root_path: string,
	skip_shader_compile: bool,
	skip_git_diff_check: bool,
}

Validate_Full_Options :: struct {
	root_path: string,
	auto_exit_frames: int,
	skip_shader_compile: bool,
	skip_d3d11_builds: bool,
	skip_d3d11_runs: bool,
	skip_git_diff_check: bool,
}

Hygiene_Options :: struct {
	root_path: string,
}

parse_hygiene_options :: proc(args: []string) -> (Hygiene_Options, bool) {
	options := Hygiene_Options {
		root_path = ".",
	}

	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		switch arg {
		case "-root", "-Root":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.root_path = args[i]
		case:
			return {}, false
		}
	}

	return options, true
}

parse_validate_core_options :: proc(args: []string) -> (Validate_Core_Options, bool) {
	options := Validate_Core_Options {
		root_path = ".",
	}

	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		switch arg {
		case "-root", "-Root":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.root_path = args[i]
		case "-skip-shader-compile", "-SkipShaderCompile":
			options.skip_shader_compile = true
		case "-skip-git-diff-check", "-SkipGitDiffCheck":
			options.skip_git_diff_check = true
		case:
			return {}, false
		}
	}

	return options, true
}

parse_validate_full_options :: proc(args: []string) -> (Validate_Full_Options, bool) {
	options := Validate_Full_Options {
		root_path = ".",
		auto_exit_frames = 5,
	}

	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		switch arg {
		case "-root", "-Root":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.root_path = args[i]
		case "-auto-exit-frames", "-AutoExitFrames":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			value, ok := strconv.parse_int(args[i])
			if !ok || value < 0 {
				return {}, false
			}
			options.auto_exit_frames = value
		case "-skip-shader-compile", "-SkipShaderCompile":
			options.skip_shader_compile = true
		case "-skip-d3d11-builds", "-SkipD3D11Builds":
			options.skip_d3d11_builds = true
		case "-skip-d3d11-runs", "-SkipD3D11Runs":
			options.skip_d3d11_runs = true
		case "-skip-git-diff-check", "-SkipGitDiffCheck":
			options.skip_git_diff_check = true
		case:
			return {}, false
		}
	}

	return options, true
}

run_hygiene :: proc(options: Hygiene_Options) -> bool {
	root, root_ok := filepath.abs(options.root_path, context.temp_allocator)
	if !root_ok {
		fmt.eprintln("ape: failed to resolve repo root: ", options.root_path)
		return false
	}

	if !check_repo_hygiene(root) {
		return false
	}

	fmt.println("repo hygiene passed")
	return true
}

validate_core :: proc(options: Validate_Core_Options) -> bool {
	root, root_ok := filepath.abs(options.root_path, context.temp_allocator)
	if !root_ok {
		fmt.eprintln("ape: failed to resolve repo root: ", options.root_path)
		return false
	}

	started_at := time.now()
	fmt.println("Ape GFX core validation")
	fmt.printf("Root: %s\n", root)
	fmt.println("D3D11 runtime tests: skipped")

	step_started_at := validation_step_start("repo hygiene")
	if !check_repo_hygiene(root) {
		validation_step_fail("repo hygiene")
		return false
	}
	validation_step_pass("repo hygiene", step_started_at)

	if !options.skip_shader_compile {
		step_started_at = validation_step_start("compile sample shaders")
		if !compile_shaders({
			root_path = root,
			build_dir = "build/shaders",
			all = true,
		}) {
			validation_step_fail("compile sample shaders")
			return false
		}
		validation_step_pass("compile sample shaders", step_started_at)
	}

	power_shell_scripts := [?]string {
		"build_smoke.ps1",
		"test_api_docs_public_surface.ps1",
		"test_gfx_public_api_audit.ps1",
		"test_gfx_error_codes.ps1",
		"test_gfx_descriptor_contracts.ps1",
		"test_gfx_image_transfer_contracts.ps1",
		"test_gfx_state_descriptor_contracts.ps1",
		"test_gfx_binding_group_arrays.ps1",
		"test_gfx_range_helpers.ps1",
		"test_gfx_handle_lifecycle.ps1",
	}
	for script in power_shell_scripts {
		step_started_at := validation_step_start(script)
		if !run_repo_script(root, script) {
			validation_step_fail(script)
			return false
		}
		validation_step_pass(script, step_started_at)
	}

	step_started_at = validation_step_start("shaderc reflection tests")
	if !run_shader_tests({
		root_path = root,
		name = "all",
		all = true,
	}) {
		validation_step_fail("shaderc reflection tests")
		return false
	}
	validation_step_pass("shaderc reflection tests", step_started_at)

	step_started_at = validation_step_start("test_shader_hot_reload.ps1")
	if !run_repo_script(root, "test_shader_hot_reload.ps1") {
		validation_step_fail("test_shader_hot_reload.ps1")
		return false
	}
	validation_step_pass("test_shader_hot_reload.ps1", step_started_at)

	if !options.skip_git_diff_check {
		step_started_at = validation_step_start("git diff --check")
		command := [?]string {"git", "diff", "--check"}
		if !run_command("git diff --check", command[:], root) {
			validation_step_fail("git diff --check")
			return false
		}
		validation_step_pass("git diff --check", step_started_at)
	}

	elapsed := time.since(started_at)
	fmt.println()
	fmt.printf("Ape GFX core validation passed (%.1fs)\n", f64(elapsed) / f64(time.Second))
	return true
}

validate_full :: proc(options: Validate_Full_Options) -> bool {
	root, root_ok := filepath.abs(options.root_path, context.temp_allocator)
	if !root_ok {
		fmt.eprintln("ape: failed to resolve repo root: ", options.root_path)
		return false
	}

	started_at := time.now()
	fmt.println("Ape GFX full validation")
	fmt.printf("Root: %s\n", root)
	fmt.printf("AutoExitFrames: %d\n", options.auto_exit_frames)

	step_started_at := validation_step_start("repo hygiene")
	if !check_repo_hygiene(root) {
		validation_step_fail("repo hygiene")
		return false
	}
	validation_step_pass("repo hygiene", step_started_at)

	if !options.skip_shader_compile {
		step_started_at = validation_step_start("compile sample shaders")
		if !compile_shaders({
			root_path = root,
			build_dir = "build/shaders",
			all = true,
		}) {
			validation_step_fail("compile sample shaders")
			return false
		}
		validation_step_pass("compile sample shaders", step_started_at)
	}

	public_scripts := [?]string {
		"build_smoke.ps1",
		"test_api_docs_public_surface.ps1",
		"test_gfx_public_api_audit.ps1",
		"test_gfx_error_codes.ps1",
		"test_gfx_descriptor_contracts.ps1",
		"test_gfx_image_transfer_contracts.ps1",
		"test_gfx_state_descriptor_contracts.ps1",
		"test_gfx_binding_group_arrays.ps1",
		"test_gfx_range_helpers.ps1",
		"test_gfx_handle_lifecycle.ps1",
		"test_d3d11_backend_limits.ps1",
		"test_d3d11_error_codes.ps1",
		"test_d3d11_buffer_transfers.ps1",
		"test_d3d11_compute_pass.ps1",
		"test_d3d11_invalid_pipeline_layout.ps1",
		"test_d3d11_invalid_uniform_size.ps1",
		"test_d3d11_invalid_view_kind.ps1",
		"test_d3d11_resource_hazards.ps1",
		"test_d3d11_storage_views.ps1",
		"test_d3d11_bindless_reject.ps1",
		"test_d3d11_barrier_validation.ps1",
		"test_d3d11_indirect_validation.ps1",
		"test_shader_hot_reload.ps1",
	}
	for script in public_scripts {
		step_started_at := validation_step_start(script)
		if !run_repo_script(root, script) {
			validation_step_fail(script)
			return false
		}
		validation_step_pass(script, step_started_at)
	}

	step_started_at = validation_step_start("shaderc reflection tests")
	if !run_shader_tests({
		root_path = root,
		name = "all",
		all = true,
	}) {
		validation_step_fail("shaderc reflection tests")
		return false
	}
	validation_step_pass("shaderc reflection tests", step_started_at)

	d3d11_build_scripts := [?]string {
		"build_d3d11_clear.ps1",
		"build_d3d11_cube.ps1",
		"build_d3d11_depth_render_to_texture.ps1",
		"build_d3d11_dynamic_texture.ps1",
		"build_d3d11_gfx_lab.ps1",
		"build_d3d11_improved_shadows.ps1",
		"build_d3d11_mrt.ps1",
		"build_d3d11_msaa.ps1",
		"build_d3d11_render_to_texture.ps1",
		"build_d3d11_textured_cube.ps1",
		"build_d3d11_textured_quad.ps1",
		"build_d3d11_transient_uniforms.ps1",
		"build_d3d11_triangle.ps1",
		"build_d3d11_triangle_indirect.ps1",
		"build_d3d11_triangle_minimal.ps1",
		"build_d3d11_dispatch_indirect.ps1",
	}
	if !options.skip_d3d11_builds {
		for script in d3d11_build_scripts {
			step_started_at := validation_step_start(script)
			if !run_repo_script(root, script) {
				validation_step_fail(script)
				return false
			}
			validation_step_pass(script, step_started_at)
		}
	}

	d3d11_run_scripts := [?]string {
		"run_d3d11_clear.ps1",
		"run_d3d11_cube.ps1",
		"run_d3d11_depth_render_to_texture.ps1",
		"run_d3d11_dynamic_texture.ps1",
		"run_d3d11_gfx_lab.ps1",
		"run_d3d11_improved_shadows.ps1",
		"run_d3d11_mrt.ps1",
		"run_d3d11_msaa.ps1",
		"run_d3d11_render_to_texture.ps1",
		"run_d3d11_textured_cube.ps1",
		"run_d3d11_textured_quad.ps1",
		"run_d3d11_transient_uniforms.ps1",
		"run_d3d11_triangle.ps1",
		"run_d3d11_triangle_indirect.ps1",
		"run_d3d11_triangle_minimal.ps1",
		"run_d3d11_dispatch_indirect.ps1",
	}
	if !options.skip_d3d11_runs {
		for script in d3d11_run_scripts {
			step_name := fmt.tprintf("%s -AutoExitFrames %d", script, options.auto_exit_frames)
			step_started_at := validation_step_start(step_name)
			auto_exit_arg := fmt.tprintf("%d", options.auto_exit_frames)
			args := [?]string {"-AutoExitFrames", auto_exit_arg}
			if !run_repo_script(root, script, args[:]) {
				validation_step_fail(step_name)
				return false
			}
			validation_step_pass(step_name, step_started_at)
		}
	}

	if !options.skip_git_diff_check {
		step_started_at = validation_step_start("git diff --check")
		command := [?]string {"git", "diff", "--check"}
		if !run_command("git diff --check", command[:], root) {
			validation_step_fail("git diff --check")
			return false
		}
		validation_step_pass("git diff --check", step_started_at)
	}

	elapsed := time.since(started_at)
	fmt.println()
	fmt.printf("Ape GFX full validation passed (%.1fs)\n", f64(elapsed) / f64(time.Second))
	return true
}

validation_step_start :: proc(name: string) -> time.Time {
	fmt.println()
	fmt.printf("==> %s\n", name)
	return time.now()
}

validation_step_pass :: proc(name: string, started_at: time.Time) {
	elapsed := time.since(started_at)
	fmt.printf("OK  %s (%.1fs)\n", name, f64(elapsed) / f64(time.Second))
}

validation_step_fail :: proc(name: string) {
	fmt.println()
	fmt.eprintln("FAILED  ", name)
}

check_repo_hygiene :: proc(root: string) -> bool {
	command := [?]string {"git", "ls-files"}
	process_desc := os2.Process_Desc {
		working_dir = root,
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
		fmt.eprintln("repo hygiene: failed to run git ls-files: ", err)
		return false
	}
	if !state.exited || state.exit_code != 0 {
		if len(stderr) > 0 {
			fmt.eprint(string(stderr))
		}
		fmt.eprintln("repo hygiene: git ls-files failed with exit ", state.exit_code)
		return false
	}

	violations: [dynamic]string
	defer delete(violations)

	for raw_line in strings.split_lines(string(stdout), context.temp_allocator) {
		path := strings.trim_space(strings.trim_right(raw_line, "\r"))
		if path == "" {
			continue
		}

		normalized, _ := strings.replace_all(path, "\\", "/", context.temp_allocator)
		if repo_hygiene_forbidden_tracked_path(normalized) {
			append(&violations, normalized)
		}
	}

	if len(violations) == 0 {
		return true
	}

	fmt.eprintln("repo hygiene: tracked build artifacts are not allowed:")
	for path in violations {
		fmt.eprintln("  ", path)
	}
	fmt.eprintln("repo hygiene: remove these files from git and keep artifact rules in .gitignore")
	return false
}

repo_hygiene_forbidden_tracked_path :: proc(path: string) -> bool {
	if strings.has_prefix(path, "_scratch/") || strings.has_prefix(path, "build/") {
		return true
	}

	for suffix in REPO_HYGIENE_FORBIDDEN_SUFFIXES {
		if strings.has_suffix(path, suffix) {
			return true
		}
	}

	return false
}

REPO_HYGIENE_FORBIDDEN_SUFFIXES :: [?]string {
	".o",
	".obj",
	".exe",
	".pdb",
	".ilk",
	".lib",
	".dll",
	".so",
	".dylib",
}

run_repo_script :: proc(root: string, script_name: string, arguments: []string = nil) -> bool {
	script_path := repo_path(root, filepath.join({"tools", script_name}, context.temp_allocator))
	command: [dynamic]string
	append(&command, "powershell")
	append(&command, "-ExecutionPolicy")
	append(&command, "Bypass")
	append(&command, "-File")
	append(&command, script_path)
	for arg in arguments {
		append(&command, arg)
	}
	defer delete(command)

	return run_command("", command[:], root)
}
