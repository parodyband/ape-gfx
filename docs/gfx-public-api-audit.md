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
| `COLOR_MASK_A` | keep, needs_docs | Stable color-write mask bit. |
| `COLOR_MASK_B` | keep, needs_docs | Stable color-write mask bit. |
| `COLOR_MASK_G` | keep, needs_docs | Stable color-write mask bit. |
| `COLOR_MASK_R` | keep, needs_docs | Stable color-write mask bit. |
| `COLOR_MASK_RGB` | keep, needs_docs | Stable combined color-write mask. |
| `COLOR_MASK_RGBA` | keep, needs_docs | Stable combined color-write mask. |
| `Compute_Pipeline_Invalid` | keep | Stable invalid sentinel. |
| `Image_Invalid` | keep | Stable invalid sentinel. |
| `MAX_BINDING_GROUPS` | keep | Public logical binding group limit. |
| `MAX_BINDING_GROUP_ENTRIES` | keep | Generated binding group layout entry limit. |
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
| `Sampler_Invalid` | keep | Stable invalid sentinel. |
| `Shader_Invalid` | keep | Stable invalid sentinel. |
| `View_Invalid` | keep | Stable invalid sentinel. |

## Procedures

| Symbol | Status | v0.1 Decision |
| --- | --- | --- |
| `apply_binding_group` | keep, needs_test | Applies an object-backed binding group with optional geometry bindings. |
| `apply_binding_groups` | keep, needs_test | Applies multiple object-backed binding groups with optional geometry bindings. |
| `apply_bindings` | keep, needs_test | Core command. Expand validation tests around buffer/view/sampler slots. |
| `apply_compute_pipeline` | keep, needs_test | Core compute command. Keep if compute is v0.1-stable. |
| `apply_pipeline` | keep, needs_test | Core render command. |
| `apply_uniform` | keep, needs_docs | Ergonomic typed wrapper over `apply_uniforms`. |
| `apply_uniforms` | keep, needs_test | Core uniform upload. |
| `backend_name` | keep | Small diagnostic helper. |
| `begin_compute_pass` | keep, needs_test | Core compute command. |
| `begin_pass` | keep, needs_test | Core render command. |
| `binding_group_layout_valid` | keep, needs_test | Simple sentinel check. |
| `binding_group_valid` | keep, needs_test | Simple sentinel check. |
| `buffer_valid` | keep, needs_test | Simple sentinel check. Revisit overload group only if callsites need it. |
| `commit` | keep, needs_test | Core frame command. |
| `compute_pipeline_valid` | keep, needs_test | Simple sentinel check. |
| `create_buffer` | keep, needs_test | Primary buffer creation spelling. |
| `create_binding_group` | keep, needs_test | Primary binding group creation spelling. |
| `create_binding_group_layout` | keep, needs_test | Primary binding group layout creation spelling. |
| `create_compute_pipeline` | keep, needs_test | Primary compute pipeline creation spelling. |
| `create_image` | keep, needs_test | Primary image creation spelling. |
| `create_pipeline` | keep, needs_test | Primary graphics pipeline creation spelling. |
| `create_pipeline_layout` | keep, needs_test | Primary pipeline layout creation spelling for reflected shader bindings. |
| `create_sampler` | keep, needs_test | Primary sampler creation spelling. |
| `create_shader` | keep, needs_docs | Primary low-level shader creation spelling. Most users should arrive through `.ashader`. |
| `create_view` | keep, needs_test | Primary view creation spelling. |
| `default_pass_action` | keep, needs_docs | Stable default helper. Document clear/store defaults. |
| `destroy_buffer` | keep | Explicit destroy remains available. |
| `destroy_binding_group` | keep | Explicit destroy remains available. |
| `destroy_binding_group_layout` | keep | Explicit destroy remains available. |
| `destroy_compute_pipeline` | keep | Explicit destroy remains available. |
| `destroy_image` | keep | Explicit destroy remains available. |
| `destroy_pipeline` | keep | Explicit destroy remains available. |
| `destroy_pipeline_layout` | keep | Explicit destroy remains available. |
| `destroy_sampler` | keep | Explicit destroy remains available. |
| `destroy_shader` | keep | Explicit destroy remains available. |
| `destroy_view` | keep | Explicit destroy remains available. |
| `dispatch` | keep, needs_test | Core compute command. |
| `draw` | keep, needs_test | Core render command. |
| `end_compute_pass` | keep, needs_test | Core compute command. |
| `end_pass` | keep, needs_test | Core render command. |
| `image_valid` | keep, needs_test | Simple sentinel check. |
| `init` | keep | Context creation is covered by `tools/test_gfx_descriptor_contracts.ps1`. |
| `last_error` | keep | Human-readable diagnostics. |
| `last_error_code` | keep, needs_test | Keep after Phase 3 makes codes explicit. |
| `last_error_info` | keep, needs_test | Keep after Phase 3 makes codes explicit. |
| `pipeline_valid` | keep, needs_test | Simple sentinel check. |
| `pipeline_layout_valid` | keep, needs_test | Simple sentinel check. |
| `query_backend_limits` | keep, needs_docs | Stable name. Document difference from `query_limits`. |
| `query_buffer_state` | keep, needs_test | Public read-only validation/diagnostic helper. |
| `query_features` | keep, needs_docs | Stable name. |
| `query_image_state` | keep, needs_test | Public read-only validation/diagnostic helper. |
| `query_limits` | keep, needs_docs | Stable name. Document public fixed limits. |
| `query_view_buffer` | keep, needs_docs | Convenience helper over `query_view_state`. |
| `query_view_compatible` | keep, needs_test | Useful validation helper. |
| `query_view_image` | keep, needs_docs | Convenience helper over `query_view_state`. |
| `query_view_state` | keep, needs_test | Public read-only validation/diagnostic helper. |
| `range_raw` | keep | Useful raw-pointer escape hatch. Primary docs should prefer typed `range` when possible. |
| `read_buffer` | keep, needs_test | Synchronous readback is v0.1-stable if documented as blocking. |
| `resize` | keep, needs_test | Stable swapchain resize entry point. |
| `resolve_image` | keep, needs_test | Stable MSAA color resolve command. |
| `sampler_valid` | keep, needs_test | Simple sentinel check. |
| `shader_valid` | keep, needs_test | Simple sentinel check. |
| `shutdown` | keep, needs_test | Context teardown and leak reporting. |
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
| `Binding_Group` | keep | Stable binding group handle. |
| `Binding_Group_Desc` | keep | Binding group creation descriptor for generated resource views and samplers. Uniforms are still applied separately. |
| `Binding_Group_Layout` | keep | Stable binding group layout handle. |
| `Binding_Group_Layout_Desc` | keep | Generated binding group layout data used by `create_binding_group_layout`. |
| `Binding_Group_Layout_Entry_Desc` | keep | Logical generated binding entry descriptor. |
| `Binding_Group_Native_Binding_Desc` | keep | Backend/stage native slot mapping for generated binding layouts. |
| `Binding_Group_Resource_View_Layout_Desc` | keep | Resource-view payload for generated binding layout entries. |
| `Binding_Group_Uniform_Block_Layout_Desc` | keep | Uniform-block payload for generated binding layout entries. |
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
| `Buffer_Usage` | keep | Public bit set. |
| `Buffer_Usage_Flag` | keep, needs_docs | Public bit set values. |
| `Color` | keep | Basic pass clear color type. |
| `Color_Attachment_Action` | keep, needs_docs | Pass action descriptor. |
| `Color_Attachment_View_Desc` | keep | Covered as part of `View_Desc` contract. |
| `Color_State` | keep, needs_docs | Pipeline color target state. |
| `Compare_Func` | keep, needs_docs | Depth state enum. |
| `Compute_Pass_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md`; D3D11 compute behavior is covered by `tools/test_d3d11_compute_pass.ps1`. |
| `Compute_Pipeline` | keep | Stable handle if compute remains v0.1-stable. |
| `Compute_Pipeline_Desc` | keep | Contract documented in `docs/gfx-descriptor-contracts.md` and covered by `tools/test_gfx_state_descriptor_contracts.ps1`. |
| `Context` | keep, needs_docs | Public context value. Intent is opaque even though Odin exposes the type. |
| `Cull_Mode` | keep, needs_docs | Raster state enum. |
| `Depth_Attachment_Action` | keep, needs_docs | Pass action descriptor. |
| `Depth_State` | keep, needs_docs | Pipeline depth state. |
| `Depth_Stencil_Attachment_View_Desc` | keep | Covered as part of `View_Desc` contract. |
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
| `Primitive_Type` | keep | Pipeline topology enum. |
| `Range` | keep | Raw byte span for uploads/readback/bytecode. |
| `Raster_State` | keep, needs_docs | Pipeline raster state. |
| `Sampler` | keep | Stable handle. |
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
| `Texture_View_Desc` | keep | Covered as part of `View_Desc` contract. |
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
