#+private
package gfx

import d3d11 "vendor:directx/d3d11"

// D3D11 transient allocator backing — see gfx-transient-allocator-note.md
// and AAA roadmap item 24 (APE-20).
//
// Approach:
//   - One `D3D11_USAGE_DYNAMIC` `ID3D11Buffer` per requested role, sized to
//     the allocator's `capacity` (default 4 MiB). The chunk-pool model
//     reduces to one chunk per role for now; growing into multi-chunk
//     pools is a future change that does not break the public API.
//   - `Map(WRITE_DISCARD)` once at chunk creation. The mapped pointer is
//     held for the life of the frame and handed out as
//     `Transient_Slice.mapped` offsets. D3D11 allows reading the buffer
//     contents on the CPU through this pointer (write-combined memory),
//     but the `Transient_Slice` contract is write-only.
//   - At reset (after the previous frame's GPU work has retired) the
//     buffer is `Unmap`-ped and re-`Map`-ped with `WRITE_DISCARD`,
//     rotating to fresh storage and avoiding GPU/CPU contention. This is
//     the standard sokol-style per-frame ring-rotate; once
//     `Timeline_Semaphore` lands in queue.odin, the wait moves into the
//     reset call's `Semaphore_Wait` argument.
//   - Sub-allocations within a chunk are pure CPU bump-pointer ops; no
//     `Map(WRITE_NO_OVERWRITE)` is required because the buffer stays
//     mapped end-to-end.
//
// `Transient_Usage.Storage` and `.Indirect` need GPU-writable / indirect-
// argument bind flags that cannot coexist with `D3D11_USAGE_DYNAMIC` plus
// CPU write access on the same buffer. Until APE-7 / APE-25 introduce a
// staging-then-copy path, those roles are rejected here. `Uniform`,
// `Vertex`, and `Index` all map cleanly to dynamic CPU-write buffers.

d3d11_create_transient_chunk :: proc(ctx: ^Context, role: Transient_Usage, capacity: int, label: string) -> (Buffer, rawptr, bool) {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return Buffer_Invalid, nil, false
	}

	if capacity <= 0 || u64(capacity) > 0xffffffff {
		set_validation_errorf(ctx, "gfx.d3d11: transient chunk capacity %d is invalid", capacity)
		return Buffer_Invalid, nil, false
	}

	bind_flags, role_usage, ok := d3d11_transient_role_flags(role)
	if !ok {
		set_unsupported_errorf(ctx, "gfx.d3d11: transient role %v is not supported by the D3D11 dynamic-buffer model yet", role)
		return Buffer_Invalid, nil, false
	}

	buffer_desc := d3d11.BUFFER_DESC {
		ByteWidth      = u32(capacity),
		Usage          = .DYNAMIC,
		BindFlags      = bind_flags,
		CPUAccessFlags = {.WRITE},
	}

	native_buffer: ^d3d11.IBuffer
	hr := state.device.CreateBuffer(state.device, &buffer_desc, nil, &native_buffer)
	if d3d11_failed(hr) || native_buffer == nil {
		set_backend_error(ctx, "gfx.d3d11: CreateBuffer for transient chunk failed")
		return Buffer_Invalid, nil, false
	}
	d3d11_set_debug_name_suffixed(cast(^d3d11.IDeviceChild)native_buffer, label, d3d11_transient_role_label(role))

	mapped: d3d11.MAPPED_SUBRESOURCE
	hr = state.immediate.Map(state.immediate, cast(^d3d11.IResource)native_buffer, 0, .WRITE_DISCARD, {}, &mapped)
	if d3d11_failed(hr) || mapped.pData == nil {
		native_buffer.Release(native_buffer)
		set_backend_error(ctx, "gfx.d3d11: failed to map transient chunk")
		return Buffer_Invalid, nil, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.buffer_pool, "gfx.d3d11.transient_chunk")
	if handle_id == 0 {
		state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)native_buffer, 0)
		native_buffer.Release(native_buffer)
		return Buffer_Invalid, nil, false
	}
	handle := Buffer(handle_id)

	state.buffers[handle] = D3D11_Buffer {
		buffer               = native_buffer,
		usage                = role_usage,
		size                 = u32(capacity),
		transient_mapped     = true,
		transient_mapped_ptr = mapped.pData,
	}

	return handle, mapped.pData, true
}

// d3d11_transient_chunk_unmap_for_bind unmaps a transient chunk so a draw can
// read from it. D3D11.0 forbids draws while a bound resource is mapped, so the
// `apply_uniform_at` path Unmaps the chunk before the bind+draw and lazily
// re-Maps via `d3d11_transient_chunk_ensure_mapped` on the next allocation.
d3d11_transient_chunk_unmap_for_bind :: proc(ctx: ^Context, buffer: Buffer) {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		return
	}
	info, ok := &state.buffers[buffer]
	if !ok || info.buffer == nil || !info.transient_mapped {
		return
	}
	state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)info.buffer, 0)
	info.transient_mapped = false
	info.transient_mapped_ptr = nil
}

// d3d11_transient_chunk_ensure_mapped re-Maps a transient chunk with
// WRITE_NO_OVERWRITE so the caller can keep handing out CPU pointers without
// discarding previously written contents.
d3d11_transient_chunk_ensure_mapped :: proc(ctx: ^Context, buffer: Buffer) -> (rawptr, bool) {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		return nil, false
	}
	info, ok := &state.buffers[buffer]
	if !ok || info.buffer == nil {
		return nil, false
	}
	if info.transient_mapped {
		return info.transient_mapped_ptr, true
	}
	mapped: d3d11.MAPPED_SUBRESOURCE
	hr := state.immediate.Map(state.immediate, cast(^d3d11.IResource)info.buffer, 0, .WRITE_NO_OVERWRITE, {}, &mapped)
	if d3d11_failed(hr) || mapped.pData == nil {
		set_backend_error(ctx, "gfx.d3d11: failed to remap transient chunk for write")
		return nil, false
	}
	info.transient_mapped = true
	info.transient_mapped_ptr = mapped.pData
	return mapped.pData, true
}

d3d11_destroy_transient_chunk :: proc(ctx: ^Context, buffer: Buffer) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if info, ok := state.buffers[buffer]; ok {
		if info.buffer != nil {
			if state.immediate != nil && info.transient_mapped {
				state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)info.buffer, 0)
			}
			info.buffer.Release(info.buffer)
		}
		delete_key(&state.buffers, buffer)
	}

	release_resource_id(&ctx.buffer_pool, u64(buffer))
}

d3d11_reset_transient_chunk :: proc(ctx: ^Context, buffer: Buffer) -> (rawptr, bool) {
	state := d3d11_state(ctx)
	if state == nil || state.immediate == nil {
		set_backend_error(ctx, "gfx.d3d11: backend state is not initialized")
		return nil, false
	}

	info, ok := &state.buffers[buffer]
	if !ok || info.buffer == nil {
		set_invalid_handle_error(ctx, "gfx.d3d11: transient chunk handle is unknown")
		return nil, false
	}

	if info.transient_mapped {
		state.immediate.Unmap(state.immediate, cast(^d3d11.IResource)info.buffer, 0)
	}

	mapped: d3d11.MAPPED_SUBRESOURCE
	hr := state.immediate.Map(state.immediate, cast(^d3d11.IResource)info.buffer, 0, .WRITE_DISCARD, {}, &mapped)
	if d3d11_failed(hr) || mapped.pData == nil {
		info.transient_mapped = false
		info.transient_mapped_ptr = nil
		set_backend_error(ctx, "gfx.d3d11: failed to remap transient chunk on reset")
		return nil, false
	}

	info.transient_mapped = true
	info.transient_mapped_ptr = mapped.pData
	return mapped.pData, true
}

@(private)
d3d11_transient_role_flags :: proc(role: Transient_Usage) -> (d3d11.BIND_FLAGS, Buffer_Usage, bool) {
	switch role {
	case .Uniform:
		return {.CONSTANT_BUFFER}, {.Uniform, .Stream_Update}, true
	case .Vertex:
		return {.VERTEX_BUFFER}, {.Vertex, .Stream_Update}, true
	case .Index:
		return {.INDEX_BUFFER}, {.Index, .Stream_Update}, true
	case .Storage, .Indirect:
		return {}, {}, false
	}
	return {}, {}, false
}

@(private)
d3d11_transient_role_label :: proc(role: Transient_Usage) -> string {
	switch role {
	case .Uniform:
		return "transient uniform"
	case .Storage:
		return "transient storage"
	case .Vertex:
		return "transient vertex"
	case .Index:
		return "transient index"
	case .Indirect:
		return "transient indirect"
	}
	return "transient"
}
