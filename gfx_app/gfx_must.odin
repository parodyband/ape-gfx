package gfx_app

import "core:fmt"
import "core:os"
import app "ape:app"
import gfx "ape:gfx"

must :: proc(ok: bool, message: string) {
	if ok {
		return
	}
	fmt.eprintln(message)
	os.exit(1)
}

must_gfx :: proc(ctx: ^gfx.Context, ok: bool, message: string) {
	if ok {
		return
	}
	fmt.eprintln(message, ": ", gfx.last_error(ctx))
	os.exit(1)
}

must_create_window :: proc(desc: app.Window_Desc) -> app.Window {
	window, ok := app.create_window(desc)
	must(ok, "window creation failed")
	return window
}

must_init_gfx :: proc(desc: gfx.Desc) -> gfx.Context {
	ctx, ok := gfx.init(desc)
	must_gfx(&ctx, ok, "gfx init failed")
	return ctx
}

must_create_image :: proc(ctx: ^gfx.Context, desc: gfx.Image_Desc) -> gfx.Image {
	image, ok := gfx.create_image(ctx, desc)
	must_gfx(ctx, ok, "image creation failed")
	return image
}

must_create_view :: proc(ctx: ^gfx.Context, desc: gfx.View_Desc) -> gfx.View {
	view, ok := gfx.create_view(ctx, desc)
	must_gfx(ctx, ok, "view creation failed")
	return view
}

must_create_render_target :: proc(ctx: ^gfx.Context, desc: gfx.Render_Target_Desc) -> gfx.Render_Target {
	target, ok := gfx.create_render_target(ctx, desc)
	must_gfx(ctx, ok, "render target creation failed")
	return target
}

must_create_sampler :: proc(ctx: ^gfx.Context, desc: gfx.Sampler_Desc) -> gfx.Sampler {
	sampler, ok := gfx.create_sampler(ctx, desc)
	must_gfx(ctx, ok, "sampler creation failed")
	return sampler
}

must_create_buffer :: proc(ctx: ^gfx.Context, desc: gfx.Buffer_Desc) -> gfx.Buffer {
	buffer, ok := gfx.create_buffer(ctx, desc)
	must_gfx(ctx, ok, "buffer creation failed")
	return buffer
}

must_load_shader_program :: proc(ctx: ^gfx.Context, desc: Shader_Program_Desc) -> Shader_Program {
	program, ok := shader_program_load(ctx, desc)
	if !ok {
		os.exit(1)
	}
	return program
}

must_resize_swapchain :: proc(ctx: ^gfx.Context, window: ^app.Window, render_width, render_height: ^i32) -> Resize_Result {
	resize, ok := resize_swapchain(ctx, window, render_width, render_height)
	must_gfx(ctx, ok, "resize failed")
	return resize
}

begin_pass :: proc(ctx: ^gfx.Context, desc: gfx.Pass_Desc) {
	must_gfx(ctx, gfx.begin_pass(ctx, desc), "begin_pass failed")
}

end_pass :: proc(ctx: ^gfx.Context) {
	must_gfx(ctx, gfx.end_pass(ctx), "end_pass failed")
}

commit :: proc(ctx: ^gfx.Context) {
	must_gfx(ctx, gfx.commit(ctx), "commit failed")
}

apply_pipeline :: proc(ctx: ^gfx.Context, pipeline: gfx.Pipeline) {
	must_gfx(ctx, gfx.apply_pipeline(ctx, pipeline), "apply_pipeline failed")
}

apply_bindings :: proc(ctx: ^gfx.Context, bindings: gfx.Bindings) {
	must_gfx(ctx, gfx.apply_bindings(ctx, bindings), "apply_bindings failed")
}

draw :: proc(ctx: ^gfx.Context, base_element, element_count: i32) {
	must_gfx(ctx, gfx.draw(ctx, base_element, element_count), "draw failed")
}
