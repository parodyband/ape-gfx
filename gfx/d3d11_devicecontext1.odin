#+private
package gfx

import d3d11 "vendor:directx/d3d11"

// Minimal binding for ID3D11DeviceContext1.
//
// The Odin vendor:directx/d3d11 binding does not expose ID3D11DeviceContext1,
// so we redeclare just enough of its vtable to call the *SetConstantBuffers1
// methods used by `apply_uniform_at` (APE-21). The vtable layout extends
// IDeviceContext_VTable with the IDeviceContext1 entries up to the constant
// buffer setters; methods past that point are never called and so are not
// declared.
//
// Acquired once via QueryInterface at backend init; absent on platforms /
// drivers that do not expose the interface (the SetConstantBuffers1 path
// requires a runtime that supports it). Callers must check `state.context1`
// before using it.

@(private)
ID3D11DeviceContext1_UUID := &d3d11.IID{0xbb2c6faa, 0xb5fb, 0x4082, {0x8e, 0x6b, 0x38, 0x8b, 0x8c, 0xfa, 0x90, 0xe1}}

@(private)
D3D11_DeviceContext1 :: struct #raw_union {
	#subtype id3d11devicecontext: d3d11.IDeviceContext,
	using id3d11devicecontext1_vtable: ^D3D11_DeviceContext1_VTable,
}

@(private)
D3D11_DeviceContext1_VTable :: struct {
	using id3d11devicecontext_vtable: d3d11.IDeviceContext_VTable,

	// IDeviceContext1 additions, in vtable order. Methods we never call are
	// declared as `rawptr` to keep the layout right-sized without pulling in
	// their full signatures.
	CopySubresourceRegion1: rawptr,
	UpdateSubresource1:     rawptr,
	DiscardResource:        rawptr,
	DiscardView:            rawptr,
	VSSetConstantBuffers1:  proc "system" (this: ^D3D11_DeviceContext1, StartSlot: u32, NumBuffers: u32, ppConstantBuffers: [^]^d3d11.IBuffer, pFirstConstant: [^]u32, pNumConstants: [^]u32),
	HSSetConstantBuffers1:  rawptr,
	DSSetConstantBuffers1:  rawptr,
	GSSetConstantBuffers1:  rawptr,
	PSSetConstantBuffers1:  proc "system" (this: ^D3D11_DeviceContext1, StartSlot: u32, NumBuffers: u32, ppConstantBuffers: [^]^d3d11.IBuffer, pFirstConstant: [^]u32, pNumConstants: [^]u32),
	CSSetConstantBuffers1:  proc "system" (this: ^D3D11_DeviceContext1, StartSlot: u32, NumBuffers: u32, ppConstantBuffers: [^]^d3d11.IBuffer, pFirstConstant: [^]u32, pNumConstants: [^]u32),
}

@(private)
d3d11_acquire_context1 :: proc(state: ^D3D11_State) {
	if state == nil || state.immediate == nil || state.context1 != nil {
		return
	}

	context1_raw: rawptr
	hr := state.immediate.QueryInterface(cast(^d3d11.IUnknown)state.immediate, ID3D11DeviceContext1_UUID, &context1_raw)
	if d3d11_failed(hr) || context1_raw == nil {
		return
	}

	state.context1 = cast(^D3D11_DeviceContext1)context1_raw
}
