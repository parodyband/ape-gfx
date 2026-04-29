package main

import "core:fmt"
import "core:os"
import os2 "core:os/os2"
import "core:path/filepath"
import "core:strings"

Docs_Generate_Options :: struct {
	root_path: string,
	out_dir: string,
	markdown_dir: string,
}

Doc_Section :: enum {
	None,
	Constants,
	Procedures,
	Types,
}

Doc_Entry :: struct {
	name: string,
	declaration: string,
	docs: [dynamic]string,
}

Doc_Entries :: struct {
	constants: [dynamic]Doc_Entry,
	procedures: [dynamic]Doc_Entry,
	types: [dynamic]Doc_Entry,
}

parse_docs_generate_options :: proc(args: []string) -> (Docs_Generate_Options, bool) {
	options := Docs_Generate_Options {
		root_path = ".",
		out_dir = "docs/api/raw",
		markdown_dir = "docs/api/markdown",
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
		case "-out-dir", "-OutDir":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.out_dir = args[i]
		case "-markdown-dir", "-MarkdownDir":
			i += 1
			if i >= len(args) {
				return {}, false
			}
			options.markdown_dir = args[i]
		case:
			return {}, false
		}
	}

	return options, true
}

generate_api_docs :: proc(options: Docs_Generate_Options) -> bool {
	root, root_ok := filepath.abs(options.root_path, context.temp_allocator)
	if !root_ok {
		fmt.eprintln("ape: failed to resolve repo root: ", options.root_path)
		return false
	}

	output_dir := repo_path(root, options.out_dir)
	markdown_output_dir := repo_path(root, options.markdown_dir)
	api_dir, _ := filepath.split(output_dir)

	if !ensure_directory(output_dir) || !ensure_directory(markdown_output_dir) || !ensure_directory(api_dir) {
		return false
	}

	gfx_raw, gfx_ok := write_odin_doc(root, output_dir, "gfx_api", "gfx", true)
	if !gfx_ok {
		return false
	}
	app_raw, app_ok := write_odin_doc(root, output_dir, "app_api", "app", false)
	if !app_ok {
		return false
	}
	gfx_app_raw, gfx_app_ok := write_odin_doc(root, output_dir, "gfx_app_api", "gfx_app", false)
	if !gfx_app_ok {
		return false
	}
	shader_raw, shader_ok := write_odin_doc(root, output_dir, "shader_api", "shader", false)
	if !shader_ok {
		return false
	}

	if !convert_raw_doc_to_markdown(markdown_output_dir, "gfx", "gfx", gfx_raw) {
		return false
	}
	if !convert_raw_doc_to_markdown(markdown_output_dir, "app", "app", app_raw) {
		return false
	}
	if !convert_raw_doc_to_markdown(markdown_output_dir, "gfx_app", "gfx_app", gfx_app_raw) {
		return false
	}
	if !convert_raw_doc_to_markdown(markdown_output_dir, "shader", "shader", shader_raw) {
		return false
	}
	if !write_api_index(api_dir) {
		return false
	}

	fmt.printf("Generated raw API docs in %s\n", output_dir)
	fmt.printf("Generated Markdown API docs in %s\n", markdown_output_dir)
	return true
}

write_odin_doc :: proc(root: string, output_dir: string, name: string, package_path: string, collapse_context: bool) -> (string, bool) {
	target := filepath.join({output_dir, fmt.tprintf("%s.txt", name)}, context.temp_allocator)
	command := [?]string {
		"odin",
		"doc",
		repo_path(root, package_path),
		fmt.tprintf("-collection:ape=%s", root),
	}

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

	if len(stderr) > 0 {
		fmt.eprint(string(stderr))
	}
	if err != nil {
		fmt.eprintln("ape: odin doc failed for ", package_path, ": ", err)
		return "", false
	}
	if !state.exited || state.exit_code != 0 {
		fmt.eprintln("ape: odin doc failed for ", package_path, " with exit ", state.exit_code)
		return "", false
	}

	normalized := normalize_raw_doc_text(string(stdout), root, collapse_context)
	if !write_text_file(target, normalized) {
		return "", false
	}

	fmt.println("Wrote ", target)
	return target, true
}

normalize_raw_doc_text :: proc(text: string, root: string, collapse_context: bool) -> string {
	root_slashes, _ := strings.replace_all(root, "\\", "/", context.temp_allocator)
	replaced, _ := strings.replace_all(text, root_slashes, "<repo>", context.temp_allocator)
	replaced, _ = strings.replace_all(replaced, root, "<repo>", context.temp_allocator)

	if !collapse_context {
		return replaced
	}

	lines := strings.split_lines(replaced, context.temp_allocator)
	out: [dynamic]byte
	for line in lines {
		normalized_line := line
		if strings.has_prefix(strings.trim_left(normalized_line, "\t "), "Context :: struct {") {
			leading_len := len(normalized_line) - len(strings.trim_left(normalized_line, "\t "))
			prefix := normalized_line[:leading_len]
			append_doc_text(&out, prefix)
			append_doc_line(&out, "Context :: struct {...}")
			continue
		}
		append_doc_line(&out, normalized_line)
	}

	finish_doc_text(&out)
	return string(out[:])
}

convert_raw_doc_to_markdown :: proc(markdown_output_dir: string, name: string, title: string, raw_path: string) -> bool {
	target := filepath.join({markdown_output_dir, fmt.tprintf("%s.md", name)}, context.temp_allocator)
	raw, raw_ok := read_text_file(raw_path)
	if !raw_ok {
		return false
	}
	defer delete(raw)

	package_name := name
	entries: Doc_Entries
	defer delete_doc_entries(&entries)

	current_section := Doc_Section.None
	current_declaration := ""
	current_docs: [dynamic]string
	defer delete(current_docs)

	lines := strings.split_lines(raw, context.temp_allocator)
	for raw_line in lines {
		line := strings.trim_right(raw_line, "\r")

		if strings.has_prefix(line, "package ") {
			package_name = strings.trim_space(line[len("package "):])
			continue
		}

		if strings.has_prefix(line, "\tfullpath:") || strings.has_prefix(line, "\tfiles:") {
			add_doc_entry(&entries, current_section, current_declaration, current_docs[:])
			current_section = .None
			current_declaration = ""
			clear(&current_docs)
			continue
		}

		if line == "\tconstants" || line == "\tprocedures" || line == "\ttypes" {
			add_doc_entry(&entries, current_section, current_declaration, current_docs[:])
			current_section = doc_section_from_header(strings.trim_space(line))
			current_declaration = ""
			clear(&current_docs)
			continue
		}

		if current_section != .None && strings.has_prefix(line, "\t\t") && !strings.has_prefix(line, "\t\t\t") {
			add_doc_entry(&entries, current_section, current_declaration, current_docs[:])
			current_declaration = strings.trim_right(line[2:], "\r")
			clear(&current_docs)
			continue
		}

		if current_declaration != "" && strings.has_prefix(line, "\t\t\t") {
			append(&current_docs, strings.trim_right(line[3:], "\r"))
			continue
		}
	}

	add_doc_entry(&entries, current_section, current_declaration, current_docs[:])

	out: [dynamic]byte
	append_doc_line(&out, fmt.tprintf("# %s API", title))
	append_doc_line(&out, "")
	append_doc_line(&out, "Generated by `tools/ape docs generate` from `odin doc` output.")
	append_doc_line(&out, "")
	append_doc_line(&out, fmt.tprintf("Package: `%s`", package_name))
	append_doc_line(&out, "")
	append_markdown_section(&out, "Constants", entries.constants[:])
	append_markdown_section(&out, "Procedures", entries.procedures[:])
	append_markdown_section(&out, "Types", entries.types[:])

	finish_doc_text(&out)

	if !os.write_entire_file(target, out[:]) {
		fmt.eprintln("ape: failed to write file: ", target)
		return false
	}

	fmt.println("Wrote ", target)
	return true
}

append_markdown_section :: proc(out: ^[dynamic]byte, title: string, entries: []Doc_Entry) {
	append_doc_line(out, fmt.tprintf("## %s", title))
	append_doc_line(out, "")

	if len(entries) == 0 {
		append_doc_line(out, fmt.tprintf("_No public %s._", strings.to_lower(title, context.temp_allocator)))
		append_doc_line(out, "")
		return
	}

	for entry in entries {
		append_doc_line(out, fmt.tprintf("### `%s`", entry.name))
		append_doc_line(out, "")
		append_doc_line(out, "```odin")
		append_doc_line(out, entry.declaration)
		append_doc_line(out, "```")
		append_doc_line(out, "")

		if len(entry.docs) > 0 {
			for doc_line in entry.docs {
				append_doc_line(out, doc_line)
			}
			append_doc_line(out, "")
		}
	}
}

write_api_index :: proc(api_dir: string) -> bool {
	target := filepath.join({api_dir, "README.md"}, context.temp_allocator)
	content := `# Ape API Docs

Generated by ` + "`tools/ape docs generate`" + `.

These docs are checked in so API drift is visible in normal diffs.

## Packages

- ` + "`raw/gfx_api.txt`" + `: low-level graphics API symbols.
- ` + "`raw/app_api.txt`" + `: minimal window/event facade used by the samples.
- ` + "`raw/gfx_app_api.txt`" + `: app-facing graphics helper package.
- ` + "`raw/shader_api.txt`" + `: ` + "`.ashader`" + ` package loader and shader descriptor conversion.

## Markdown

- ` + "`markdown/gfx.md`" + `: low-level graphics API reference.
- ` + "`markdown/app.md`" + `: minimal window/event API reference.
- ` + "`markdown/gfx_app.md`" + `: app-facing graphics helper API reference.
- ` + "`markdown/shader.md`" + `: shader package loader API reference.

## Status

The ` + "`gfx`" + ` docs are filtered with Odin private-file/private-symbol annotations for backend internals and include first-pass comments on the public API. The current decision is to keep ` + "`gfx`" + ` as the public package instead of adding a smaller facade package; explicit descriptors and handles are the intended low-level API. ` + "`tools/test_api_docs_public_surface.ps1`" + ` guards against backend internals leaking back into generated API docs.
`

	if !write_text_file(target, content) {
		return false
	}

	fmt.println("Wrote ", target)
	return true
}

add_doc_entry :: proc(entries: ^Doc_Entries, section: Doc_Section, declaration: string, docs: []string) {
	if section == .None || strings.trim_space(declaration) == "" {
		return
	}

	entry := Doc_Entry {
		name = doc_symbol_name(declaration),
		declaration = strings.trim_right(declaration, "\r"),
	}
	for doc in docs {
		if strings.trim_space(doc) != "" {
			append(&entry.docs, strings.trim_right(doc, "\r"))
		}
	}

	switch section {
	case .Constants:
		append(&entries.constants, entry)
	case .Procedures:
		append(&entries.procedures, entry)
	case .Types:
		append(&entries.types, entry)
	case .None:
		delete_doc_entry(&entry)
	}
}

doc_symbol_name :: proc(declaration: string) -> string {
	trimmed := strings.trim_space(declaration)
	if index := strings.index(trimmed, " :: "); index >= 0 {
		return strings.trim_space(trimmed[:index])
	}

	for field in strings.fields_iterator(&trimmed) {
		return field
	}
	return trimmed
}

doc_section_from_header :: proc(header: string) -> Doc_Section {
	switch header {
	case "constants":
		return .Constants
	case "procedures":
		return .Procedures
	case "types":
		return .Types
	}
	return .None
}

delete_doc_entries :: proc(entries: ^Doc_Entries) {
	for &entry in entries.constants {
		delete_doc_entry(&entry)
	}
	for &entry in entries.procedures {
		delete_doc_entry(&entry)
	}
	for &entry in entries.types {
		delete_doc_entry(&entry)
	}
	delete(entries.constants)
	delete(entries.procedures)
	delete(entries.types)
}

delete_doc_entry :: proc(entry: ^Doc_Entry) {
	delete(entry.docs)
}

append_doc_text :: proc(out: ^[dynamic]byte, text: string) {
	for b in transmute([]byte)text {
		append(out, b)
	}
}

append_doc_line :: proc(out: ^[dynamic]byte, text: string) {
	append_doc_text(out, text)
	append(out, '\n')
}

finish_doc_text :: proc(out: ^[dynamic]byte) {
	for len(out^) > 0 {
		last := out^[len(out^) - 1]
		if last != '\n' && last != '\r' && last != ' ' && last != '\t' {
			break
		}
		resize(out, len(out^) - 1)
	}
	if len(out^) > 0 {
		append(out, '\n')
	}
}
