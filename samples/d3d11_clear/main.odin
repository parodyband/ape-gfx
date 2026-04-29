package main

import "core:fmt"
import app "ape:app"
import gfx "ape:gfx"
import gfx_app "ape:gfx_app"

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)

main :: proc() {
	ok := gfx_app.run({
		title      = "Ape D3D11 Clear",
		gfx_label  = "ape d3d11 clear",
		backend    = .D3D11,
		vsync      = true,
		debug      = true,
		max_frames = AUTO_EXIT_FRAMES,
		frame      = clear_frame,
	})
	if !ok {
		fmt.eprintln("d3d11_clear: gfx_app.run failed")
	}
}

clear_frame :: proc(ctx: ^gfx.Context, window: ^app.Window, info: gfx_app.Frame_Info, user_data: rawptr) -> bool {
	t := f32(info.index % 240) / 239.0
	clear_color := gfx.Color {
		r = 0.04 + 0.18 * t,
		g = 0.08,
		b = 0.13 + 0.18 * (1.0 - t),
		a = 1,
	}

	if !gfx.begin_pass(ctx, {
		label = "main clear",
		action = {colors = {0 = {clear_value = clear_color}}},
	}) {
		fmt.eprintln("begin_pass failed:", gfx.last_error(ctx))
		return false
	}
	if !gfx.end_pass(ctx) {
		fmt.eprintln("end_pass failed:", gfx.last_error(ctx))
		return false
	}
	if !gfx.commit(ctx) {
		fmt.eprintln("commit failed:", gfx.last_error(ctx))
		return false
	}
	return true
}
