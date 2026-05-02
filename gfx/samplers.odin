package gfx

// create_sampler creates immutable texture sampling state.
// On failure, the returned handle is Sampler_Invalid and last_error explains why.
create_sampler :: proc(ctx: ^Context, desc: Sampler_Desc) -> (Sampler, bool) {
	if !require_initialized(ctx, "gfx.create_sampler") {
		return Sampler_Invalid, false
	}

	if !validate_sampler_desc(ctx, desc) {
		return Sampler_Invalid, false
	}

	handle_id := alloc_resource_id(ctx, &ctx.sampler_pool, "gfx.create_sampler")
	if handle_id == 0 {
		return Sampler_Invalid, false
	}

	handle := Sampler(handle_id)
	if !backend_create_sampler(ctx, handle, desc) {
		cancel_resource_id(&ctx.sampler_pool, handle_id)
		return Sampler_Invalid, false
	}

	return handle, true
}

// destroy_sampler releases a live sampler handle.
destroy_sampler :: proc(ctx: ^Context, sampler: Sampler) {
	if !require_initialized(ctx, "gfx.destroy_sampler") {
		return
	}
	if !require_resource(ctx, &ctx.sampler_pool, u64(sampler), "gfx.destroy_sampler", "sampler") {
		return
	}
	if message := sampler_blocked_from_destroy(ctx, sampler); message != "" {
		set_validation_error(ctx, message)
		return
	}

	backend_destroy_sampler(ctx, sampler)
	release_resource_id(&ctx.sampler_pool, u64(sampler))
}

@(private)
validate_sampler_desc :: proc(ctx: ^Context, desc: Sampler_Desc) -> bool {
	if !filter_valid(desc.min_filter) {
		set_validation_error(ctx, "gfx.create_sampler: min_filter is invalid")
		return false
	}
	if !filter_valid(desc.mag_filter) {
		set_validation_error(ctx, "gfx.create_sampler: mag_filter is invalid")
		return false
	}
	if !filter_valid(desc.mip_filter) {
		set_validation_error(ctx, "gfx.create_sampler: mip_filter is invalid")
		return false
	}
	if !wrap_valid(desc.wrap_u) {
		set_validation_error(ctx, "gfx.create_sampler: wrap_u is invalid")
		return false
	}
	if !wrap_valid(desc.wrap_v) {
		set_validation_error(ctx, "gfx.create_sampler: wrap_v is invalid")
		return false
	}
	if !wrap_valid(desc.wrap_w) {
		set_validation_error(ctx, "gfx.create_sampler: wrap_w is invalid")
		return false
	}
	if !sampler_compare_func_valid(desc.compare) {
		set_validation_error(ctx, "gfx.create_sampler: compare is invalid")
		return false
	}

	return true
}

@(private)
filter_valid :: proc(value: Filter) -> bool {
	switch value {
	case .Nearest, .Linear:
		return true
	}

	return false
}


@(private)
wrap_valid :: proc(value: Wrap) -> bool {
	switch value {
	case .Repeat, .Clamp_To_Edge, .Mirrored_Repeat:
		return true
	}

	return false
}

@(private)
sampler_compare_func_valid :: proc(value: Compare_Func) -> bool {
	switch value {
	case .Always, .Never, .Less, .Less_Equal, .Equal, .Greater_Equal, .Greater, .Not_Equal:
		return true
	}

	return false
}
