package shader

import "core:fmt"
import "core:os/os2"
import "core:path/filepath"

// Subprocess_Compiler_Options configures the default Library_Compiler
// implementation that shells out to `ape_shaderc.exe`. Only `executable_path`
// is required; the rest pick up reasonable defaults relative to the source
// file the compiler is invoked for.
//
// This is the default APE-28 source-compile fallback path: when `resolve`
// misses both the in-memory cache and the on-disk `.ashader`, the runtime
// asks `ape_shaderc` to produce one. Production callers can substitute their
// own Library_Compiler if they want to drive Slang in-process.
Subprocess_Compiler_Options :: struct {
	executable_path: string,
	build_dir: string,
	working_dir: string,
}

// install_subprocess_compiler wires the default `ape_shaderc.exe` invoker
// into a Library. The pointer to `options` must outlive the library.
install_subprocess_compiler :: proc(lib: ^Library, options: ^Subprocess_Compiler_Options) {
	if lib == nil || options == nil {
		return
	}
	set_source_compiler(lib, subprocess_compiler_invoke, rawptr(options))
}

@(private)
subprocess_compiler_invoke :: proc(name: string, source_path: string, out_path: string, user: rawptr) -> bool {
	if user == nil || name == "" || source_path == "" {
		return false
	}
	options := cast(^Subprocess_Compiler_Options)user
	if options.executable_path == "" {
		return false
	}

	build_dir := options.build_dir
	if build_dir == "" {
		build_dir = filepath.dir(out_path)
	}

	command := []string {
		options.executable_path,
		fmt.tprintf("-name=%s", name),
		fmt.tprintf("-source=%s", source_path),
		fmt.tprintf("-build-dir=%s", build_dir),
		fmt.tprintf("-package=%s", out_path),
	}

	desc := os2.Process_Desc {
		working_dir = options.working_dir,
		command = command,
	}

	state, _, _, err := os2.process_exec(desc, context.allocator)
	if err != nil {
		return false
	}
	return state.exited && state.exit_code == 0
}
