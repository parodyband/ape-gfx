package main

import "core:fmt"
import "core:os"
import os2 "core:os/os2"
import "core:path/filepath"

EXE_SUFFIX :: ".exe" when ODIN_OS == .Windows else ""

Shader_Kind :: enum {
	Graphics,
	Compute,
}

Shader_Compile_Options :: struct {
	root_path: string,
	shader_name: string,
	source_path: string,
	build_dir: string,
	kind: Shader_Kind,
	all: bool,
}

main :: proc() {
	if !run(os.args[1:]) {
		os.exit(1)
	}
}

run :: proc(args: []string) -> bool {
	if len(args) == 0 {
		print_usage()
		return false
	}

	if args[0] == "shader" {
		if len(args) >= 2 && args[1] == "compile" {
			options, ok := parse_shader_compile_options(args[2:])
			if !ok {
				print_usage()
				return false
			}
			return compile_shaders(options)
		}
		if len(args) >= 2 && args[1] == "test" {
			options, ok := parse_shader_test_options(args[2:])
			if !ok {
				print_usage()
				return false
			}
			return run_shader_tests(options)
		}
	}

	if args[0] == "compile-shaders" {
		options, ok := parse_shader_compile_options(args[1:])
		if !ok {
			print_usage()
			return false
		}
		return compile_shaders(options)
	}

	if args[0] == "validate" {
		if len(args) >= 2 && args[1] == "core" {
			options, ok := parse_validate_core_options(args[2:])
			if !ok {
				print_usage()
				return false
			}
			return validate_core(options)
		}
		if len(args) >= 2 && args[1] == "full" {
			options, ok := parse_validate_full_options(args[2:])
			if !ok {
				print_usage()
				return false
			}
			return validate_full(options)
		}
	}

	if args[0] == "sample" {
		if len(args) >= 2 && args[1] == "build" {
			options, ok := parse_sample_options(args[2:])
			if !ok {
				print_usage()
				return false
			}
			return build_samples(options)
		}
		if len(args) >= 2 && args[1] == "run" {
			options, ok := parse_sample_options(args[2:])
			if !ok {
				print_usage()
				return false
			}
			return run_samples(options)
		}
	}

	if args[0] == "hygiene" {
		options, ok := parse_hygiene_options(args[1:])
		if !ok {
			print_usage()
			return false
		}
		return run_hygiene(options)
	}

	if args[0] == "docs" {
		if len(args) >= 2 && args[1] == "generate" {
			options, ok := parse_docs_generate_options(args[2:])
			if !ok {
				print_usage()
				return false
			}
			return generate_api_docs(options)
		}
	}

	print_usage()
	return false
}

parse_shader_compile_options :: proc(args: []string) -> (Shader_Compile_Options, bool) {
	options := Shader_Compile_Options {
		root_path = ".",
		shader_name = "triangle",
		build_dir = "build/shaders",
		kind = .Graphics,
	}

	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		switch arg {
		case "-all", "-All":
			options.all = true
		case "-root", "-Root":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.root_path = args[i]
		case "-shader-name", "-ShaderName":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.shader_name = args[i]
		case "-kind", "-Kind":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			switch args[i] {
			case "graphics", "Graphics":
				options.kind = .Graphics
			case "compute", "Compute":
				options.kind = .Compute
			case:
				return {}, false
			}
		case "-source", "-SourcePath":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.source_path = args[i]
		case "-build-dir", "-BuildDir":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.build_dir = args[i]
		case:
			return {}, false
		}
	}

	if options.all && options.source_path != "" {
		return {}, false
	}
	if options.shader_name == "" {
		return {}, false
	}

	return options, true
}

compile_shaders :: proc(options: Shader_Compile_Options) -> bool {
	root, root_ok := filepath.abs(options.root_path, context.temp_allocator)
	if !root_ok {
		fmt.eprintln("ape: failed to resolve repo root: ", options.root_path)
		return false
	}

	build_dir := repo_path(root, options.build_dir)
	if !ensure_directory(build_dir) {
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

	if options.all {
		command := [?]string {
			shaderc_path,
			"-all",
			"-build-dir",
			build_dir,
		}
		if !run_command("compile all shaders", command[:], root) {
			return false
		}
		fmt.printf("Compiled all sample shader outputs and packages to %s\n", build_dir)
		return true
	}

	source_path := options.source_path
	if source_path == "" {
		source_path = filepath.join({"assets/shaders", fmt.tprintf("%s.slang", options.shader_name)}, context.temp_allocator)
	}
	source_path = repo_path(root, source_path)

	package_path := filepath.join({build_dir, fmt.tprintf("%s.ashader", options.shader_name)}, context.temp_allocator)
	generated_path := repo_path(
		root,
		filepath.join({"assets/shaders/generated", options.shader_name, "bindings.odin"}, context.temp_allocator),
	)

	command := [?]string {
		shaderc_path,
		"-shader-name",
		options.shader_name,
		"-kind",
		shader_kind_arg(options.kind),
		"-source",
		source_path,
		"-build-dir",
		build_dir,
		"-package",
		package_path,
		"-generated",
		generated_path,
	}
	if !run_command("compile shader", command[:], root) {
		return false
	}

	fmt.printf("Compiled %s shader outputs and package to %s\n", options.shader_name, build_dir)
	return true
}

build_shaderc :: proc(root: string, out_path: string) -> bool {
	source_path := repo_path(root, "tools/ape_shaderc")
	command := [?]string {
		"odin",
		"build",
		source_path,
		fmt.tprintf("-out:%s", out_path),
	}
	return run_command("build ape_shaderc", command[:], root)
}

run_command :: proc(label: string, command: []string, working_dir: string) -> bool {
	if label != "" {
		fmt.printf("==> %s\n", label)
	}

	process_desc := os2.Process_Desc {
		working_dir = working_dir,
		command = command,
	}

	state, stdout, stderr, err := os2.process_exec(process_desc, context.allocator)
	defer if stdout != nil {
		delete(stdout)
	}
	defer if stderr != nil {
		delete(stderr)
	}

	if len(stdout) > 0 {
		fmt.print(string(stdout))
	}
	if len(stderr) > 0 {
		fmt.eprint(string(stderr))
	}

	if err != nil {
		fmt.eprintln("ape: failed to run command: ", command[0], ": ", err)
		return false
	}
	if !state.exited || state.exit_code != 0 {
		fmt.eprintln("ape: command failed: ", command[0], " exit ", state.exit_code)
		return false
	}

	return true
}

repo_path :: proc(root: string, path: string) -> string {
	if filepath.is_abs(path) {
		return path
	}
	return filepath.join({root, path}, context.temp_allocator)
}

shader_kind_arg :: proc(kind: Shader_Kind) -> string {
	switch kind {
	case .Graphics:
		return "graphics"
	case .Compute:
		return "compute"
	}
	return "graphics"
}

print_usage :: proc() {
	fmt.eprintln("usage: ape shader compile [-all] [-root <repo>] [-shader-name <name>] [-kind graphics|compute] [-source <path>] [-build-dir <dir>]")
	fmt.eprintln("       ape shader test [-all|-name <test>] [-root <repo>]")
	fmt.eprintln("       ape docs generate [-root <repo>] [-out-dir <dir>] [-markdown-dir <dir>]")
	fmt.eprintln("       ape sample build [all|<name>] [-root <repo>] [-auto-exit-frames <n>]")
	fmt.eprintln("       ape sample run [all|<name>] [-root <repo>] [-auto-exit-frames <n>] [-skip-shader-compile]")
	fmt.eprintln("       ape hygiene [-root <repo>]")
	fmt.eprintln("       ape validate core [-root <repo>] [-skip-shader-compile] [-skip-git-diff-check]")
	fmt.eprintln("       ape validate full [-root <repo>] [-auto-exit-frames <n>] [-skip-shader-compile] [-skip-sample-builds] [-skip-git-diff-check]")
	fmt.eprintln("       ape compile-shaders [-all] [-root <repo>] [-shader-name <name>] [-kind graphics|compute] [-source <path>] [-build-dir <dir>]")
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
		fmt.eprintln("ape: failed to create directory: ", normalized)
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
