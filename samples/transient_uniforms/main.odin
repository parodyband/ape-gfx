package main

import "core:fmt"
import app "ape:app"
import gfx "ape:gfx"
import gfx_app "ape:gfx_app"

// Sample: transient uniform allocator stress (APE-20).
//
// Allocates a large number of small uniform slices per frame from a
// `gfx.Transient_Allocator`, writes sentinel data through each slice's
// mapped pointer, and renders a clear pass that varies its color from
// the first slice's contents. Exercises:
//   - per-frame reset and bump-pointer rotation,
//   - 256-byte uniform alignment guarantees,
//   - capacity accounting (`transient_allocator_used`),
//   - ID3D12Buffer chunk re-`Map(WRITE_DISCARD)` on reset.

AUTO_EXIT_FRAMES :: #config(AUTO_EXIT_FRAMES, 0)

ALLOCS_PER_FRAME :: 256
ALLOC_PAYLOAD_BYTES :: 64 // smaller than 256 alignment so each alloc consumes a full uniform stride

Per_Slice_Uniforms :: struct {
	frame_index: u32,
	slice_index: u32,
	color:       [4]f32,
	_pad:        [12]f32,
}

Sample_State :: struct {
	allocator: gfx.Transient_Allocator,
	worst_used: int,
}

main :: proc() {
	state := Sample_State{}
	ok := gfx_app.run({
		title      = "Ape D3D12 Transient Uniforms",
		gfx_label  = "ape d3d12 transient uniforms",
		backend    = .D3D12,
		vsync      = true,
		debug      = true,
		max_frames = AUTO_EXIT_FRAMES,
		user_data  = &state,
		init       = sample_init,
		frame      = sample_frame,
		shutdown   = sample_shutdown,
	})
	if !ok {
		fmt.eprintln("transient_uniforms: gfx_app.run failed")
	}
}

sample_init :: proc(ctx: ^gfx.Context, window: ^app.Window, user_data: rawptr) -> bool {
	state := cast(^Sample_State)user_data

	// 256 KiB is plenty for ALLOCS_PER_FRAME * 256 alignment = 64 KiB working
	// set, leaves headroom to verify we are NOT capacity-bound under stress.
	allocator, ok := gfx.create_transient_allocator(ctx, {
		label    = "stress uniforms",
		capacity = 256 * 1024,
		usage    = {.Uniform},
	})
	if !ok {
		fmt.eprintln("create_transient_allocator failed:", gfx.last_error(ctx))
		return false
	}
	state.allocator = allocator
	return true
}

sample_shutdown :: proc(ctx: ^gfx.Context, user_data: rawptr) {
	state := cast(^Sample_State)user_data
	if state.allocator != gfx.Transient_Allocator_Invalid {
		gfx.destroy_transient_allocator(ctx, state.allocator)
	}
	fmt.printf("transient allocator peak used: %d bytes\n", state.worst_used)
}

sample_frame :: proc(ctx: ^gfx.Context, window: ^app.Window, info: gfx_app.Frame_Info, user_data: rawptr) -> bool {
	state := cast(^Sample_State)user_data

	if !gfx.reset_transient_allocator(ctx, state.allocator, {gfx.Timeline_Semaphore_Invalid, 0}) {
		fmt.eprintln("reset_transient_allocator failed:", gfx.last_error(ctx))
		return false
	}

	first_color := [4]f32{0.04, 0.08, 0.13, 1.0}
	prev_offset := -1

	for i in 0 ..< ALLOCS_PER_FRAME {
		slice, ok := gfx.transient_alloc(state.allocator, ALLOC_PAYLOAD_BYTES, .Uniform)
		if !ok {
			fmt.eprintln("transient_alloc failed at index", i)
			return false
		}
		if slice.offset % gfx.TRANSIENT_UNIFORM_ALIGNMENT != 0 {
			fmt.eprintln("alignment broken at index", i, "offset", slice.offset)
			return false
		}
		if slice.size % gfx.TRANSIENT_UNIFORM_ALIGNMENT != 0 {
			fmt.eprintln("size not aligned at index", i, "size", slice.size)
			return false
		}
		if slice.offset <= prev_offset {
			fmt.eprintln("bump pointer regressed at index", i)
			return false
		}
		prev_offset = slice.offset

		t := f32(i) / f32(ALLOCS_PER_FRAME - 1)
		color := [4]f32{0.04 + 0.18 * t, 0.08, 0.13 + 0.18 * (1.0 - t), 1.0}
		(^Per_Slice_Uniforms)(slice.mapped)^ = {
			frame_index = u32(info.index),
			slice_index = u32(i),
			color       = color,
		}

		if i == 0 {
			first_color = color
		}
	}

	used := gfx.transient_allocator_used(state.allocator)
	if used > state.worst_used {
		state.worst_used = used
	}
	expected_min := ALLOCS_PER_FRAME * gfx.TRANSIENT_UNIFORM_ALIGNMENT
	if used < expected_min {
		fmt.eprintln("transient_allocator_used too low:", used, "expected at least", expected_min)
		return false
	}

	clear_color := gfx.Color {
		r = first_color[0],
		g = first_color[1],
		b = first_color[2],
		a = first_color[3],
	}
	if !gfx.begin_pass(ctx, {
		label  = "transient uniforms clear",
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
