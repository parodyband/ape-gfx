package main

import "core:fmt"
import gfx "ape:gfx"

main :: proc() {
	desc := gfx.Desc {
		backend = .Null,
		width = 1280,
		height = 720,
		debug = true,
		label = "ape smoke",
	}

	ctx, ok := gfx.init(desc)
	if !ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		return
	}
	defer gfx.shutdown(&ctx)

	action := gfx.default_pass_action()
	action.colors[0].clear_value = gfx.Color{r = 0.06, g = 0.08, b = 0.11, a = 1}

	pass := gfx.Pass_Desc {
		label = "smoke clear",
		action = action,
	}

	if !gfx.begin_pass(&ctx, pass) {
		fmt.eprintln("begin_pass failed: ", gfx.last_error(&ctx))
		return
	}

	if !gfx.end_pass(&ctx) {
		fmt.eprintln("end_pass failed: ", gfx.last_error(&ctx))
		return
	}

	if !gfx.commit(&ctx) {
		fmt.eprintln("commit failed: ", gfx.last_error(&ctx))
		return
	}

	fmt.println("gfx smoke frame completed on backend: ", gfx.backend_name(gfx.query_features(&ctx).backend))
}
