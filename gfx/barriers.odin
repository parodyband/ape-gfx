package gfx

import "core:fmt"

// Barrier API — AAA roadmap items 19 and 20 / APE-15 and APE-16.
//
// The shapes here reflect the decisions in
// docs/private/gfx-barriers-note.md §9 and §10:
//
//   §9   — hybrid model (auto inside a pass, explicit between passes/queues).
//   §10  — barrier addressing scheme (resource handle plus image
//          Subresource_Range; views, render-target aggregates, and
//          pass-resource aliases are rejected).
//
// `Resource_Usage` lives in types.odin and supplies the from/to vocabulary.
// `Subresource_Aspect` is the only aspect type in the public API.
//
// On the immediate-mode `Context` API (`gfx.barrier`), modern explicit
// backends use this schema to emit native barriers and to run the APE-16
// debug-build consistency check against the per-frame last-known-usage
// tracker on `Context`.
// `cmd_barrier(list, desc)` is the encoder-mode equivalent and returns
// Unsupported until the `Command_List` runtime lands in APE-5; both verbs
// share the same validator so the schema does not drift.

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
// `from` and `to` use `Resource_Usage` from types.odin. Validation (APE-16)
// owns which `from -> to` pairs are legal on which backends.
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

// Barrier_Desc is the description for one `cmd_barrier` / `barrier` call.
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

// barrier records one set of explicit transitions on a Context.
//
// The immediate-mode counterpart of `cmd_barrier`. Recorded outside any pass
// (calling between `begin_pass` / `end_pass` is a validation error). The
// runtime emits one backend barrier record on Vulkan / D3D12 covering all
// transitions in `desc`.
//
// Validation (APE-16):
//
//   - Always: handles valid, kind/handle agreement, ranges in bounds for the
//     resource, `from`/`to` in the `Resource_Usage` enum.
//   - Debug builds (`Desc.debug == true`): checks each transition's `from`
//     against the per-frame last-known declared usage of the resource. A
//     mismatch is reported as a wrong-barrier validation error. Successful
//     transitions update the tracker; the tracker is flushed at every
//     `commit`.
//
// On D3D12 the actual D3D12 call is a no-op; the validator is the entire
// observable behavior. The schema is the explicit one — D3D12 just has
// nothing to do with it (gfx-barriers-note.md §9.6).
//
// example:
//   gfx.barrier(&ctx, gfx.Barrier_Desc{
//       image_transitions = []gfx.Image_Transition{
//           {image = offscreen_color, from = .Color_Target, to = .Sampled},
//       },
//   })
barrier :: proc(ctx: ^Context, desc: Barrier_Desc) -> bool {
	if !require_initialized(ctx, "gfx.barrier") {
		return false
	}
	if ctx.in_pass {
		set_validation_error(ctx, "gfx.barrier: cannot record barriers while a pass is in progress")
		return false
	}
	if !validate_barrier_desc(ctx, desc, "gfx.barrier") {
		return false
	}
	if ctx.desc.debug {
		if !validate_barrier_against_tracker(ctx, desc, "gfx.barrier") {
			return false
		}
		record_barrier_into_tracker(ctx, desc)
	}
	return backend_barrier(ctx, desc)
}

// cmd_barrier records one set of explicit transitions on a Command_List.
//
// Recorded between encoder scopes (§9.2 of the barriers note); calling it
// while a `Render_Pass_Encoder` or `Compute_Pass_Encoder` is open is a
// validation error. The runtime emits one backend barrier record
// (`vkCmdPipelineBarrier2` / `ResourceBarrier`) covering all transitions in
// `desc`; D3D12 routes through the item-20 validation policy and otherwise
// no-ops.
//
// Returns false on validation/backend failure; per-list error follows
// recording-note §7.3.
cmd_barrier :: proc(list: ^Command_List, desc: Barrier_Desc) -> bool {
	return command_list_set_unsupported(list, "gfx.cmd_barrier: explicit command recording is not implemented yet")
}

@(private)
validate_barrier_desc :: proc(ctx: ^Context, desc: Barrier_Desc, op: string) -> bool {
	if len(desc.image_transitions) == 0 && len(desc.buffer_transitions) == 0 {
		return true
	}

	for transition, i in desc.image_transitions {
		if !image_valid(transition.image) {
			set_validation_errorf(ctx, "%s: image transition %d has an invalid image handle", op, i)
			return false
		}
		if !require_resource(ctx, &ctx.image_pool, u64(transition.image), op, "image transition") {
			return false
		}
		image_state := query_image_state(ctx, transition.image)
		if !image_state.valid {
			set_invalid_handle_errorf(ctx, "%s: image transition %d image handle is invalid", op, i)
			return false
		}
		if !validate_subresource_range(ctx, op, i, transition.range, image_state) {
			return false
		}
		if !resource_usage_legal_for_image(transition.from, image_state) {
			set_validation_errorf(ctx, "%s: image transition %d from=%v is not a legal image usage", op, i, transition.from)
			return false
		}
		if !resource_usage_legal_for_image(transition.to, image_state) {
			set_validation_errorf(ctx, "%s: image transition %d to=%v is not a legal image usage", op, i, transition.to)
			return false
		}
	}

	for transition, i in desc.buffer_transitions {
		if !buffer_valid(transition.buffer) {
			set_validation_errorf(ctx, "%s: buffer transition %d has an invalid buffer handle", op, i)
			return false
		}
		if !require_resource(ctx, &ctx.buffer_pool, u64(transition.buffer), op, "buffer transition") {
			return false
		}
		if !resource_usage_legal_for_buffer(transition.from) {
			set_validation_errorf(ctx, "%s: buffer transition %d from=%v is not a legal buffer usage", op, i, transition.from)
			return false
		}
		if !resource_usage_legal_for_buffer(transition.to) {
			set_validation_errorf(ctx, "%s: buffer transition %d to=%v is not a legal buffer usage", op, i, transition.to)
			return false
		}
	}

	return true
}

@(private)
validate_subresource_range :: proc(ctx: ^Context, op: string, transition_index: int, range: Subresource_Range, image_state: Image_State) -> bool {
	mip_total := u32(image_state.mip_count)
	if mip_total == 0 {
		mip_total = 1
	}
	layer_total := u32(image_state.array_count)
	if layer_total == 0 {
		layer_total = 1
	}
	if image_state.kind == .Cube {
		layer_total = max(layer_total, 6)
	}

	if range.base_mip >= mip_total {
		set_validation_errorf(ctx, "%s: image transition %d base_mip %d exceeds image mip count %d", op, transition_index, range.base_mip, mip_total)
		return false
	}
	if range.mip_count != 0 && range.base_mip + range.mip_count > mip_total {
		set_validation_errorf(ctx, "%s: image transition %d mip range exceeds image mip count %d", op, transition_index, mip_total)
		return false
	}
	if range.base_layer >= layer_total {
		set_validation_errorf(ctx, "%s: image transition %d base_layer %d exceeds image layer count %d", op, transition_index, range.base_layer, layer_total)
		return false
	}
	if range.layer_count != 0 && range.base_layer + range.layer_count > layer_total {
		set_validation_errorf(ctx, "%s: image transition %d layer range exceeds image layer count %d", op, transition_index, layer_total)
		return false
	}

	if image_state.kind == .Image_3D && (range.base_layer != 0 || (range.layer_count != 0 && range.layer_count != 1)) {
		set_validation_errorf(ctx, "%s: image transition %d names a layer range on a 3D image", op, transition_index)
		return false
	}

	return true
}

@(private)
resource_usage_legal_for_image :: proc(usage: Resource_Usage, image_state: Image_State) -> bool {
	switch usage {
	case .None, .Sampled, .Storage_Read, .Storage_Write, .Storage_Read_Write,
	     .Color_Target, .Depth_Target_Read, .Depth_Target_Write,
	     .Copy_Source, .Copy_Dest, .Present:
		return true
	case .Indirect_Argument:
		return false
	}
	return false
}

@(private)
resource_usage_legal_for_buffer :: proc(usage: Resource_Usage) -> bool {
	switch usage {
	case .None, .Storage_Read, .Storage_Write, .Storage_Read_Write, .Copy_Source, .Copy_Dest, .Indirect_Argument:
		return true
	case .Sampled, .Color_Target, .Depth_Target_Read, .Depth_Target_Write, .Present:
		return false
	}
	return false
}

@(private)
validate_barrier_against_tracker :: proc(ctx: ^Context, desc: Barrier_Desc, op: string) -> bool {
	for transition, i in desc.image_transitions {
		prior, has_prior := ctx.image_last_usage[transition.image]
		if has_prior && prior != transition.from {
			set_validation_errorf(
				ctx,
				"%s: image transition %d declares from=%v but resource is currently %v (wrong barrier)",
				op,
				i,
				transition.from,
				prior,
			)
			return false
		}
	}
	for transition, i in desc.buffer_transitions {
		prior, has_prior := ctx.buffer_last_usage[transition.buffer]
		if has_prior && prior != transition.from {
			set_validation_errorf(
				ctx,
				"%s: buffer transition %d declares from=%v but resource is currently %v (wrong barrier)",
				op,
				i,
				transition.from,
				prior,
			)
			return false
		}
	}
	return true
}

@(private)
record_barrier_into_tracker :: proc(ctx: ^Context, desc: Barrier_Desc) {
	if ctx.image_last_usage == nil {
		ctx.image_last_usage = make(map[Image]Resource_Usage)
	}
	if ctx.buffer_last_usage == nil {
		ctx.buffer_last_usage = make(map[Buffer]Resource_Usage)
	}
	for transition in desc.image_transitions {
		ctx.image_last_usage[transition.image] = transition.to
	}
	for transition in desc.buffer_transitions {
		ctx.buffer_last_usage[transition.buffer] = transition.to
	}
}

@(private)
barrier_tracker_record_image_usage :: proc(ctx: ^Context, image: Image, usage: Resource_Usage) {
	if ctx == nil || !ctx.desc.debug || !image_valid(image) {
		return
	}
	if ctx.image_last_usage == nil {
		ctx.image_last_usage = make(map[Image]Resource_Usage)
	}
	ctx.image_last_usage[image] = usage
}

@(private)
barrier_tracker_record_buffer_usage :: proc(ctx: ^Context, buffer: Buffer, usage: Resource_Usage) {
	if ctx == nil || !ctx.desc.debug || !buffer_valid(buffer) {
		return
	}
	if ctx.buffer_last_usage == nil {
		ctx.buffer_last_usage = make(map[Buffer]Resource_Usage)
	}
	ctx.buffer_last_usage[buffer] = usage
}

// barrier_tracker_check_image_use validates a debug-build use site against the
// per-frame tracker. Returns false (and reports a missing-barrier validation
// error) when the resource was previously declared in an incompatible usage
// without an intervening `barrier()` that transitioned it to `usage`.
@(private)
barrier_tracker_check_image_use :: proc(ctx: ^Context, image: Image, usage: Resource_Usage, op, role: string) -> bool {
	if ctx == nil || !ctx.desc.debug || !image_valid(image) {
		return true
	}
	prior, has_prior := ctx.image_last_usage[image]
	if has_prior && !image_usages_compatible(prior, usage) {
		set_validation_errorf(
			ctx,
			"%s: %s declares image as %v but resource is currently %v (missing barrier from %v to %v)",
			op,
			role,
			usage,
			prior,
			prior,
			usage,
		)
		return false
	}
	return true
}

@(private)
barrier_tracker_check_buffer_use :: proc(ctx: ^Context, buffer: Buffer, usage: Resource_Usage, op, role: string) -> bool {
	if ctx == nil || !ctx.desc.debug || !buffer_valid(buffer) {
		return true
	}
	prior, has_prior := ctx.buffer_last_usage[buffer]
	if has_prior && !buffer_usages_compatible(prior, usage) {
		set_validation_errorf(
			ctx,
			"%s: %s declares buffer as %v but resource is currently %v (missing barrier from %v to %v)",
			op,
			role,
			usage,
			prior,
			prior,
			usage,
		)
		return false
	}
	return true
}

@(private)
image_usages_compatible :: proc(prior, next: Resource_Usage) -> bool {
	if prior == next {
		return true
	}
	// Read-only sampled and read-only depth coexist with each other on
	// D3D12/Vulkan when the resource carries both states. Track only direct
	// equality for now — the conservative rule is "any change of role needs
	// a barrier", matching the wrong-barrier policy on barrier() calls.
	return false
}

@(private)
buffer_usages_compatible :: proc(prior, next: Resource_Usage) -> bool {
	return prior == next
}

@(private)
barrier_tracker_clear :: proc(ctx: ^Context) {
	if ctx == nil {
		return
	}
	clear(&ctx.image_last_usage)
	clear(&ctx.buffer_last_usage)
}

@(private)
barrier_tracker_release :: proc(ctx: ^Context) {
	if ctx == nil {
		return
	}
	delete(ctx.image_last_usage)
	delete(ctx.buffer_last_usage)
	ctx.image_last_usage = nil
	ctx.buffer_last_usage = nil
}

@(private)
barrier_tracker_record_pass_attachments :: proc(ctx: ^Context, desc: Pass_Desc) {
	if ctx == nil || !ctx.desc.debug {
		return
	}
	for view, _ in desc.color_attachments {
		if !view_valid(view) {
			continue
		}
		view_state := query_view_state(ctx, view)
		if !view_state.valid || !image_valid(view_state.image) {
			continue
		}
		barrier_tracker_record_image_usage(ctx, view_state.image, .Color_Target)
	}
	if view_valid(desc.depth_stencil_attachment) {
		view_state := query_view_state(ctx, desc.depth_stencil_attachment)
		if view_state.valid && image_valid(view_state.image) {
			barrier_tracker_record_image_usage(ctx, view_state.image, .Depth_Target_Write)
		}
	}
}

@(private)
barrier_tracker_check_pass_attachments :: proc(ctx: ^Context, desc: Pass_Desc, op: string) -> bool {
	if ctx == nil || !ctx.desc.debug {
		return true
	}
	for view, slot in desc.color_attachments {
		if !view_valid(view) {
			continue
		}
		view_state := query_view_state(ctx, view)
		if !view_state.valid || !image_valid(view_state.image) {
			continue
		}
		role := fmt.tprintf("color attachment slot %d", slot)
		if !barrier_tracker_check_image_use(ctx, view_state.image, .Color_Target, op, role) {
			return false
		}
	}
	if view_valid(desc.depth_stencil_attachment) {
		view_state := query_view_state(ctx, desc.depth_stencil_attachment)
		if view_state.valid && image_valid(view_state.image) {
			if !barrier_tracker_check_image_use(ctx, view_state.image, .Depth_Target_Write, op, "depth-stencil attachment") {
				return false
			}
		}
	}
	return true
}

// barrier_tracker_role_for_view maps a sampled/storage view to the resource
// usage it implies at the bind site. Attachment views never reach
// apply_bindings (validate_bindings rejects them earlier).
@(private)
barrier_tracker_role_for_view :: proc(view_state: View_State) -> Resource_Usage {
	switch view_state.kind {
	case .Sampled:
		return .Sampled
	case .Storage_Image, .Storage_Buffer:
		// Storage reflection can be conservative; treat a storage view bind as
		// read/write so barriers must declare the common UAV-style role
		// explicitly.
		return .Storage_Read_Write
	case .Color_Attachment, .Depth_Stencil_Attachment:
		return .None
	}
	return .None
}

@(private)
barrier_tracker_check_bindings :: proc(ctx: ^Context, bindings: Bindings, op: string) -> bool {
	if ctx == nil || !ctx.desc.debug {
		return true
	}
	for group_views, group in bindings.views {
		for view, slot in group_views {
			if !view_valid(view) {
				continue
			}
			view_state := query_view_state(ctx, view)
			if !view_state.valid {
				continue
			}
			usage := barrier_tracker_role_for_view(view_state)
			if usage == .None {
				continue
			}
			if image_valid(view_state.image) {
				role := fmt.tprintf("resource view group %d slot %d", group, slot)
				if !barrier_tracker_check_image_use(ctx, view_state.image, usage, op, role) {
					return false
				}
			}
			if buffer_valid(view_state.buffer) {
				role := fmt.tprintf("resource view group %d slot %d", group, slot)
				if !barrier_tracker_check_buffer_use(ctx, view_state.buffer, usage, op, role) {
					return false
				}
			}
		}
	}
	return true
}

@(private)
barrier_tracker_record_bindings :: proc(ctx: ^Context, bindings: Bindings) {
	if ctx == nil || !ctx.desc.debug {
		return
	}
	for group_views in bindings.views {
		for view in group_views {
			if !view_valid(view) {
				continue
			}
			view_state := query_view_state(ctx, view)
			if !view_state.valid {
				continue
			}
			usage := barrier_tracker_role_for_view(view_state)
			if usage == .None {
				continue
			}
			if image_valid(view_state.image) {
				barrier_tracker_record_image_usage(ctx, view_state.image, usage)
			}
			if buffer_valid(view_state.buffer) {
				barrier_tracker_record_buffer_usage(ctx, view_state.buffer, usage)
			}
		}
	}
}
