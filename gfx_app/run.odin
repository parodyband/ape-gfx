package gfx_app

import "core:fmt"
import app "ape:app"
import gfx "ape:gfx"

// Frame_Info is passed to a Run_Desc.frame callback.
//
// `resized` is true on the first frame after the swapchain dimensions changed,
// so callers can rebuild size-dependent resources. `width` / `height` are the
// current render-target dimensions in pixels.
Frame_Info :: struct {
	index:   int,
	width:   i32,
	height:  i32,
	resized: bool,
}

// Run_Desc configures the gfx_app.run sample harness.
//
// The harness owns app.init/shutdown, window creation, gfx.init/shutdown, and
// the swapchain-resize / event-poll loop. It does NOT touch the recording
// model — callers still issue begin_pass / apply_pipeline / draw / end_pass /
// commit explicitly inside `frame`.
//
// This package is deliberately separate from `gfx`: production code is
// expected to drive gfx directly. The harness exists only to keep one-question
// samples from drowning in identical setup boilerplate.
Run_Desc :: struct {
	title:            cstring,
	width:            i32,
	height:           i32,
	gfx_label:        string,
	backend:          gfx.Backend,
	swapchain_format: gfx.Pixel_Format,
	vsync:            bool,
	debug:            bool,
	max_frames:       int, // 0 = run until window close
	user_data:        rawptr,
	init:             proc(ctx: ^gfx.Context, window: ^app.Window, user_data: rawptr) -> bool,
	frame:            proc(ctx: ^gfx.Context, window: ^app.Window, info: Frame_Info, user_data: rawptr) -> bool,
	shutdown:         proc(ctx: ^gfx.Context, user_data: rawptr),
}

// run hosts a sample's main loop. Returns true on clean exit.
run :: proc(desc: Run_Desc) -> bool {
	if desc.frame == nil {
		fmt.eprintln("gfx_app.run: frame callback is required")
		return false
	}

	if !app.init() {
		fmt.eprintln("gfx_app.run: app.init failed")
		return false
	}
	defer app.shutdown()

	width := desc.width
	if width <= 0 { width = 1280 }
	height := desc.height
	if height <= 0 { height = 720 }

	title := desc.title
	if title == nil { title = "Ape Sample" }

	window, win_ok := app.create_window({
		width         = width,
		height        = height,
		title         = title,
		no_client_api = true,
	})
	if !win_ok {
		fmt.eprintln("gfx_app.run: window creation failed")
		return false
	}
	defer app.destroy_window(&window)

	fb_width, fb_height := app.framebuffer_size(&window)

	backend := desc.backend
	if backend == .Auto {
		backend = .D3D11
	}
	swapchain_format := desc.swapchain_format
	if swapchain_format == .Invalid {
		swapchain_format = .BGRA8
	}
	gfx_label := desc.gfx_label
	if gfx_label == "" { gfx_label = string(title) }

	ctx, gfx_ok := gfx.init({
		backend          = backend,
		width            = fb_width,
		height           = fb_height,
		native_window    = app.native_window_handle(&window),
		swapchain_format = swapchain_format,
		vsync            = desc.vsync,
		debug            = desc.debug,
		label            = gfx_label,
	})
	if !gfx_ok {
		fmt.eprintln("gfx_app.run: gfx.init failed:", gfx.last_error(&ctx))
		return false
	}
	defer gfx.shutdown(&ctx)

	if desc.init != nil {
		if !desc.init(&ctx, &window, desc.user_data) {
			if desc.shutdown != nil {
				desc.shutdown(&ctx, desc.user_data)
			}
			return false
		}
	}
	defer if desc.shutdown != nil {
		desc.shutdown(&ctx, desc.user_data)
	}

	render_width := fb_width
	render_height := fb_height
	frame_index := 0
	for !app.should_close(&window) {
		app.poll_events()

		resize, resize_ok := resize_swapchain(&ctx, &window, &render_width, &render_height)
		if !resize_ok {
			fmt.eprintln("gfx_app.run: resize failed:", gfx.last_error(&ctx))
			return false
		}
		if !resize.active {
			continue
		}

		info := Frame_Info {
			index   = frame_index,
			width   = render_width,
			height  = render_height,
			resized = resize.resized,
		}
		if !desc.frame(&ctx, &window, info, desc.user_data) {
			return false
		}

		frame_index += 1
		if desc.max_frames > 0 && frame_index >= desc.max_frames {
			break
		}
	}

	return true
}
