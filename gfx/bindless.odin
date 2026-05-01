package gfx

// Bindless / resource-array public API â€” AAA roadmap items 26 / 27,
// APE-22 / APE-23.
//
// This file holds the locked public types and verbs. Runtime-only bodies
// return Unsupported until their backend implementations land. The shapes
// reflect the design in docs/private/gfx-bindless-note.md, which composes with:
//
//   gfx-bindless-note.md §9    — D3D12 / Vulkan descriptor heaps are the
//                                intended runtime-array path after the
//                                D3D12 backend migration.
//   gfx-slang-reflection-contract.md "Descriptor Arrays And Bindless
//                                Direction" â€” generated-binding shapes that
//                                target this runtime API. The runtime type
//                                consumed by Slang tooling is named
//                                `Binding_Heap` (was `Binding_Table` in
//                                pre-item-27 drafts).
//   binding_groups.odin        â€” existing immutable-group surface that this
//                                file extends without rewriting.
//   queue.odin                 â€” Timeline_Semaphore is the public sync for
//                                heap-slot reuse.
//
// Heap-side verbs validate their descriptor shape, then return Unsupported
// until the runtime-array sample exists and backend validation rules land.
// The `arrays` payload on `Binding_Group_Desc` (declared in types.odin) is
// enforced by binding-group validation; the field zero-defaults to "no fixed
// arrays" so existing Binding_Group_Desc literals stay valid.

// MAX_BINDING_GROUP_ARRAYS bounds the number of distinct fixed-array slots
// in one `Binding_Group_Desc`. The number must be small because every entry
// holds a slice header and is part of the immutable group payload.
MAX_BINDING_GROUP_ARRAYS :: 8

// MAX_BINDING_HEAPS bounds the number of `Binding_Heap` handles a pipeline
// layout may bind in one draw / dispatch.
//
// One heap per logical pipeline-layout slot; `MAX_BINDING_GROUPS` is the
// matching upper bound for groups, so heap and group budgets compose.
MAX_BINDING_HEAPS :: MAX_BINDING_GROUPS

// Binding_Group_Array_Desc is the immutable, fixed-count array payload that
// lives inside `Binding_Group_Desc.arrays` (declared in types.odin, locked
// by item 27).
//
// `kind` is `.Resource_View` or `.Sampler`; uniform-block arrays are not in
// the contract (uniform arrays go through the existing `apply_uniform_*`
// path).
//
// `slot` names the *logical* base slot reflected from Slang. The array
// occupies `[slot, slot + count)` in the layout's per-kind slot space.
// Backend-native expansion uses `Binding_Group_Native_Binding_Desc` for the
// base slot; the per-element native slots are `base + index` and are not
// emitted into `native_bindings` separately.
//
// `views` and `samplers` are mutually exclusive â€” exactly one is non-empty,
// gated by `kind`. `len(views)` (or `len(samplers)`) must equal the
// generated array's reflected `count` for full population, or the user must
// use the `_range` setter from the generated binding to populate a subset.
// Slots not populated by `_range` are validation errors at
// `create_binding_group` time.
//
// `first_index` is meaningful only for the `_range` setter writing into a
// staging payload before group creation; the create call collapses partial
// ranges into the final array and rejects gaps.
Binding_Group_Array_Desc :: struct {
    active:      bool,
    kind:        Shader_Binding_Kind,
    slot:        u32,
    first_index: u32,
    count:       u32,
    views:       []View,
    samplers:    []Sampler,
}

// Binding_Heap is the opaque handle for a long-lived, mutable descriptor
// table.
//
// Created by `create_binding_heap`. Slots are written individually with
// `update_binding_heap_views` / `update_binding_heap_samplers`. Unlike
// `Binding_Group`, a heap is *not* immutable; per-entry reuse is fence-
// gated through `Timeline_Semaphore` (see Â§7.2 of the bindless note).
//
// One heap holds one element kind â€” sampled views, storage images, storage
// buffers, *or* samplers. Mixed-kind heaps are not in the public contract
// (Vulkan and D3D12 both forbid them in their natural form).
Binding_Heap :: distinct u64
Binding_Heap_Invalid :: Binding_Heap(0)

// Binding_Heap_Desc creates a `Binding_Heap`.
//
// Exactly one of (`view_kind`, `samplers`) names the heap's element kind:
//
//   samplers = true                  -> sampler heap; view_kind / format /
//                                       stride must be zero-init.
//   samplers = false, view_kind = â€¦ -> resource-view heap; field semantics
//                                       follow `Binding_Group_Resource_View_Layout_Desc`.
//
// `capacity` is the number of slots. Fence-gated reuse means a 4096-slot
// heap can serve far more than 4096 distinct resources over its lifetime;
// pick capacity based on "how many descriptors must be in flight at once",
// not "how many resources will ever pass through".
//
// `access` follows the existing `Shader_Resource_Access` enum
// (`.Read` / `.Write` / `.Read_Write`). Mixing access kinds inside one
// heap is rejected; create separate heaps if a binding needs both.
Binding_Heap_Desc :: struct {
    label:                 string,
    capacity:              u32,
    samplers:              bool,
    view_kind:             View_Kind,
    access:                Shader_Resource_Access,
    storage_image_format:  Pixel_Format,
    storage_buffer_stride: u32,
}

// Binding_Heap_Slot_Range names a contiguous slot range for batched
// updates and partial binds.
//
// `count == 0` is a no-op (validated as success). `first_index + count`
// must be `<= capacity`.
Binding_Heap_Slot_Range :: struct {
    first_index: u32,
    count:       u32,
}

// create_binding_heap allocates a long-lived descriptor heap.
//
// Must be called on the Context thread. Returns `Binding_Heap_Invalid` and
// `false` on validation/backend failure; check `last_error(ctx)`.
//
// Backends:
//
//   D3D12   â€” allocates a shader-visible `D3D12_DESCRIPTOR_HEAP` of the
//             matching `D3D12_DESCRIPTOR_HEAP_TYPE`.
//   Vulkan  â€” allocates a `VkDescriptorPool` + `VkDescriptorSet` configured
//             with `UPDATE_AFTER_BIND` / `PARTIALLY_BOUND` /
//             `runtimeDescriptorArray` flags from
//             `VK_EXT_descriptor_indexing`.
//
// example:
//   heap, ok := gfx.create_binding_heap(&ctx, gfx.Binding_Heap_Desc{
//       label     = "particle textures",
//       capacity  = 4096,
//       view_kind = .Sampled,
//       access    = .Read,
//   })
create_binding_heap :: proc(ctx: ^Context, desc: Binding_Heap_Desc) -> (Binding_Heap, bool) {
    if !require_initialized(ctx, "gfx.create_binding_heap") {
        return Binding_Heap_Invalid, false
    }
    if !validate_binding_heap_desc(ctx, desc, "gfx.create_binding_heap") {
        return Binding_Heap_Invalid, false
    }
    if reject_binding_heap_for_backend(ctx, "gfx.create_binding_heap") {
        return Binding_Heap_Invalid, false
    }
    set_unsupported_error(ctx, "gfx.create_binding_heap: backend support is not implemented yet (item 28 ships fixed arrays only; runtime / bindless heap is gated on the runtime-array sample)")
    return Binding_Heap_Invalid, false
}

// destroy_binding_heap releases a `Binding_Heap`'s backing storage.
//
// All in-flight submits that bound or read the heap must have completed;
// the call does not block on its own slots. The typical caller is shutdown.
destroy_binding_heap :: proc(ctx: ^Context, heap: Binding_Heap) {
    if !require_initialized(ctx, "gfx.destroy_binding_heap") {
        return
    }
    set_unsupported_error(ctx, "gfx.destroy_binding_heap: backend support is not implemented yet")
}

// binding_heap_capacity reports the slot count a heap was created with.
//
// Returns 0 for an invalid handle.
binding_heap_capacity :: proc(ctx: ^Context, heap: Binding_Heap) -> u32 {
    return 0
}

// update_binding_heap_views writes a contiguous range of resource-view
// descriptors into a heap.
//
// The write is **visible to every submit issued after this call returns**
// (Â§7.1 of the bindless note). It is *not* visible to in-flight submits;
// a slot already read by an unfinished submit must be released first.
//
// Validation:
//
//   - `heap` is a resource-view heap (not a sampler heap).
//   - `len(views)` slots fit at `[first_index, first_index + len(views))`.
//   - every `view` in `views` is valid and matches the heap's
//     `view_kind` / `access` / `storage_image_format` /
//     `storage_buffer_stride`.
//   - no slot in the range has a pending fence recorded by
//     `release_binding_heap_slot` that has not yet retired (Â§7.2).
//
// Returns false on validation/backend failure; check `last_error(ctx)`.
//
// example:
//   gfx.update_binding_heap_views(&ctx, heap, 0, []gfx.View{
//       tex_smoke, tex_spark, tex_glow,
//   })
update_binding_heap_views :: proc(ctx: ^Context, heap: Binding_Heap, first_index: u32, views: []View) -> bool {
    if !require_initialized(ctx, "gfx.update_binding_heap_views") {
        return false
    }
    if u64(heap) == 0 {
        set_invalid_handle_error(ctx, "gfx.update_binding_heap_views: heap handle is invalid")
        return false
    }
    set_unsupported_error(ctx, "gfx.update_binding_heap_views: backend support is not implemented yet")
    return false
}

// update_binding_heap_samplers writes a contiguous range of sampler
// descriptors into a sampler heap. Mirrors `update_binding_heap_views`.
update_binding_heap_samplers :: proc(ctx: ^Context, heap: Binding_Heap, first_index: u32, samplers: []Sampler) -> bool {
    if !require_initialized(ctx, "gfx.update_binding_heap_samplers") {
        return false
    }
    if u64(heap) == 0 {
        set_invalid_handle_error(ctx, "gfx.update_binding_heap_samplers: heap handle is invalid")
        return false
    }
    set_unsupported_error(ctx, "gfx.update_binding_heap_samplers: backend support is not implemented yet")
    return false
}

// release_binding_heap_slot records that slot `index` will not be safe to
// overwrite until `frame_done` has been reached.
//
// The heap remembers the wait. The next `update_binding_heap_views` /
// `update_binding_heap_samplers` for that slot is rejected as a validation
// error until `gfx.timeline_semaphore_value(frame_done.semaphore) >=
// frame_done.value`. Callers that already serialize frame pacing on the
// CPU side may pass `{Timeline_Semaphore_Invalid, 0}` to release without
// a fence (Â§7.2 of the bindless note).
//
// Releasing a slot does not zero or null its descriptor; readers that race
// the release see the old contents. The fence guarantees no submit reads
// the descriptor after release completes.
release_binding_heap_slot :: proc(ctx: ^Context, heap: Binding_Heap, index: u32, frame_done: Semaphore_Wait) -> bool {
    if !require_initialized(ctx, "gfx.release_binding_heap_slot") {
        return false
    }
    if u64(heap) == 0 {
        set_invalid_handle_error(ctx, "gfx.release_binding_heap_slot: heap handle is invalid")
        return false
    }
    set_unsupported_error(ctx, "gfx.release_binding_heap_slot: backend support is not implemented yet")
    return false
}

// apply_binding_heap binds a `Binding_Heap` at one logical pipeline-layout
// slot, parallel to `apply_binding_group`.
//
// `group` is the logical group index the pipeline layout reserved for the
// heap (the layout slot's `kind == .Heap`). Mixing `apply_binding_group`
// and `apply_binding_heap` for the same logical slot in one draw is a
// validation error.
//
// Per the indexing model in Â§6, the *shader* declaration decides whether
// reads use a constant, dynamic-uniform, or fully-dynamic index into the
// heap. The runtime does not pick.
apply_binding_heap :: proc(ctx: ^Context, group: u32, heap: Binding_Heap) -> bool {
    if !require_initialized(ctx, "gfx.apply_binding_heap") {
        return false
    }
    if u64(heap) == 0 {
        set_invalid_handle_error(ctx, "gfx.apply_binding_heap: heap handle is invalid")
        return false
    }
    set_unsupported_error(ctx, "gfx.apply_binding_heap: backend support is not implemented yet")
    return false
}

// cmd_apply_binding_heap is the encoder-side counterpart to
// `apply_binding_heap`, recorded into a `Command_List`.
//
// Lands when `Command_List` recording lands; today this is the same kind
// of forward-declared sketch as the rest of `command_list.odin`.
cmd_apply_binding_heap :: proc(encoder: ^Render_Pass_Encoder, group: u32, heap: Binding_Heap) -> bool {
    return render_encoder_set_unsupported(encoder, "gfx.cmd_apply_binding_heap: explicit command recording is not implemented yet")
}

// cmd_apply_compute_binding_heap mirrors `cmd_apply_binding_heap` for
// compute encoders.
cmd_apply_compute_binding_heap :: proc(encoder: ^Compute_Pass_Encoder, group: u32, heap: Binding_Heap) -> bool {
    return compute_encoder_set_unsupported(encoder, "gfx.cmd_apply_compute_binding_heap: explicit command recording is not implemented yet")
}

// reject_binding_heap_for_backend exists so backend-specific permanent
// rejections have one place to live. D3D12 and Vulkan are expected to support
// this path once their descriptor backends land, so they currently fall
// through to the implementation-pending Unsupported error.
//
// Returns true if the call has been rejected (the caller's error is set);
// false if the backend has no permanent objection and the caller should
// proceed to its implementation-pending fallback.
@(private)
reject_binding_heap_for_backend :: proc(ctx: ^Context, op: string) -> bool {
    switch ctx.backend {
    case .Null, .D3D12, .Vulkan, .Auto:
        return false
    }
    return false
}

// validate_binding_heap_desc enforces the shape rules in Â§5 / Â§6 of the
// bindless note. Backends will reject the desc with an additional Unsupported
// error until the runtime / bindless heap path lands.
@(private)
validate_binding_heap_desc :: proc(ctx: ^Context, desc: Binding_Heap_Desc, op: string) -> bool {
    if desc.capacity == 0 {
        set_validation_errorf(ctx, "%s: capacity must be > 0", op)
        return false
    }
    if desc.samplers {
        if desc.view_kind != .Sampled {
            // Sampler heaps must zero-init view_kind; the enum's zero value is .Sampled.
            // Reject any non-default storage_image_format / storage_buffer_stride below.
        }
        if desc.storage_image_format != .Invalid {
            set_validation_errorf(ctx, "%s: sampler heap must not declare a storage image format", op)
            return false
        }
        if desc.storage_buffer_stride != 0 {
            set_validation_errorf(ctx, "%s: sampler heap must not declare a storage buffer stride", op)
            return false
        }
        if desc.access != .Unknown && desc.access != .Read {
            set_validation_errorf(ctx, "%s: sampler heap access must be .Unknown or .Read", op)
            return false
        }
        return true
    }
    if !shader_resource_view_kind_valid(desc.view_kind) {
        set_validation_errorf(ctx, "%s: view_kind must be .Sampled, .Storage_Image, or .Storage_Buffer", op)
        return false
    }
    if !shader_resource_access_valid(desc.access) {
        set_validation_errorf(ctx, "%s: access has an invalid value", op)
        return false
    }
    if desc.view_kind == .Storage_Image {
        if !shader_storage_image_format_valid(desc.storage_image_format) {
            set_validation_errorf(ctx, "%s: storage image heap has an unsupported format", op)
            return false
        }
    } else if desc.storage_image_format != .Invalid {
        set_validation_errorf(ctx, "%s: non-storage-image heap must not declare a storage image format", op)
        return false
    }
    if desc.view_kind == .Storage_Buffer {
        if desc.storage_buffer_stride != 0 && desc.storage_buffer_stride % 4 != 0 {
            set_validation_errorf(ctx, "%s: storage buffer heap stride must be 4-byte aligned", op)
            return false
        }
    } else if desc.storage_buffer_stride != 0 {
        set_validation_errorf(ctx, "%s: non-storage-buffer heap must not declare a storage buffer stride", op)
        return false
    }
    return true
}
