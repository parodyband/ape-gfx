# Ape GFX Public API Audit

Date: 2026-04-27
Source: `docs/api/markdown/gfx.md`

This audit records the v0.1 public surface for `gfx`. It classifies every symbol so future API work starts from a concrete baseline.

## Status Key

- `keep`: intended to remain public for v0.1.
- `hide`: should become private or disappear from public docs if Odin/package constraints allow it.
- `defer`: public shape exists, but the feature should not be considered v0.1-stable yet.
- `rename`: spelling should change before a stronger compatibility promise.
- `needs_docs`: public but under-explained.
- `needs_test`: public but not directly validated enough.

Composite statuses are comma-separated.

## First Decisions

- `create_*` remains the primary creation spelling.
- `make_*` handle-only aliases are removed before `v0.1-alpha`. The project is pre-1.0 and should not preserve older creation spellings.
- `destroy` remains the primary ergonomic cleanup overload, while `destroy_*` stays public for explicit callsites.
- `range` is the primary data-span helper. `range_slice` and `range_fixed_array` are private overload implementations. `range_raw` stays public as the explicit raw-pointer escape hatch.
- `query_*` names are acceptable for v0.1.
- Public `Swapchain` handles are removed from v0.1. A `Pass_Desc` with no explicit attachments targets the context's implicit window swapchain.
- `Shader_Desc` remains public low-level API because `.ashader` loading produces it, but user-facing docs should steer most users through `shader`.
- Typed errors are assigned explicitly. Remaining error work is representative coverage for backend/device-loss paths.
- Core descriptors have contract docs and representative validation coverage.

## Required API Maintenance

1. Keep public contract scripts in the normal validation path so new public symbols and descriptor regressions are caught.
2. Keep the full v0.1 validation gate passing and commit any generated API docs drift.

## Constants

| Symbol | Status | v0.1 Decision |
| --- | --- | --- |
| `Buffer_Invalid` | keep | Stable invalid sentinel. |
| `Binding_Group_Invalid` | keep | Stable invalid sentinel for object-backed binding groups. |
| `Binding_Group_Layout_Invalid` | keep | Stable invalid sentinel for object-backed binding group layouts. |
| `Binding_Heap_Invalid` | defer | APE-23/APE-25 bindless binding heap sentinel. Stays public when bindless ships in a non-D3D11 backend. |
| `COLOR_MASK_A` | keep, needs_docs | Stable color-write mask bit. |
| `COLOR_MASK_B` | keep, needs_docs | Stable color-write mask bit. |
| `COLOR_MASK_G` | keep, needs_docs | Stable color-write mask bit. |
| `COLOR_MASK_R` | keep, needs_docs | Stable color-write mask bit. |
| `COLOR_MASK_RGB` | keep, needs_docs | Stable combined color-write mask. |
| `COLOR_MASK_RGBA` | keep, needs_docs | Stable combined color-write mask. |
| `Compute_Pipeline_Invalid` | keep | Stable invalid sentinel. |
| `DISPATCH_INDIRECT_ARGS_STRIDE` | keep | APE-7 indirect dispatch arg stride (`size_of(Dispatch_Indirect_Args)`). |
| `DRAW_INDEXED_INDIRECT_ARGS_STRIDE` | keep | APE-7 indexed indirect arg stride (`size_of(Draw_Indexed_Indirect_Args)`). |
| `DRAW_INDIRECT_ARGS_STRIDE` | keep | APE-7 non-indexed indirect arg stride (`size_of(Draw_Indirect_Args)`). |
| `Image_Invalid` | keep | Stable invalid sentinel. |
| `MAX_BINDING_GROUPS` | keep | Public logical binding group limit. |
| `MAX_BINDING_GROUP_ARRAYS` | keep | APE-24 public limit on binding-group runtime/fixed array entries. |
| `MAX_BINDING_GROUP_ENTRIES` | keep | Generated binding group layout entry limit. |
| `MAX_BINDING_HEAPS` | defer | APE-23 public bindless heap concurrency cap. Stays public when bindless ships. |
| `MAX_COLOR_ATTACHMENTS` | keep | Public fixed array limit. |
| `MAX_IMAGE_MIPS` | keep | Public fixed array limit. |
| `MAX_RESOURCE_VIEWS` | keep | Public fixed array limit. |
| `MAX_SAMPLERS` | keep | Public fixed array limit. |
| `MAX_SHADER_BINDINGS` | keep | Public fixed array limit. |
| `MAX_UNIFORM_BLOCKS` | keep | Public fixed array limit. |
| `MAX_VERTEX_ATTRIBUTES` | keep | Public fixed array limit. |
| `MAX_VERTEX_BUFFERS` | keep | Public fixed array limit. |
| `Pipeline_Invalid` | keep | Stable invalid sentinel. |
| `Pipeline_Layout_Invalid` | keep | Stable invalid sentinel for explicit pipeline layouts. |
| `Queue_Invalid` | defer | APE-17 queue/timeline sketch sentinel. Stays public when the submission API lands. |
| `Sampler_Invalid` | keep | Stable invalid sentinel. |
| `Shader_Invalid` | keep | Stable invalid sentinel. |
| `SUBRESOURCE_RANGE_WHOLE` | keep | APE-15 explicit name for the zero-init "whole image" `Subresource_Range`. |
| `Timeline_Semaphore_Invalid` | defer | APE-17 queue/timeline sketch sentinel. Stays public when the submission API lands. |
| `TRANSIENT_INDEX_ALIGNMENT` | keep | Public alignment for `Transient_Usage.Index` slices. |
| `TRANSIENT_INDIRECT_ALIGNMENT` | keep | Public alignment for `Transient_Usage.Indirect` slices. |
| `TRANSIENT_STORAGE_ALIGNMENT` | keep | Public alignment for `Transient_Usage.Storage` slices. |
| `TRANSIENT_UNIFORM_ALIGNMENT` | keep | Public alignment for `Transient_Usage.Uniform` slices (256 bytes, the strictest of the three target backends). |
| `TRANSIENT_VERTEX_ALIGNMENT` | keep | Public alignment for `Transient_Usage.Vertex` slices. |
| `Transient_Allocator_Invalid` | keep | Stable invalid sentinel for transient allocators. |
| `View_Invalid` | keep | Stable invalid sentinel. |

## Procedures

| Symbol | Status | v0.1 Decision |
| --- | --- | --- |
| `acquire_compute_queue` | defer | APE-17 queue/timeline sketch. Body panics; backend lands with D3D12/Vulkan. |
| `acquire_graphics_queue` | defer | APE-17 queue/timeline sketch. Body panics; backend lands with D3D12/Vulkan. |
| `acquire_transfer_queue` | defer | APE-17 queue/timeline sketch. Body panics; backend lands with D3D12/Vulkan. |
| `apply_binding_group` | keep, needs_test | Applies an object-backed binding group with optional geometry bindings. |
| `apply_binding_groups` | keep, needs_test | Applies multiple object-backed binding groups with optional geometry bindings. |
| `apply_binding_heap` | defer | APE-23/APE-25 bindless heap bind. D3D11 rejects; lands with D3D12/Vulkan bindless. |
| `apply_bindings` | keep, needs_test | Core command. Expand validation tests around buffer/view/sampler slots. |
| `apply_compute_pipeline` | keep, needs_test | Core compute command. Keep if compute is v0.1-stable. |
| `apply_pipeline` | keep, needs_test | Core render command. |
| `apply_uniform` | keep, needs_docs | Ergonomic typed wrapper over `apply_uniforms`. |
| `apply_uniform_at` | keep, needs_test | Offset-aware uniform binding (APE-21) that binds a `Transient_Slice` as a constant buffer at a slot. |
| `apply_uniform_at_typed` | keep, needs_docs | Ergonomic typed wrapper over `apply_uniform_at`. |
| `apply_uniforms` | keep, needs_test | Core uniform upload. |
| `barrier` | keep, needs_test | APE-16 immediate-mode barrier verb. D3D11 no-ops; in debug builds runs the per-frame last-known-usage tracker to flag wrong-barrier and missing-barrier scenarios. |
| `barrier_buffer_target` | defer | APE-15 helper that builds a whole-buffer `Barrier_Target`. |
| `barrier_image_target` | defer | APE-15 helper that builds an image `Barrier_Target` with optional `Subresource_Range`. |
| `backend_name` | keep | Small diagnostic helper. |
| `begin_compute_pass` | keep, needs_test | Core compute command. |
| `begin_pass` | keep, needs_test | Core render command. |
| `binding_group_layout_valid` | keep, needs_test | Simple sentinel check. |
| `binding_heap_capacity` | defer | APE-23 bindless heap capacity diagnostic. |
| `cmd_apply_binding_heap` | defer | APE-5 + APE-23/APE-25 recording sketch. Body panics; backend lands with bindless. |
| `cmd_apply_bindings` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_apply_compute_binding_heap` | defer | APE-5 + APE-23/APE-25 recording sketch. Body panics; backend lands with bindless. |
| `cmd_apply_compute_bindings` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_apply_compute_pipeline` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_apply_compute_uniforms` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_apply_pipeline` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_apply_uniforms` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_barrier` | defer | APE-15 explicit barrier sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_begin_compute_pass` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_begin_render_pass` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_dispatch` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_dispatch_indirect` | defer | APE-5 + APE-7 recording sketch. Body panics; backend lands with APE-9. |
| `cmd_draw` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_draw_indexed_indirect` | defer | APE-5 + APE-7 recording sketch. Body panics; immediate-mode `draw_indexed_indirect` ships with APE-8. |
| `cmd_draw_indirect` | defer | APE-5 + APE-7 recording sketch. Body panics; immediate-mode `draw_indirect` ships with APE-8. |
| `cmd_end_compute_pass` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `cmd_end_render_pass` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `command_list_last_error` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `command_list_last_error_code` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `binding_group_valid` | keep, needs_test | Simple sentinel check. |
| `buffer_valid` | keep, needs_test | Simple sentinel check. Revisit overload group only if callsites need it. |
| `commit` | keep, needs_test | Core frame command. |
| `compute_pipeline_valid` | keep, needs_test | Simple sentinel check. |
| `create_buffer` | keep, needs_test | Primary buffer creation spelling. |
| `create_command_list` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `create_binding_group` | keep, needs_test | Primary binding group creation spelling. |
| `create_binding_group_layout` | keep, needs_test | Primary binding group layout creation spelling. |
| `create_binding_heap` | defer | APE-23/APE-25 bindless heap creation. D3D11 rejects; lands with D3D12/Vulkan bindless. |
| `create_compute_pipeline` | keep, needs_test | Primary compute pipeline creation spelling. |
| `create_image` | keep, needs_test | Primary image creation spelling. |
| `create_pipeline` | keep, needs_test | Primary graphics pipeline creation spelling. |
| `create_pipeline_layout` | keep, needs_test | Primary pipeline layout creation spelling for reflected shader bindings. |
| `create_render_target` | keep | Low-level helper for common offscreen color/depth target setup. Covered by descriptor contract tests. |
| `create_sampler` | keep, needs_test | Primary sampler creation spelling. |
| `create_shader` | keep, needs_docs | Primary low-level shader creation spelling. Most users should arrive through `.ashader`. |
| `create_timeline_semaphore` | defer | APE-17 queue/timeline sketch. Body panics; backend lands with D3D12/Vulkan. |
| `create_view` | keep, needs_test | Primary view creation spelling. |
| `default_pass_action` | keep, needs_docs | Stable default helper. Document clear/store defaults. |
| `destroy_command_list` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `destroy_timeline_semaphore` | defer | APE-17 queue/timeline sketch. Body panics; backend lands with D3D12/Vulkan. |
| `destroy_buffer` | keep | Explicit destroy remains available. |
| `destroy_binding_group` | keep | Explicit destroy remains available. |
| `destroy_binding_group_layout` | keep | Explicit destroy remains available. |
| `destroy_binding_heap` | defer | APE-23/APE-25 bindless heap destroy. Lands with D3D12/Vulkan bindless. |
| `destroy_compute_pipeline` | keep | Explicit destroy remains available. |
| `destroy_image` | keep | Explicit destroy remains available. |
| `destroy_pipeline` | keep | Explicit destroy remains available. |
| `destroy_pipeline_layout` | keep | Explicit destroy remains available. |
| `destroy_render_target` | keep | Releases the explicit image/view handles owned by a `Render_Target` aggregate. |
| `destroy_sampler` | keep | Explicit destroy remains available. |
| `destroy_shader` | keep | Explicit destroy remains available. |
| `destroy_view` | keep | Explicit destroy remains available. |
| `dispatch` | keep, needs_test | Core compute command. |
| `dispatch_indirect` | keep, needs_test | APE-7 indirect compute dispatch entry point. Body panics on D3D11 until APE-9 wires the backend. |
| `draw` | keep, needs_test | Core render command. |
| `draw_indexed_indirect` | keep, needs_test | APE-7/APE-8 indirect indexed draw entry point. D3D11 backend loops `DrawIndexedInstancedIndirect`. |
| `draw_indirect` | keep, needs_test | APE-7/APE-8 indirect non-indexed draw entry point. D3D11 backend loops `DrawInstancedIndirect`. |
| `end_compute_pass` | keep, needs_test | Core compute command. |
| `end_pass` | keep, needs_test | Core render command. |
| `finish_command_list` | defer | APE-5 recording sketch. Body panics; backend lands with the explicit recording path. |
| `image_valid` | keep, needs_test | Simple sentinel check. |
| `init` | keep | Context creation is covered by `tools/test_gfx_descriptor_contracts.ps1`. |
| `last_error` | keep | Human-readable diagnostics. |
| `last_error_code` | keep, needs_test | Keep after Phase 3 makes codes explicit. |
| `last_error_info` | keep, needs_test | Keep after Phase 3 makes codes explicit. |
| `pass_action_with_defaults` | keep, needs_docs | APE-31 zero-`Pass_Action` defaulting helper applied at the `begin_pass` boundary. |
| `pipeline_valid` | keep, needs_test | Simple sentinel check. |
| `pipeline_layout_valid` | keep, needs_test | Simple sentinel check. |
| `present` | defer | APE-17 swapchain present sketch. Body panics; backend lands with D3D12/Vulkan. |
| `query_backend_limits` | keep, needs_docs | Stable name. Document difference from `query_limits`. |
| `query_buffer_state` | keep, needs_test | Public read-only validation/diagnostic helper. |
| `query_features` | keep, needs_docs | Stable name. |
| `query_image_state` | keep, needs_test | Public read-only validation/diagnostic helper. |
| `query_limits` | keep, needs_docs | Stable name. Document public fixed limits. |
| `query_view_buffer` | keep, needs_docs | Convenience helper over `query_view_state`. |
| `query_view_compatible` | keep, needs_test | Useful validation helper. |
| `query_view_image` | keep, needs_docs | Convenience helper over `query_view_state`. |
| `query_view_state` | keep, needs_test | Public read-only validation/diagnostic helper. |
| `queue_kind` | defer | APE-17 queue/timeline sketch. Body panics; backend lands with D3D12/Vulkan. |
| `range_raw` | keep | Useful raw-pointer escape hatch. Primary docs should prefer typed `range` when possible. |
| `read_buffer` | keep, needs_test | Synchronous readback is v0.1-stable if documented as blocking. |
| `release_binding_heap_slot` | defer | APE-23 bindless heap slot release. Lands with D3D12/Vulkan bindless. |
| `render_target_pass_desc` | keep | Small helper for beginning a pass against a `Render_Target` aggregate. |
| `resize` | keep, needs_test | Stable swapchain resize entry point. |
| `resolve_image` | keep, needs_test | Stable MSAA color resolve command. |
| `sampler_valid` | keep, needs_test | Simple sentinel check. |
| `shader_valid` | keep, needs_test | Simple sentinel check. |
| `shutdown` | keep, needs_test | Context teardown and leak reporting. |
| `submit` | defer | APE-17 queue/timeline sketch. Body panics; backend lands with D3D12/Vulkan. |
| `submit_command_list` | defer | APE-5 recording sketch. Convenience wrapper over `submit`; body panics. |
| `timeline_semaphore_signal` | defer | APE-17 queue/timeline sketch. Body panics; backend lands with D3D12/Vulkan. |
| `timeline_semaphore_value` | defer | APE-17 queue/timeline sketch. Body panics; backend lands with D3D12/Vulkan. |
| `timeline_semaphore_wait` | defer | APE-17 queue/timeline sketch. Body panics; backend lands with D3D12/Vulkan. |
| `create_transient_allocator` | keep, needs_test | Primary creation spelling for per-frame linear allocators (APE-19/APE-20). |
| `destroy_transient_allocator` | keep | Releases backing chunks owned by a transient allocator. |
| `reset_transient_allocator` | keep, needs_test | Returns the bump pointer to zero after the previous frame retires; rotates D3D11 chunks via `Map(WRITE_DISCARD)`. |
| `transient_alloc` | keep, needs_test | Per-frame slice allocation; alignment selected by `Transient_Usage`. |
| `transient_allocator_capacity` | keep | Per-role capacity diagnostic. |
| `transient_allocator_used` | keep | Per-frame bytes-handed-out diagnostic. |
| `update_binding_heap_samplers` | defer | APE-23 bindless heap sampler-array update. Lands with D3D12/Vulkan bindless. |
| `update_binding_heap_views` | defer | APE-23 bindless heap view-array update. Lands with D3D12/Vulkan bindless. |
| `update_buffer` | keep, needs_test | Stable dynamic/stream buffer update. |
| `update_image` | keep, needs_test | Stable dynamic image update. |
| `validate_binding_group_layout_desc` | keep | Validates generated binding group layout descriptors before object creation. |
| `validate_pipeline_layout_desc` | keep | Validates generated pipeline layout descriptors before object creation. |
| `view_valid` | keep, needs_test | Simple sentinel check. |
| `destroy` | keep | Primary ergonomic destroy overload. |
| `range` | keep | Primary data-span overload. |

## Types

| Symbol | Status | v0.1 Decision |
| --- | --- | --- |
| `Backend` | keep | Stable backend selector. `Auto` behavior needs docs. |
| `Barrier_Desc` | defer | APE-15 explicit barrier description (lists of `Image_Transition` / `Buffer_Transition`). Settled with the recording-path implementation. |
| `Barrier_Target` | defer | APE-15 barrier addressee: `Image` or `Buffer` handle plus image `Subresource_Range`. |
| `Barrier_Target_Kind` | defer | APE-15 tag for `Barrier_Target` (Image vs Buffer). |
| `Binding_Group` | keep | Stable binding group handle. |
| `Binding_Group_Array_Desc` | keep | APE-24 fixed/runtime array entry descriptor inside `Binding_Group_Desc`. |
| `Binding_Group_Desc` | keep | Binding group creation descriptor for generated resource views and samplers. Uniforms are still applied separately. |
| `Binding_Group_Layout` | keep | Stable binding group layout handle. |
| `Binding_Group_Layout_Desc` | keep | Generated binding group layout data used by `create_binding_group_layout`. |
| `Binding_Group_Layout_Entry_Desc` | keep | Logical generated binding entry descriptor. |
| `Binding_Group_Native_Binding_Desc` | keep | Backend/stage native slot mapping for generated binding layouts. |
| `Binding_Group_Resource_View_Layout_Desc` | keep | Resource-view payload for generated binding layout entries. |
| `Binding_Group_Uniform_Block_Layout_Desc` | keep | Uniform-block payload for generated binding layout entries. |
| `Binding_Heap` | defer | APE-23/APE-25 bindless heap handle. Stays public when bindless ships. |
| `Binding_Heap_Desc` | defer | APE-23 bindless heap creation descriptor. |
| `Binding_Heap_Slot_Range` | defer | APE-23 contiguous slot range descriptor for bindless heap updates. |
| `Bindings` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_state_descriptor_contracts.ps1`. |
| `Blend_Factor` | keep, needs_docs | Pipeline state enum. |
| `Blend_Op` | keep, needs_docs | Pipeline state enum. |
| `Blend_State` | keep, needs_docs | Pipeline state descriptor. |
| `Buffer` | keep | Stable handle. |
| `Buffer_Binding` | keep | Binding struct for buffers plus byte offset. |
| `Buffer_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_descriptor_contracts.ps1`. |
| `Buffer_Read_Desc` | keep, needs_docs, needs_test | Blocking readback descriptor. |
| `Buffer_State` | keep, needs_docs | Query result. |
| `Buffer_Update_Desc` | keep, needs_docs, needs_test | Dynamic/stream update descriptor. |
| `Buffer_Transition` | defer | APE-15 buffer-side transition (whole-buffer `from -> to`). |
| `Buffer_Usage` | keep | Public bit set. |
| `Buffer_Usage_Flag` | keep, needs_docs | Public bit set values. |
| `Color` | keep | Basic pass clear color type. |
| `Color_Attachment_Action` | keep, needs_docs | Pass action descriptor. |
| `Color_Attachment_View_Desc` | keep | Covered as part of `View_Desc` contract. |
| `Color_State` | keep, needs_docs | Pipeline color target state. |
| `Command_List` | defer | APE-5 recording sketch type. Body and backend land with the explicit recording path. |
| `Command_List_State` | defer | APE-5 recording sketch enum. |
| `Command_Queue` | defer | APE-5 recording-affinity enum. Companion to APE-17 `Queue_Kind`. |
| `Compare_Func` | keep, needs_docs | Depth state enum. |
| `Compute_Pass_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md`; D3D11 compute behavior is covered by `tools/test_d3d11_compute_pass.ps1`. |
| `Compute_Pass_Encoder` | defer | APE-5 recording sketch type. Body and backend land with the explicit recording path. |
| `Compute_Pipeline` | keep | Stable handle if compute remains v0.1-stable. |
| `Compute_Pipeline_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_state_descriptor_contracts.ps1`. |
| `Context` | keep, needs_docs | Public context value. Intent is opaque even though Odin exposes the type. |
| `Cull_Mode` | keep, needs_docs | Raster state enum. |
| `Depth_Attachment_Action` | keep, needs_docs | Pass action descriptor. |
| `Depth_State` | keep, needs_docs | Pipeline depth state. |
| `Depth_Stencil_Attachment_View_Desc` | keep | Covered as part of `View_Desc` contract. |
| `Dispatch_Indirect_Args` | keep | APE-7 canonical indirect dispatch arg layout (`thread_group_count_x/y/z`). |
| `Draw_Indexed_Indirect_Args` | keep | APE-7 canonical indexed indirect draw arg layout. |
| `Draw_Indirect_Args` | keep | APE-7 canonical non-indexed indirect draw arg layout. |
| `Desc` | keep | Context descriptor. Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_descriptor_contracts.ps1`. |
| `Error_Code` | keep, needs_test | Keep after Phase 3 removes string inference. |
| `Error_Info` | keep, needs_test | Keep after Phase 3 removes string inference. |
| `Face_Winding` | keep, needs_docs | Raster state enum. |
| `Features` | keep, needs_docs | Query result. |
| `Fill_Mode` | keep, needs_docs | Raster state enum. |
| `Filter` | keep, needs_docs | Sampler enum. |
| `Image` | keep | Stable handle. |
| `Image_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_descriptor_contracts.ps1`. |
| `Image_Kind` | keep, needs_docs | Image shape enum. Document implemented subset. |
| `Image_Resolve_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_image_transfer_contracts.ps1`. |
| `Image_State` | keep, needs_docs | Query result. |
| `Image_Subresource_Data` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_image_transfer_contracts.ps1`. |
| `Image_Transition` | defer | APE-15 image-side transition (handle, `Subresource_Range`, `from -> to`). |
| `Image_Update_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_image_transfer_contracts.ps1`. |
| `Image_Usage` | keep | Public bit set. |
| `Image_Usage_Flag` | keep, needs_docs | Public bit set values. |
| `Index_Type` | keep | Pipeline index format enum. |
| `Layout_Desc` | keep, needs_docs, needs_test | Manual vertex layout override. |
| `Limits` | keep, needs_docs | Query result. |
| `Load_Action` | keep, needs_docs | Pass action enum. |
| `Pass_Action` | keep, needs_docs | Pass clear/load/store descriptor. |
| `Pass_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_state_descriptor_contracts.ps1`. No explicit attachments means the implicit context swapchain. |
| `Pipeline` | keep | Stable handle. |
| `Pipeline_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_state_descriptor_contracts.ps1`. |
| `Pipeline_Layout` | keep | Stable pipeline layout handle for reflected shader bindings. |
| `Pipeline_Layout_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_state_descriptor_contracts.ps1`. |
| `Pixel_Format` | keep, needs_docs | Public format enum. Document backend support matrix. |
| `Present_Info` | defer | APE-17 swapchain present sketch descriptor. |
| `Primitive_Type` | keep | Pipeline topology enum. |
| `Queue` | defer | APE-17 queue handle sketch. |
| `Queue_Kind` | defer | APE-17 queue family enum. |
| `Range` | keep | Raw byte span for uploads/readback/bytecode. |
| `Raster_State` | keep, needs_docs | Pipeline raster state. |
| `Render_Pass_Encoder` | defer | APE-5 recording sketch type. Body and backend land with the explicit recording path. |
| `Render_Target` | keep | Explicit aggregate of image/view handles created from `Render_Target_Desc`. |
| `Render_Target_Desc` | keep | Low-level color/depth target helper descriptor covered by `tools/test_gfx_descriptor_contracts.ps1`. |
| `Resource_Usage` | keep, needs_docs | APE-13/APE-14 buffer/image state vocabulary used by attachments, binding-group entries, and barrier verbs. |
| `Sampler` | keep | Stable handle. |
| `Semaphore_Signal` | defer | APE-17 timeline-signal edge sketch. |
| `Semaphore_Wait` | defer | APE-17 timeline-wait edge sketch. |
| `Sampler_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_state_descriptor_contracts.ps1`. |
| `Shader` | keep | Stable handle. |
| `Shader_Binding_Desc` | keep, needs_docs | Reflection metadata in `Shader_Desc`. Most users should not handwrite it. |
| `Shader_Binding_Kind` | keep, needs_docs | Reflection metadata enum. |
| `Shader_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_state_descriptor_contracts.ps1`. Low-level shader descriptor produced by `shader`. |
| `Shader_Resource_Access` | keep, needs_docs | Reflection metadata enum. |
| `Shader_Stage` | keep | Shader stage enum. |
| `Shader_Stage_Desc` | keep, needs_docs | Low-level backend bytecode stage descriptor. |
| `Shader_Stage_Set` | keep, needs_docs | Public stage bit set used by generated binding group layout descriptors. |
| `Shader_Vertex_Input_Desc` | keep, needs_docs | Reflection metadata in `Shader_Desc`. |
| `Stencil_Attachment_Action` | keep, needs_docs | Pass action descriptor. |
| `Storage_Buffer_View_Desc` | keep | Covered as part of `View_Desc` contract. |
| `Storage_Image_View_Desc` | keep | Covered as part of `View_Desc` contract. |
| `Store_Action` | keep, needs_docs | Pass action enum. |
| `Subresource_Aspect` | defer | APE-15 image-aspect bit set. Empty means "every aspect this image owns". |
| `Subresource_Aspect_Flag` | defer | APE-15 image-aspect enum (Color, Depth, Stencil). |
| `Subresource_Range` | defer | APE-15 mip/layer/aspect range carried by image barriers. Zero-init means "whole image". |
| `Submit_Info` | defer | APE-17 submission descriptor sketch. |
| `Texture_View_Desc` | keep | Covered as part of `View_Desc` contract. |
| `Timeline_Semaphore` | defer | APE-17 timeline semaphore handle sketch. |
| `Transient_Allocator` | keep | Per-frame linear allocator handle (APE-19/APE-20). |
| `Transient_Allocator_Desc` | keep | Creation descriptor for `create_transient_allocator`. |
| `Transient_Slice` | keep | Allocator output: `(buffer, offset, size, mapped)` slice valid until next reset. |
| `Transient_Usage` | keep | Role enum gating slice alignment and the allocator's bind-flag set. |
| `Transient_Usage_Set` | keep | Bit set baked into the allocator's backing buffer at creation. |
| `Vertex_Attribute_Desc` | keep, needs_docs, needs_test | Manual vertex layout override. |
| `Vertex_Buffer_Layout` | keep, needs_docs, needs_test | Manual vertex layout override. |
| `Vertex_Format` | keep, needs_docs | Public vertex attribute format enum. |
| `Vertex_Step_Function` | keep, needs_docs | Vertex/instance stepping enum. |
| `View` | keep | Stable handle. |
| `View_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_descriptor_contracts.ps1`. |
| `View_Kind` | keep, needs_docs | Public view shape enum used by queries/reflection. |
| `View_State` | keep, needs_docs | Query result. |
| `Wrap` | keep, needs_docs | Sampler wrap enum. |

## Audit Follow-Up Queue

1. Run the full v0.1 validation gate and review any generated API docs drift.
2. Keep generated API docs current with code comments.
