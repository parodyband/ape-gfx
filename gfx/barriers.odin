package gfx

// Barrier addressing API sketch — AAA roadmap item 19 / APE-15.
//
// This file is a header-only stub. Every entry point panics. The shapes here
// reflect the decision in docs/private/gfx-barriers-note.md §10 (barriers
// name resources, not views, render targets, or pass aliases) and compose
// with:
//
//   gfx-barriers-note.md §9   — hybrid model (auto inside a pass, explicit
//                               between passes/queues).
//   gfx-barriers-note.md §10  — barrier addressing scheme (this file).
//   gfx-command-recording-note.md §7 — per-list error slot; `cmd_barrier`
//                               records into it on validation failure.
//   queue.odin                — cross-queue ownership transfer verbs land
//                               in APE-21; they reuse `Barrier_Target` and
//                               `Subresource_Range` so the addressing scheme
//                               stays uniform across barrier and handoff.
//
// `Resource_Usage` lives in types.odin and supplies the from/to vocabulary.
// `Subresource_Aspect` is duplicated nowhere — it is the only aspect type in
// the public API.

// Subresource_Aspect_Flag selects which planes of an image a barrier names.
//
// Color images carry only the `Color` aspect. Depth-only formats carry only
// `Depth`. Combined depth/stencil formats (e.g. `D24S8`) carry both `Depth`
// and `Stencil`; the two planes can transition independently on Vulkan
// (`VK_IMAGE_ASPECT_DEPTH_BIT` vs `VK_IMAGE_ASPECT_STENCIL_BIT`) and on
// D3D12 (separate states are not addressable, but separate barriers are).
Subresource_Aspect_Flag :: enum {
	Color,
	Depth,
	Stencil,
}

// Subresource_Aspect is a bit set of `Subresource_Aspect_Flag` values.
//
// A zero-init (`{}`) bit set means "every aspect the resource owns" — color
// for color formats, depth for depth-only formats, depth and stencil for
// combined formats. Naming aspects explicitly is only required when a
// transition must move depth and stencil through different states or in
// different barriers (§10.4 of the barriers note).
Subresource_Aspect :: bit_set[Subresource_Aspect_Flag; u32]

// Subresource_Range names a contiguous range of mip levels and array layers
// within an image, plus the aspects to transition.
//
// Zero-init means "the whole image": all mip levels, all array layers, every
// aspect. The runtime fills the zero counts from the image's `mip_count` and
// `array_count` at barrier emission time. This matches the zero-count default
// already used by `Image_Desc` (AAA roadmap item 34).
//
// Buffers do not use `Subresource_Range` today; whole-buffer transitions are
// the only shape on the roadmap. When sparse buffers or buffer suballocators
// arrive, this struct grows a buffer-range variant or a sibling struct does;
// `Barrier_Target.range` keeps its current shape for images.
//
// Field semantics:
//
//   base_mip      — first mip level. 0 is valid and common.
//   mip_count     — number of mip levels. 0 means "from base_mip to the last
//                   mip" (the all-mips default).
//   base_layer    — first array layer (0 for non-array images).
//   layer_count   — number of array layers. 0 means "from base_layer to the
//                   last layer".
//   aspect        — image planes (see `Subresource_Aspect`). `{}` means
//                   every aspect the resource owns.
Subresource_Range :: struct {
	base_mip:    u32,
	mip_count:   u32,
	base_layer:  u32,
	layer_count: u32,
	aspect:      Subresource_Aspect,
}

// SUBRESOURCE_RANGE_WHOLE is the explicit name for the zero-init "whole
// resource" range. Functionally identical to `Subresource_Range{}`; preferred
// at call sites that read more clearly with a name than with `{}`.
SUBRESOURCE_RANGE_WHOLE :: Subresource_Range{}

// Barrier_Target_Kind tags which resource handle a `Barrier_Target` carries.
//
// The default zero value is `Image` so a zero-init `Barrier_Target` plus a
// nonzero `image` field reads as a "whole image" transition without an
// explicit kind setter. Construction helpers (`barrier_image_target`,
// `barrier_buffer_target`) populate the tag and the matching handle in one
// step.
Barrier_Target_Kind :: enum {
	Image,
	Buffer,
}

// Barrier_Target names the addressee of one explicit barrier transition.
//
// Barriers always name resources (Image / Buffer handles) — never views,
// render-target aggregates, or pass-resource aliases. See barriers-note §10
// for the rejected alternatives. `range` is meaningful only when
// `kind == .Image`; for buffers it is ignored and zero-init.
//
// Swapchain images are named by their `Image` handle, like any other image.
// The typical `Color_Target -> Present` move rides the §9.4 attachment
// auto-path and never appears here; use `cmd_barrier` only when the swapchain
// image is touched in a non-attachment role.
//
// Transient/aliased resources (frame-graph style "the color target of pass
// X") are explicitly out of scope; a future render-graph layer will project
// onto this same `Barrier_Target` shape (§10.5 of the note).
Barrier_Target :: struct {
	kind:   Barrier_Target_Kind,
	image:  Image,
	buffer: Buffer,
	range:  Subresource_Range,
}

// Image_Transition names one image-side state move.
//
// `range` defaults to `SUBRESOURCE_RANGE_WHOLE`; non-zero fields restrict the
// move to a subresource (mip range, layer range, or a specific aspect). The
// runtime widens the range to "all aspects of this image" when the bit set
// is empty — so a depth-only or color-only image needs no explicit aspect.
//
// `from` and `to` use `Resource_Usage` from types.odin. Validation rules
// (item 20 / APE-16) own which `from -> to` pairs are legal on which
// backends.
Image_Transition :: struct {
	image: Image,
	range: Subresource_Range,
	from:  Resource_Usage,
	to:    Resource_Usage,
}

// Buffer_Transition names one buffer-side state move.
//
// Buffers always transition whole-resource today; `Subresource_Range` is not
// part of the buffer transition shape. When sparse / suballocated buffer
// states arrive, the new range field lands here without changing the verb
// signature.
Buffer_Transition :: struct {
	buffer: Buffer,
	from:   Resource_Usage,
	to:     Resource_Usage,
}

// Barrier_Desc is the description for one `cmd_barrier` call.
//
// Both arrays may be empty (the call no-ops); both may be populated (one
// barrier per record on Vulkan / D3D12, freely batched). Arrays are read by
// the runtime during the call and may be reused or freed immediately after.
//
// Future fields (deferred):
//
//   - queue ownership transfer (release / acquire) — APE-21.
//   - memory-only barriers without a state move — covered today by the
//     in-pass UAV auto-path (§9.1, case 4.5); a public verb is not on the
//     roadmap.
Barrier_Desc :: struct {
	image_transitions:  []Image_Transition,
	buffer_transitions: []Buffer_Transition,
}

// barrier_image_target builds a `Barrier_Target` for an image and range.
//
// Pass `SUBRESOURCE_RANGE_WHOLE` (or `{}`) for whole-resource transitions.
barrier_image_target :: proc(image: Image, range: Subresource_Range = SUBRESOURCE_RANGE_WHOLE) -> Barrier_Target {
	return Barrier_Target{
		kind  = .Image,
		image = image,
		range = range,
	}
}

// barrier_buffer_target builds a `Barrier_Target` for a whole-buffer
// transition.
barrier_buffer_target :: proc(buffer: Buffer) -> Barrier_Target {
	return Barrier_Target{
		kind   = .Buffer,
		buffer = buffer,
	}
}

// cmd_barrier records one set of explicit transitions on a Command_List.
//
// Recorded between encoder scopes (§9.2 of the barriers note); calling it
// while a `Render_Pass_Encoder` or `Compute_Pass_Encoder` is open is a
// validation error. The runtime emits one backend barrier record
// (`vkCmdPipelineBarrier2` / `ResourceBarrier`) covering all transitions in
// `desc`; D3D11 routes through the item-20 validation policy and otherwise
// no-ops.
//
// Returns false on validation/backend failure; per-list error follows
// recording-note §7.3.
cmd_barrier :: proc(list: ^Command_List, desc: Barrier_Desc) -> bool {
	panic("gfx.cmd_barrier: unimplemented (APE-15 sketch only)")
}
