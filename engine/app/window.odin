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

// framebuffer_size returns the drawable framebuffer size in physical pixels.
framebuffer_size :: proc(window: ^Window) -> (width: i32, height: i32) {
	if window == nil || window.handle == nil {
		return 0, 0
	}

	fb_width, fb_height := glfw.GetFramebufferSize(window.handle)
	return i32(fb_width), i32(fb_height)
}
