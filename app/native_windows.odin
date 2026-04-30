#+build windows

package app

import glfw "vendor:glfw"

// native_window_handle returns the Win32 HWND used by the D3D12 backend.
native_window_handle :: proc(window: ^Window) -> rawptr {
	if window == nil || window.handle == nil {
		return nil
	}

	return cast(rawptr)glfw.GetWin32Window(window.handle)
}
