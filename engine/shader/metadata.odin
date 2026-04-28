package shader

import "core:os"
import gfx "ape:engine/gfx"

@(private)
PACKAGE_MAGIC :: u32(0x48535041) // "APSH"
@(private)
PACKAGE_VERSION_MIN :: u32(1)
@(private)
PACKAGE_VERSION :: u32(8)
@(private)
PACKAGE_HEADER_SIZE_V1 :: 16
@(private)
PACKAGE_HEADER_SIZE_V3 :: 20
@(private)
PACKAGE_STAGE_RECORD_SIZE :: 48
@(private)
PACKAGE_BINDING_RECORD_SIZE_V2 :: 32
@(private)
PACKAGE_BINDING_RECORD_SIZE_V4 :: 40
@(private)
PACKAGE_BINDING_RECORD_SIZE_V5 :: 48
@(private)
PACKAGE_BINDING_RECORD_SIZE_V7 :: 52
@(private)
PACKAGE_BINDING_RECORD_SIZE_V8 :: 56
@(private)
PACKAGE_VERTEX_INPUT_RECORD_SIZE :: 20

// Backend_Target selects which compiled backend payload to read from an .ashader package.
Backend_Target :: enum {
	D3D11_DXBC,
	Vulkan_SPIRV,
}

// Stage selects a shader stage inside an .ashader package.
Stage :: enum {
	Vertex,
	Fragment,
	Compute,
}

@(private)
Compiled_Stage :: struct {
	target: Backend_Target,
	stage: Stage,
	entry: string,
	path: string,
	reflection_path: string,
}

@(private)
Package_Manifest :: struct {
	source: string,
	stages: []Compiled_Stage,
}

@(private)
Stage_Record :: struct {
	target: Backend_Target,
	stage: Stage,
	entry_offset: u32,
	entry_size: u32,
	bytecode_offset: u64,
	bytecode_size: u64,
	reflection_offset: u64,
	reflection_size: u64,
}

@(private)
Binding_Kind :: enum {
	Uniform_Block,
	Resource_View,
	Sampler,
}

@(private)
Binding_Record :: struct {
	target: Backend_Target,
	stage: Stage,
	kind: Binding_Kind,
	slot: u32,
	native_space: u32,
	logical_slot: u32,
	name_offset: u32,
	name_size: u32,
	used: bool,
	size: u32,
	view_kind: gfx.View_Kind,
	access: gfx.Shader_Resource_Access,
	storage_image_format: gfx.Pixel_Format,
	storage_buffer_stride: u32,
}

@(private)
Vertex_Input_Record :: struct {
	semantic_offset: u32,
	semantic_size: u32,
	semantic_index: u32,
	format: gfx.Vertex_Format,
	used: bool,
}

// Package owns bytes and parsed metadata loaded from one .ashader file.
Package :: struct {
	version: u32,
	bytes: []u8,
	stages: []Stage_Record,
	bindings: []Binding_Record,
	vertex_inputs: []Vertex_Input_Record,
}

// load reads and parses an .ashader package from disk.
load :: proc(path: string) -> (Package, bool) {
	bytes, ok := os.read_entire_file(path)
	if !ok {
		return {}, false
	}

	pkg, parse_ok := parse(bytes)
	if !parse_ok {
		delete(bytes)
		return {}, false
	}

	return pkg, true
}

// unload frees package-owned slices created by load.
unload :: proc(pkg: ^Package) {
	if pkg == nil {
		return
	}

	if pkg.stages != nil {
		delete(pkg.stages)
		pkg.stages = nil
	}
	if pkg.bindings != nil {
		delete(pkg.bindings)
		pkg.bindings = nil
	}
	if pkg.vertex_inputs != nil {
		delete(pkg.vertex_inputs)
		pkg.vertex_inputs = nil
	}
	if pkg.bytes != nil {
		delete(pkg.bytes)
		pkg.bytes = nil
	}
}

// shader_desc converts package bytecode and reflection metadata into a gfx.Shader_Desc.
shader_desc :: proc(pkg: ^Package, target: Backend_Target, label: string) -> (gfx.Shader_Desc, bool) {
	if pkg == nil || pkg.bytes == nil {
		return {}, false
	}

	desc: gfx.Shader_Desc
	desc.label = label
	desc.has_binding_metadata = pkg.version >= 2
	found := false

	for record in pkg.stages {
		if record.target != target {
			continue
		}

		stage, stage_ok := to_gfx_stage(record.stage)
		if !stage_ok {
			return {}, false
		}

		bytecode, bytecode_ok := byte_range(pkg, record.bytecode_offset, record.bytecode_size)
		if !bytecode_ok {
			return {}, false
		}

		entry := ""
		if entry_bytes, entry_ok := byte_range(pkg, u64(record.entry_offset), u64(record.entry_size)); entry_ok {
			entry = string(entry_bytes)
		}

		desc.stages[int(stage)] = gfx.Shader_Stage_Desc {
			stage = stage,
			entry = entry,
			bytecode = gfx.Range{ptr = raw_data(bytecode), size = len(bytecode)},
		}
		found = true
	}

	binding_count := 0
	for record in pkg.bindings {
		if record.target != target || !record.used {
			continue
		}
		if binding_count >= gfx.MAX_SHADER_BINDINGS {
			return {}, false
		}

		stage, stage_ok := to_gfx_stage(record.stage)
		if !stage_ok {
			return {}, false
		}

		kind, kind_ok := to_gfx_binding_kind(record.kind)
		if !kind_ok {
			return {}, false
		}

		name := ""
		if name_bytes, name_ok := byte_range(pkg, u64(record.name_offset), u64(record.name_size)); name_ok {
			name = string(name_bytes)
		}

		desc.bindings[binding_count] = gfx.Shader_Binding_Desc {
			active = true,
			stage = stage,
			kind = kind,
			slot = record.logical_slot,
			native_slot = record.slot,
			native_space = record.native_space,
			name = name,
			size = record.size,
			view_kind = record.view_kind,
			access = record.access,
			storage_image_format = record.storage_image_format,
			storage_buffer_stride = record.storage_buffer_stride,
		}
		binding_count += 1
	}

	vertex_input_count := 0
	for record in pkg.vertex_inputs {
		if !record.used {
			continue
		}
		if vertex_input_count >= gfx.MAX_VERTEX_ATTRIBUTES {
			return {}, false
		}

		semantic := ""
		if semantic_bytes, semantic_ok := byte_range(pkg, u64(record.semantic_offset), u64(record.semantic_size)); semantic_ok {
			semantic = string(semantic_bytes)
		}

		desc.vertex_inputs[vertex_input_count] = gfx.Shader_Vertex_Input_Desc {
			active = true,
			semantic = semantic,
			semantic_index = record.semantic_index,
			format = record.format,
		}
		vertex_input_count += 1
	}
	desc.has_vertex_input_metadata = vertex_input_count > 0

	return desc, found
}

// reflection_json returns the embedded Slang reflection JSON for a target/stage pair.
reflection_json :: proc(pkg: ^Package, target: Backend_Target, stage: Stage) -> (string, bool) {
	if pkg == nil || pkg.bytes == nil {
		return "", false
	}

	for record in pkg.stages {
		if record.target != target || record.stage != stage {
			continue
		}

		bytes, ok := byte_range(pkg, record.reflection_offset, record.reflection_size)
		if !ok {
			return "", false
		}

		return string(bytes), true
	}

	return "", false
}

@(private)
parse :: proc(bytes: []u8) -> (Package, bool) {
	if len(bytes) < PACKAGE_HEADER_SIZE_V1 {
		return {}, false
	}

	if read_u32(bytes, 0) != PACKAGE_MAGIC {
		return {}, false
	}
	version := read_u32(bytes, 4)
	if version < PACKAGE_VERSION_MIN || version > PACKAGE_VERSION {
		return {}, false
	}

	header_size := package_header_size(version)
	if len(bytes) < header_size {
		return {}, false
	}

	stage_count := read_u32(bytes, 8)
	if stage_count == 0 || stage_count > 32 {
		return {}, false
	}

	binding_count := u32(0)
	if version >= 2 {
		binding_count = read_u32(bytes, 12)
		if binding_count > gfx.MAX_SHADER_BINDINGS * 4 {
			return {}, false
		}
	}

	vertex_input_count := u32(0)
	if version >= 3 {
		vertex_input_count = read_u32(bytes, 16)
		if vertex_input_count > gfx.MAX_VERTEX_ATTRIBUTES {
			return {}, false
		}
	}

	record_bytes := header_size +
	                int(stage_count) * PACKAGE_STAGE_RECORD_SIZE +
	                int(binding_count) * package_binding_record_size(version) +
	                int(vertex_input_count) * PACKAGE_VERTEX_INPUT_RECORD_SIZE
	if record_bytes > len(bytes) {
		return {}, false
	}

	stages := make([]Stage_Record, int(stage_count))
	for i in 0..<int(stage_count) {
		offset := header_size + i * PACKAGE_STAGE_RECORD_SIZE
		record := Stage_Record {
			target = Backend_Target(read_u32(bytes, offset + 0)),
			stage = Stage(read_u32(bytes, offset + 4)),
			entry_offset = read_u32(bytes, offset + 8),
			entry_size = read_u32(bytes, offset + 12),
			bytecode_offset = read_u64(bytes, offset + 16),
			bytecode_size = read_u64(bytes, offset + 24),
			reflection_offset = read_u64(bytes, offset + 32),
			reflection_size = read_u64(bytes, offset + 40),
		}

		if !range_valid(bytes, u64(record.entry_offset), u64(record.entry_size)) ||
		   !range_valid(bytes, record.bytecode_offset, record.bytecode_size) ||
		   !range_valid(bytes, record.reflection_offset, record.reflection_size) {
			delete(stages)
			return {}, false
		}

		stages[i] = record
	}

	bindings: []Binding_Record
	if binding_count > 0 {
		bindings = make([]Binding_Record, int(binding_count))
		binding_records_offset := header_size + int(stage_count) * PACKAGE_STAGE_RECORD_SIZE
		binding_record_size := package_binding_record_size(version)

		for i in 0..<int(binding_count) {
			offset := binding_records_offset + i * binding_record_size
			record := Binding_Record {
				target = Backend_Target(read_u32(bytes, offset + 0)),
				stage = Stage(read_u32(bytes, offset + 4)),
				kind = Binding_Kind(read_u32(bytes, offset + 8)),
				slot = read_u32(bytes, offset + 12),
				name_offset = read_u32(bytes, offset + 16),
				name_size = read_u32(bytes, offset + 20),
				used = read_u32(bytes, offset + 24) != 0,
				size = read_u32(bytes, offset + 28),
			}
			if version >= 4 {
				record.logical_slot = read_u32(bytes, offset + 32)
			} else {
				record.logical_slot = record.slot
			}
			if version >= 5 {
				record.view_kind = gfx.View_Kind(read_u32(bytes, offset + 36))
				record.access = gfx.Shader_Resource_Access(read_u32(bytes, offset + 40))
			} else if record.kind == .Resource_View {
				record.view_kind = .Sampled
				record.access = .Read
			}
			if version >= 6 {
				record.storage_image_format = gfx.Pixel_Format(read_u32(bytes, offset + 44))
			}
			if version >= 7 {
				record.storage_buffer_stride = read_u32(bytes, offset + 48)
			}
			if version >= 8 {
				record.native_space = read_u32(bytes, offset + 52)
			}

			if !range_valid(bytes, u64(record.name_offset), u64(record.name_size)) ||
			   !binding_record_metadata_valid(record) {
				delete(stages)
				delete(bindings)
				return {}, false
			}

			bindings[i] = record
		}
	}

	vertex_inputs: []Vertex_Input_Record
	if vertex_input_count > 0 {
		vertex_inputs = make([]Vertex_Input_Record, int(vertex_input_count))
		vertex_records_offset := header_size +
		                         int(stage_count) * PACKAGE_STAGE_RECORD_SIZE +
		                         int(binding_count) * package_binding_record_size(version)

		for i in 0..<int(vertex_input_count) {
			offset := vertex_records_offset + i * PACKAGE_VERTEX_INPUT_RECORD_SIZE
			record := Vertex_Input_Record {
				semantic_offset = read_u32(bytes, offset + 0),
				semantic_size = read_u32(bytes, offset + 4),
				semantic_index = read_u32(bytes, offset + 8),
				format = gfx.Vertex_Format(read_u32(bytes, offset + 12)),
				used = read_u32(bytes, offset + 16) != 0,
			}

			if !range_valid(bytes, u64(record.semantic_offset), u64(record.semantic_size)) ||
			   !vertex_format_valid(record.format) {
				delete(stages)
				if bindings != nil {
					delete(bindings)
				}
				delete(vertex_inputs)
				return {}, false
			}

			vertex_inputs[i] = record
		}
	}

	return Package{version = version, bytes = bytes, stages = stages, bindings = bindings, vertex_inputs = vertex_inputs}, true
}

@(private)
package_header_size :: proc(version: u32) -> int {
	if version >= 3 {
		return PACKAGE_HEADER_SIZE_V3
	}

	return PACKAGE_HEADER_SIZE_V1
}

@(private)
package_binding_record_size :: proc(version: u32) -> int {
	if version >= 5 {
		if version >= 8 {
			return PACKAGE_BINDING_RECORD_SIZE_V8
		}
		if version >= 7 {
			return PACKAGE_BINDING_RECORD_SIZE_V7
		}
		return PACKAGE_BINDING_RECORD_SIZE_V5
	}
	if version >= 4 {
		return PACKAGE_BINDING_RECORD_SIZE_V4
	}

	return PACKAGE_BINDING_RECORD_SIZE_V2
}

@(private)
byte_range :: proc(pkg: ^Package, offset: u64, size: u64) -> ([]u8, bool) {
	if pkg == nil || !range_valid(pkg.bytes, offset, size) {
		return nil, false
	}

	start := int(offset)
	end := start + int(size)
	return pkg.bytes[start:end], true
}

@(private)
range_valid :: proc(bytes: []u8, offset: u64, size: u64) -> bool {
	byte_count := u64(len(bytes))
	if offset > byte_count {
		return false
	}
	if size > byte_count - offset {
		return false
	}

	return true
}

@(private)
to_gfx_stage :: proc(stage: Stage) -> (gfx.Shader_Stage, bool) {
	switch stage {
	case .Vertex:
		return .Vertex, true
	case .Fragment:
		return .Fragment, true
	case .Compute:
		return .Compute, true
	}

	return .Vertex, false
}

@(private)
to_gfx_binding_kind :: proc(kind: Binding_Kind) -> (gfx.Shader_Binding_Kind, bool) {
	switch kind {
	case .Uniform_Block:
		return .Uniform_Block, true
	case .Resource_View:
		return .Resource_View, true
	case .Sampler:
		return .Sampler, true
	}

	return .Uniform_Block, false
}

@(private)
vertex_format_valid :: proc(format: gfx.Vertex_Format) -> bool {
	switch format {
	case .Float32, .Float32x2, .Float32x3, .Float32x4, .Uint8x4_Norm:
		return true
	case .Invalid:
		return false
	}

	return false
}

@(private)
binding_record_metadata_valid :: proc(record: Binding_Record) -> bool {
	if record.kind != .Resource_View {
		return true
	}

	return view_kind_valid_for_resource_binding(record.view_kind) &&
	       shader_resource_access_valid(record.access) &&
	       storage_image_format_valid(record.storage_image_format) &&
	       storage_buffer_stride_valid(record.storage_buffer_stride)
}

@(private)
view_kind_valid_for_resource_binding :: proc(kind: gfx.View_Kind) -> bool {
	switch kind {
	case .Sampled, .Storage_Image, .Storage_Buffer:
		return true
	case .Color_Attachment, .Depth_Stencil_Attachment:
		return false
	}

	return false
}

@(private)
shader_resource_access_valid :: proc(access: gfx.Shader_Resource_Access) -> bool {
	switch access {
	case .Unknown, .Read, .Write, .Read_Write:
		return true
	}

	return false
}

@(private)
storage_image_format_valid :: proc(format: gfx.Pixel_Format) -> bool {
	switch format {
	case .Invalid, .RGBA32F, .R32F:
		return true
	case .RGBA8, .BGRA8, .RGBA16F, .D24S8, .D32F:
		return false
	}

	return false
}

@(private)
storage_buffer_stride_valid :: proc(stride: u32) -> bool {
	return stride == 0 || stride % 4 == 0
}

@(private)
read_u32 :: proc(bytes: []u8, offset: int) -> u32 {
	return u32(bytes[offset]) |
	       (u32(bytes[offset + 1]) << 8) |
	       (u32(bytes[offset + 2]) << 16) |
	       (u32(bytes[offset + 3]) << 24)
}

@(private)
read_u64 :: proc(bytes: []u8, offset: int) -> u64 {
	return u64(read_u32(bytes, offset)) |
	       (u64(read_u32(bytes, offset + 4)) << 32)
}
