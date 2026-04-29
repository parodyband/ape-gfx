package gfx

// create_buffer creates a GPU buffer and reports whether creation succeeded.
// On failure, the returned handle is Buffer_Invalid and last_error explains why.
create_buffer :: proc(ctx: ^Context, desc: Buffer_Desc) -> (Buffer, bool) {
	if !require_initialized(ctx, "gfx.create_buffer") {
		return Buffer_Invalid, false
	}

	desc := desc
	if !validate_buffer_desc(ctx, &desc) {
		return Buffer_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.buffer_pool, "gfx.create_buffer")
	if handle_id == 0 {
		return Buffer_Invalid, false
	}

	handle := Buffer(handle_id)
	if !backend_create_buffer(ctx, handle, desc) {
		cancel_resource_id(&ctx.buffer_pool, handle_id)
		return Buffer_Invalid, false
	}

	return handle, true
}

// destroy_buffer releases a live buffer handle.
destroy_buffer :: proc(ctx: ^Context, buffer: Buffer) {
	if !require_initialized(ctx, "gfx.destroy_buffer") {
		return
	}
	if !require_resource(ctx, &ctx.buffer_pool, u64(buffer), "gfx.destroy_buffer", "buffer") {
		return
	}

	backend_destroy_buffer(ctx, buffer)
	release_resource_id(&ctx.buffer_pool, u64(buffer))
}

// update_buffer writes CPU data into a Dynamic_Update or Stream_Update buffer.
update_buffer :: proc(ctx: ^Context, desc: Buffer_Update_Desc) -> bool {
	buffer_state, ok := validate_buffer_transfer(ctx, "gfx.update_buffer", desc.buffer, desc.offset, desc.data)
	if !ok {
		return false
	}

	if !(.Dynamic_Update in buffer_state.usage) && !(.Stream_Update in buffer_state.usage) {
		set_validation_error(ctx, "gfx.update_buffer: buffer must use Dynamic_Update or Stream_Update")
		return false
	}

	return backend_update_buffer(ctx, desc)
}

// read_buffer synchronously copies GPU buffer data into CPU memory.
read_buffer :: proc(ctx: ^Context, desc: Buffer_Read_Desc) -> bool {
	_, ok := validate_buffer_transfer(ctx, "gfx.read_buffer", desc.buffer, desc.offset, desc.data)
	if !ok {
		return false
	}

	return backend_read_buffer(ctx, desc)
}

// query_buffer_state returns read-only state for a live buffer, or zero if invalid.
query_buffer_state :: proc(ctx: ^Context, buffer: Buffer) -> Buffer_State {
	if ctx == nil || !ctx.initialized || !resource_id_alive(ctx, &ctx.buffer_pool, u64(buffer)) {
		return {}
	}

	return backend_query_buffer_state(ctx, buffer)
}

@(private)
validate_buffer_desc :: proc(ctx: ^Context, desc: ^Buffer_Desc) -> bool {
	if desc == nil {
		set_validation_error(ctx, "gfx.create_buffer: descriptor is nil")
		return false
	}

	if !validate_optional_range(ctx, "gfx.create_buffer", "data", desc.data) {
		return false
	}

	if desc.size == 0 && desc.data.size > 0 {
		desc.size = desc.data.size
	}
	if desc.size <= 0 {
		set_validation_error(ctx, "gfx.create_buffer: size must be positive or inferred from initial data")
		return false
	}
	if range_has_data(desc.data) && desc.data.size < desc.size {
		set_validation_error(ctx, "gfx.create_buffer: initial data range must cover Buffer_Desc.size")
		return false
	}

	role_count := buffer_usage_role_count(desc.usage)
	if role_count == 0 {
		set_validation_error(ctx, "gfx.create_buffer: usage must include at least one role flag")
		return false
	}

	update_count := buffer_usage_update_count(desc.usage)
	if update_count == 0 && !(.Storage in desc.usage) {
		set_validation_error(ctx, "gfx.create_buffer: usage must include Immutable, Dynamic_Update, or Stream_Update")
		return false
	}
	if update_count > 1 {
		set_validation_error(ctx, "gfx.create_buffer: usage has conflicting update/lifetime flags")
		return false
	}
	if .Storage in desc.usage && update_count > 0 {
		set_validation_error(ctx, "gfx.create_buffer: storage buffers are GPU-only for now and must not use update/lifetime flags")
		return false
	}
	if .Immutable in desc.usage && !range_has_data(desc.data) {
		set_validation_error(ctx, "gfx.create_buffer: immutable buffers require initial data")
		return false
	}

	if desc.storage_stride < 0 {
		set_validation_error(ctx, "gfx.create_buffer: storage_stride must be non-negative")
		return false
	}
	if desc.storage_stride > 0 {
		if !(.Storage in desc.usage) {
			set_validation_error(ctx, "gfx.create_buffer: storage_stride requires Storage usage")
			return false
		}
		if desc.storage_stride % 4 != 0 {
			set_validation_error(ctx, "gfx.create_buffer: storage_stride must be 4-byte aligned")
			return false
		}
		if desc.size % desc.storage_stride != 0 {
			set_validation_error(ctx, "gfx.create_buffer: structured storage buffer size must be a multiple of storage_stride")
			return false
		}
	} else if .Storage in desc.usage && desc.size % 4 != 0 {
		set_validation_error(ctx, "gfx.create_buffer: raw storage buffer size must be 4-byte aligned")
		return false
	}

	return true
}

@(private)
buffer_usage_role_count :: proc(usage: Buffer_Usage) -> int {
	count := 0
	if .Vertex in usage {
		count += 1
	}
	if .Index in usage {
		count += 1
	}
	if .Uniform in usage {
		count += 1
	}
	if .Storage in usage {
		count += 1
	}
	return count
}

@(private)
buffer_usage_update_count :: proc(usage: Buffer_Usage) -> int {
	count := 0
	if .Immutable in usage {
		count += 1
	}
	if .Dynamic_Update in usage {
		count += 1
	}
	if .Stream_Update in usage {
		count += 1
	}
	return count
}

@(private)
validate_buffer_transfer :: proc(ctx: ^Context, op: string, buffer: Buffer, offset: int, data: Range) -> (Buffer_State, bool) {
	if !require_initialized(ctx, op) {
		return {}, false
	}

	if ctx.in_pass {
		set_validation_errorf(ctx, "%s: cannot transfer buffer data while a pass is in progress", op)
		return {}, false
	}

	if !require_resource(ctx, &ctx.buffer_pool, u64(buffer), op, "buffer") {
		return {}, false
	}

	if offset < 0 {
		set_validation_errorf(ctx, "%s: offset must be non-negative", op)
		return {}, false
	}

	if data.ptr == nil || data.size <= 0 {
		set_validation_errorf(ctx, "%s: data range is empty", op)
		return {}, false
	}

	buffer_state := query_buffer_state(ctx, buffer)
	if !buffer_state.valid {
		set_invalid_handle_errorf(ctx, "%s: buffer handle is invalid", op)
		return {}, false
	}

	if offset > buffer_state.size || data.size > buffer_state.size - offset {
		set_validation_errorf(ctx, "%s: range exceeds buffer size", op)
		return {}, false
	}

	return buffer_state, true
}
