package main

import "core:fmt"
import "core:path/filepath"
import "core:strconv"

SAMPLE_NAMES :: [?]string {
	"clear",
	"triangle_minimal",
	"triangle",
	"cube",
	"textured_quad",
	"textured_cube",
	"dynamic_texture",
	"render_to_texture",
	"depth_render_to_texture",
	"mrt",
	"msaa",
	"gfx_lab",
	"improved_shadows",
	"transient_uniforms",
	"triangle_indirect",
	"dispatch_indirect",
	"gpu_driven_indirect",
}

Sample_Options :: struct {
	root_path: string,
	name: string,
	all: bool,
	auto_exit_frames: int,
	skip_shader_compile: bool,
}

parse_sample_options :: proc(args: []string) -> (Sample_Options, bool) {
	options := Sample_Options {
		root_path = ".",
		name = "all",
		all = true,
	}

	name_set := false
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		switch arg {
		case "all":
			if name_set {
				return {}, false
			}
			options.name = "all"
			options.all = true
			name_set = true
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
		case:
			if name_set || len(arg) == 0 || arg[0] == '-' {
				return {}, false
			}
			options.name = arg
			options.all = false
			name_set = true
		}
	}

	if !options.all && !sample_known(options.name) {
		fmt.eprintln("ape: unknown sample: ", options.name)
		return {}, false
	}

	return options, true
}

build_samples :: proc(options: Sample_Options) -> bool {
	return sample_command(options, false)
}

run_samples :: proc(options: Sample_Options) -> bool {
	return sample_command(options, true)
}

sample_command :: proc(options: Sample_Options, run: bool) -> bool {
	root, root_ok := filepath.abs(options.root_path, context.temp_allocator)
	if !root_ok {
		fmt.eprintln("ape: failed to resolve repo root: ", options.root_path)
		return false
	}

	build_dir := repo_path(root, "build")
	if !ensure_directory(build_dir) {
		return false
	}

	if run && !options.skip_shader_compile {
		if !compile_shaders({
			root_path = root,
			build_dir = "build/shaders",
			all = true,
		}) {
			return false
		}
	}

	if options.all {
		for name in SAMPLE_NAMES {
			if !sample_one(root, name, run, options.auto_exit_frames) {
				return false
			}
		}
		return true
	}

	return sample_one(root, options.name, run, options.auto_exit_frames)
}

sample_one :: proc(root, name: string, run: bool, auto_exit_frames: int) -> bool {
	sample_dir := repo_path(root, filepath.join({"samples", name}, context.temp_allocator))
	out_path := repo_path(root, filepath.join({"build", fmt.tprintf("%s%s", name, EXE_SUFFIX)}, context.temp_allocator))

	command := make([dynamic]string)
	defer delete(command)

	append(&command, "odin")
	if run {
		append(&command, "run")
	} else {
		append(&command, "build")
	}
	append(&command, sample_dir)
	append(&command, fmt.tprintf("-collection:ape=%s", root))
	append(&command, fmt.tprintf("-out:%s", out_path))
	if auto_exit_frames > 0 {
		append(&command, fmt.tprintf("-define:AUTO_EXIT_FRAMES=%d", auto_exit_frames))
	}

	action := "build"
	if run {
		action = "run"
	}
	return run_command(fmt.tprintf("%s sample %s", action, name), command[:], root)
}

sample_known :: proc(name: string) -> bool {
	for sample in SAMPLE_NAMES {
		if sample == name {
			return true
		}
	}
	return false
}
