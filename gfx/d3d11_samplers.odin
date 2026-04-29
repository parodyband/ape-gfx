#+private
package gfx

import d3d11 "vendor:directx/d3d11"

d3d11_create_sampler :: proc(ctx: ^Context, handle: Sampler, desc: Sampler_Desc) -> bool {
	state := d3d11_state(ctx)
	if state == nil || state.device == nil {
		set_backend_error(ctx, "gfx.d3d11: device is not initialized")
		return false
	}

	sampler_desc := d3d11.SAMPLER_DESC {
		Filter = d3d11_filter(desc.min_filter, desc.mag_filter, desc.mip_filter),
		AddressU = d3d11_wrap(desc.wrap_u),
		AddressV = d3d11_wrap(desc.wrap_v),
		AddressW = d3d11_wrap(desc.wrap_w),
		MipLODBias = 0,
		MaxAnisotropy = 1,
		ComparisonFunc = .ALWAYS,
		BorderColor = {0, 0, 0, 0},
		MinLOD = 0,
		MaxLOD = 3.4028234663852886e38,
	}

	native_sampler: ^d3d11.ISamplerState
	hr := state.device.CreateSamplerState(state.device, &sampler_desc, &native_sampler)
	if d3d11_failed(hr) {
		set_backend_error(ctx, "gfx.d3d11: CreateSamplerState failed")
		return false
	}
	d3d11_set_debug_name(cast(^d3d11.IDeviceChild)native_sampler, desc.label)

	state.samplers[handle] = D3D11_Sampler {
		sampler = native_sampler,
	}
	return true
}

d3d11_destroy_sampler :: proc(ctx: ^Context, handle: Sampler) {
	state := d3d11_state(ctx)
	if state == nil {
		return
	}

	if sampler_info, ok := state.samplers[handle]; ok {
		if sampler_info.sampler != nil {
			sampler_info.sampler.Release(sampler_info.sampler)
		}
		delete_key(&state.samplers, handle)
	}
}

d3d11_filter :: proc(min_filter, mag_filter, mip_filter: Filter) -> d3d11.FILTER {
	min_linear := min_filter == .Linear
	mag_linear := mag_filter == .Linear
	mip_linear := mip_filter == .Linear

	if min_linear {
		if mag_linear {
			if mip_linear {
				return .MIN_MAG_MIP_LINEAR
			}
			return .MIN_MAG_LINEAR_MIP_POINT
		}
		if mip_linear {
			return .MIN_LINEAR_MAG_POINT_MIP_LINEAR
		}
		return .MIN_LINEAR_MAG_MIP_POINT
	}

	if mag_linear {
		if mip_linear {
			return .MIN_POINT_MAG_MIP_LINEAR
		}
		return .MIN_POINT_MAG_LINEAR_MIP_POINT
	}
	if mip_linear {
		return .MIN_MAG_POINT_MIP_LINEAR
	}
	return .MIN_MAG_MIP_POINT
}

d3d11_wrap :: proc(wrap: Wrap) -> d3d11.TEXTURE_ADDRESS_MODE {
	switch wrap {
	case .Repeat:
		return .WRAP
	case .Clamp_To_Edge:
		return .CLAMP
	case .Mirrored_Repeat:
		return .MIRROR
	}

	return .WRAP
}
