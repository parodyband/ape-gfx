#+private
package gfx

import "core:mem"
import d3d11 "vendor:directx/d3d11"

d3d11_create_buffer :: proc(ctx: ^Context, handle: Buffer, desc: Buffer_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	if u64(desc.size) > 0xffffffff {
		set_validation_error(ctx, "gfx.d3d11: buffer size exceeds D3D11 u32 limit")
		return false
	}
	if desc.storage_stride > d3d11.REQ_MULTI_ELEMENT_STRUCTURE_SIZE_IN_BYTES {
		set_validation_errorf(ctx, "gfx.d3d11: structured storage buffer stride exceeds D3D11 limit (%d)", d3d11.REQ_MULTI_ELEMENT_STRUCTURE_SIZE_IN_BYTES)
		return false
	}

	if !d3d11_validate_buffer_usage(ctx, desc.usage) {
		return false
	}

	if .Immutable in desc.usage && (desc.data.ptr == nil || desc.data.size <= 0) {
		set_validation_error(ctx, "gfx.d3d11: immutable buffers require initial data")
		return false
	}

	buffer_desc := d3d11.BUFFER_DESC {
		ByteWidth = u32(desc.size),
		Usage = d3d11_buffer_usage(desc.usage),
		BindFlags = d3d11_buffer_bind_flags(desc.usage),
		CPUAccessFlags = d3d11_buffer_cpu_access(desc.usage),
		MiscFlags = d3d11_buffer_misc_flags(desc.usage, desc.storage_stride),
		StructureByteStride = u32(desc.storage_stride),
	}

	initial_data: d3d11.SUBRESOURCE_DATA
	initial_data_ptr: ^d3d11.SUBRESOURCE_DATA
	if desc.data.ptr != nil && desc.data.size > 0 {
		initial_data = d3d11.SUBRESOURCE_DATA {
			pSysMem = desc.data.ptr,
			SysMemPitch = 0,
			SysMemSlicePitch = 0,
		}
		initial_data_ptr = &initial_data
	}

	native_buffer: ^d3d11.IBuffer
	hr := state.device.CreateBuffer(state.device, &buffer_desc, initial_data_ptr, &native_buffer)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: CreateBuffer failed")
		return false
	}
	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)native_buffer, desc.label)

	state.buffers[handle] = D3D11_Buffer {
		buffer = native_buffer,
		usage = desc.usage,
		size = u32(desc.size),
		storage_stride = u32(desc.storage_stride),
	}
	return true
}

d3d11_destroy_buffer :: proc(ctx: ^Context, handle: Buffer) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if buffer_info, ok := state.buffers[handle]; ok {
		if buffer_info.buffer != nil {
			buffer_info.buffer.Release(buffer_info.buffer)
		}
		delete_key(&state.buffers, handle)
	}
}

d3d11_update_buffer :: proc(ctx: ^Context, desc: Buffer_Update_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	buffer_info, buffer_ok := state.buffers[desc.buffer]
	if !buffer_ok || buffer_info.buffer == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: buffer handle is unknown")
		return false
	}

	if !d3d11_buffer_has_cpu_update(buffer_info.usage) {
		set_validation_error(ctx, "gfx.d3d11: update_buffer requires a dynamic or stream-updated buffer")
		return false
	}

	if desc.offset < 0 ||
	   desc.data.ptr == nil ||
	   desc.data.size <= 0 ||
	   desc.offset > int(buffer_info.size) ||
	   desc.data.size > int(buffer_info.size) - desc.offset {
		set_validation_error(ctx, "gfx.d3d11: update_buffer range is invalid")
		return false
	}

	if .Dynamic_Update in buffer_info.usage && (desc.offset != 0 || desc.data.size != int(buffer_info.size)) {
		set_validation_error(ctx, "gfx.d3d11: dynamic buffer updates must replace the full buffer; use Stream_Update for ranged writes")
		return false
	}

	map_type := d3d11.MAP.WRITE_DISCARD
	if .Stream_Update in buffer_info.usage && desc.offset != 0 {
		map_type = .WRITE_NO_OVERWRITE
	}

	mapped: d3d11.MAPPED_SUBRESOURCE
	hr := state.immediate.Map(
		state.immediate,
		cast(^d3d11.IResource)buffer_info.buffer,
		0,
		map_type,
		{},
		&mapped,
	)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to map buffer for update")
		return false
	}

	dst := rawptr(uintptr(mapped.pData) + uintptr(desc.offset))
	mem.copy(dst, desc.data.ptr, desc.data.size)
	state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)buffer_info.buffer, 0)
	return true
}

d3d11_read_buffer :: proc(ctx: ^Context, desc: Buffer_Read_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return false
	}

	buffer_info, buffer_ok := state.buffers[desc.buffer]
	if !buffer_ok || buffer_info.buffer == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: buffer handle is unknown")
		return false
	}

	if desc.offset < 0 ||
	   desc.data.ptr == nil ||
	   desc.data.size <= 0 ||
	   desc.offset > int(buffer_info.size) ||
	   desc.data.size > int(buffer_info.size) - desc.offset {
		set_validation_error(ctx, "gfx.d3d11: read_buffer range is invalid")
		return false
	}

	if u64(desc.data.size) > 0xffffffff {
		set_validation_error(ctx, "gfx.d3d11: read_buffer size exceeds D3D11 u32 limit")
		return false
	}

	staging_desc := d3d11.BUFFER_DESC {
		ByteWidth = u32(desc.data.size),
		Usage = .STAGING,
		BindFlags = {},
		CPUAccessFlags = {.READ},
		MiscFlags = {},
		StructureByteStride = 0,
	}

	staging: ^d3d11.IBuffer
	hr := state.device.CreateBuffer(state.device, &staging_desc, nil, &staging)
	if d3d11_failed(hr) || staging == nil {
		set_backend_error(ctx, "gfx.d3d11: failed to create staging readback buffer")
		return false
	}
	defer staging.Release(staging)

	source_box := d3d11.BOX {
		left = u32(desc.offset),
		top = 0,
		front = 0,
		right = u32(desc.offset + desc.data.size),
		bottom = 1,
		back = 1,
	}
	state.immediate.CopySubresourceRegion(
		state.immediate,
		cast(^d3d11.IResource)staging,
		0,
		0,
		0,
		0,
		cast(^d3d11.IResource)buffer_info.buffer,
		0,
		&source_box,
	)

	mapped: d3d11.MAPPED_SUBRESOURCE
	hr = state.immediate.Map(
		state.immediate,
		cast(^d3d11.IResource)staging,
		0,
		.READ,
		{},
		&mapped,
	)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: failed to map readback buffer")
		return false
	}

	mem.copy(desc.data.ptr, mapped.pData, desc.data.size)
	state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)staging, 0)
	return true
}

d3d11_query_buffer_state :: proc(ctx: ^Context, handle: Buffer) -> Buffer_State {
	state := d3d11_state(ctx)
	if state == nil {
		return {}
	}

	if buffer_info, ok := state.buffers[handle]; ok {
		return {
			valid = buffer_info.buffer != nil,
			usage = buffer_info.usage,
			size = int(buffer_info.size),
			storage_stride = int(buffer_info.storage_stride),
		}
	}

	return {}
}

d3d11_validate_buffer_usage :: proc(ctx: ^Context, usage: Buffer_Usage) -> bool {
	role_count := 0
	if .Vertex in usage {
		role_count += 1
	}
	if .Index in usage {
		role_count += 1
	}
	if .Uniform in usage {
		role_count += 1
	}
	if .Storage in usage {
		role_count += 1
	}
	if .Indirect in usage {
		role_count += 1
	}
	if role_count == 0 {
		set_validation_error(ctx, "gfx.d3d11: buffer usage must include at least one role flag")
		return false
	}

	update_count := 0
	if .Immutable in usage {
		update_count += 1
	}
	if .Dynamic_Update in usage {
		update_count += 1
	}
	if .Stream_Update in usage {
		update_count += 1
	}
	if update_count == 0 && !(.Storage in usage) {
		set_validation_error(ctx, "gfx.d3d11: buffer usage must include an update/lifetime flag")
		return false
	}
	if update_count > 1 {
		set_validation_error(ctx, "gfx.d3d11: buffer usage has conflicting update/lifetime flags")
		return false
	}
	if .Storage in usage && (.Immutable in usage || .Dynamic_Update in usage || .Stream_Update in usage) {
		set_validation_error(ctx, "gfx.d3d11: storage buffers are GPU-only for now and must not use update/lifetime flags")
		return false
	}

	return true
}

d3d11_buffer_usage :: proc(usage: Buffer_Usage) -> d3d11.USAGE {
	if .Storage in usage {
		return .DEFAULT
	}
	// Indirect-only buffers carry MiscFlags=DRAWINDIRECT_ARGS with BindFlags=0;
	// D3D11 rejects USAGE=IMMUTABLE in that shape (E_INVALIDARG), so use DEFAULT.
	if .Indirect in usage && d3d11_buffer_bind_flags(usage) == {} {
		return .DEFAULT
	}
	if .Immutable in usage {
		return .IMMUTABLE
	}
	if .Dynamic_Update in usage || .Stream_Update in usage {
		return .DYNAMIC
	}

	return .IMMUTABLE
}

d3d11_buffer_cpu_access :: proc(usage: Buffer_Usage) -> d3d11.CPU_ACCESS_FLAGS {
	if .Dynamic_Update in usage || .Stream_Update in usage {
		return d3d11.CPU_ACCESS_FLAGS{.WRITE}
	}

	return {}
}

d3d11_buffer_misc_flags :: proc(usage: Buffer_Usage, storage_stride: int) -> d3d11.RESOURCE_MISC_FLAGS {
	flags: d3d11.RESOURCE_MISC_FLAGS
	if .Storage in usage {
		if storage_stride > 0 {
			flags += {.BUFFER_STRUCTURED}
		} else {
			flags += {.BUFFER_ALLOW_RAW_VIEWS}
		}
	}
	if .Indirect in usage {
		flags += {.DRAWINDIRECT_ARGS}
	}

	return flags
}

d3d11_buffer_bind_flags :: proc(usage: Buffer_Usage) -> d3d11.BIND_FLAGS {
	flags: d3d11.BIND_FLAGS
	if .Vertex in usage {
		flags += {.VERTEX_BUFFER}
	}
	if .Index in usage {
		flags += {.INDEX_BUFFER}
	}
	if .Uniform in usage {
		flags += {.CONSTANT_BUFFER}
	}
	if .Storage in usage {
		flags += {.SHADER_RESOURCE, .UNORDERED_ACCESS}
	}

	return flags
}

d3d11_buffer_has_cpu_update :: proc(usage: Buffer_Usage) -> bool {
	return .Dynamic_Update in usage || .Stream_Update in usage
}
