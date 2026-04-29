package app

import "core:c"
import glfw "vendor:glfw"

// Window wraps the native window handle used by samples and graphics backends.
Window :: struct {
	handle: glfw.WindowHandle,
	width: i32,
	height: i32,
	title: cstring,
}

// Window_Desc configures a GLFW-backed desktop window.
Window_Desc :: struct {
	width: i32,
	height: i32,
	title: cstring,
	no_client_api: bool,
}

// Key names the small set of keyboard inputs exposed by the sample app layer.
Key :: enum c.int {
	Escape = glfw.KEY_ESCAPE,
	A      = glfw.KEY_A,
	C      = glfw.KEY_C,
	D      = glfw.KEY_D,
	S      = glfw.KEY_S,
	W      = glfw.KEY_W,
	Left   = glfw.KEY_LEFT,
	Right  = glfw.KEY_RIGHT,
	Down   = glfw.KEY_DOWN,
	Up     = glfw.KEY_UP,
}

// Mouse_Button names the small set of mouse buttons exposed by the sample app layer.
Mouse_Button :: enum c.int {
	Left   = glfw.MOUSE_BUTTON_LEFT,
	Right  = glfw.MOUSE_BUTTON_RIGHT,
	Middle = glfw.MOUSE_BUTTON_MIDDLE,
}

@(private)
input_window: glfw.WindowHandle
@(private)
input_scroll_x: f64
@(private)
input_scroll_y: f64

// init initializes the app/window subsystem.
init :: proc() -> bool {
	return bool(glfw.Init())
}

// shutdown terminates the app/window subsystem.
shutdown :: proc() {
	glfw.Terminate()
}

// create_window creates a desktop window, defaulting invalid dimensions to 1280x720.
create_window :: proc(desc: Window_Desc) -> (Window, bool) {
	if desc.no_client_api {
		glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	}

	width := desc.width
	height := desc.height
	if width <= 0 {
		width = 1280
	}
	if height <= 0 {
		height = 720
	}

	title := desc.title
	if title == nil {
		title = "Ape"
	}

	handle := glfw.CreateWindow(c.int(width), c.int(height), title, nil, nil)
	if handle == nil {
		return {}, false
	}

	return Window {
		handle = handle,
		width = width,
		height = height,
		title = title,
	}, true
}

// destroy_window releases a live window handle.
destroy_window :: proc(window: ^Window) {
	if window == nil || window.handle == nil {
		return
	}

	if input_window == window.handle {
		input_window = nil
		input_scroll_x = 0
		input_scroll_y = 0
	}

	glfw.DestroyWindow(window.handle)
	window.handle = nil
}

// poll_events pumps pending platform window events.
poll_events :: proc() {
	glfw.PollEvents()
}

// should_close reports whether the user or platform requested window close.
should_close :: proc(window: ^Window) -> bool {
	if window == nil || window.handle == nil {
		return true
	}

	return bool(glfw.WindowShouldClose(window.handle))
}

// request_close asks the platform window to close on the next loop iteration.
request_close :: proc(window: ^Window) {
	if window == nil || window.handle == nil {
		return
	}

	glfw.SetWindowShouldClose(window.handle, glfw.TRUE)
}

// framebuffer_size returns the drawable framebuffer size in physical pixels.
framebuffer_size :: proc(window: ^Window) -> (width: i32, height: i32) {
	if window == nil || window.handle == nil {
		return 0, 0
	}

	fb_width, fb_height := glfw.GetFramebufferSize(window.handle)
	return i32(fb_width), i32(fb_height)
}

// begin_input_frame prepares per-frame input state before poll_events.
begin_input_frame :: proc(window: ^Window) {
	if window == nil || window.handle == nil {
		return
	}

	if input_window != window.handle {
		glfw.SetScrollCallback(window.handle, input_scroll_callback)
		input_window = window.handle
	}

	input_scroll_x = 0
	input_scroll_y = 0
}

// key_down reports whether a keyboard key is currently pressed.
key_down :: proc(window: ^Window, key: Key) -> bool {
	if window == nil || window.handle == nil {
		return false
	}

	return glfw.GetKey(window.handle, c.int(key)) == glfw.PRESS
}

// mouse_button_down reports whether a mouse button is currently pressed.
mouse_button_down :: proc(window: ^Window, button: Mouse_Button) -> bool {
	if window == nil || window.handle == nil {
		return false
	}

	return glfw.GetMouseButton(window.handle, c.int(button)) == glfw.PRESS
}

// cursor_position returns the cursor position in window coordinates.
cursor_position :: proc(window: ^Window) -> (x, y: f64) {
	if window == nil || window.handle == nil {
		return 0, 0
	}

	return glfw.GetCursorPos(window.handle)
}

// scroll_delta returns the accumulated mouse-wheel delta for the current input frame.
scroll_delta :: proc(window: ^Window) -> (x, y: f64) {
	if window == nil || window.handle == nil {
		return 0, 0
	}
	if window.handle != input_window {
		return 0, 0
	}

	return input_scroll_x, input_scroll_y
}

@(private)
input_scroll_callback :: proc "c" (handle: glfw.WindowHandle, xoffset, yoffset: f64) {
	if handle != input_window {
		return
	}

	input_scroll_x += xoffset
	input_scroll_y += yoffset
}
