# Ape GFX Descriptor Contracts

Date: 2026-04-27

This document records the v0.1 contract for the first hardened `gfx` descriptors. These rules are enforced before backend calls unless a rule is explicitly marked backend-specific.

## Shared Rules

- `label` is optional and only used for diagnostics/native debug names.
- A zeroed descriptor is invalid unless the descriptor says which fields default from zero.
- Optional `Range` fields may be zeroed. If `ptr` is non-nil, `size` must be positive. If `size` is nonzero, `ptr` must be non-nil.
- Prefer `gfx.range(slice)` or `gfx.range(&fixed_array)` for typed data spans. Use `gfx.range_raw(ptr, size)` only for explicit raw-pointer byte ranges.
- Creation procedures return `(invalid_handle, false)` on descriptor failure and set `last_error_info(ctx)` with a typed code.
- Descriptor validation errors use `Error_Code.Validation`; unsupported but intentional gaps use `Error_Code.Unsupported`.

## Fixed-Size Slot Arrays

Ape GFX uses fixed-size arrays instead of count fields in several descriptors. The active-slot rule is explicit per descriptor:

- `Pass_Desc.color_attachments` and `Pipeline_Desc.color_formats` are packed active spans. Non-empty entries must be contiguous from slot `0`.
- `Layout_Desc.attrs` is sparse by semantic. Active attributes have a non-empty `semantic`; inactive entries may appear between active entries. Each active attribute must reference a vertex buffer slot with nonzero stride.
- `Bindings.vertex_buffers` is sparse. The active graphics pipeline determines which vertex buffer slots are required before draw.
- `Bindings.views` and `Bindings.samplers` are sparse logical shader slots. Generated shader helpers write the exact reflected logical slot. Backends with shader metadata validate missing required slots and incompatible view kinds at draw or dispatch time.

The validation suite covers packed attachment/format gaps, sparse vertex attributes, missing vertex-buffer strides, and sparse resource/sampler bindings. A later binding-group pass still needs to decide whether debug validation should reject extra unused `Bindings` entries after reflected shader metadata is known.

## Desc

`Desc` creates one `Context`.

Fields:

| Field | Contract |
| --- | --- |
| `backend` | Optional; `.Auto` defaults to `.Null` for v0.1. Use `.D3D11` for real rendering. `.Vulkan` is a visible placeholder and fails with `Error_Code.Unsupported`. |
| `width`, `height` | Optional for `.Null`; `0` is accepted. For `.D3D11`, `0` asks the backend to use its startup default size. Negative values are rejected. After initialization, `resize` requires positive dimensions. |
| `native_window` | Required for `.D3D11`. Ignored by `.Null`. |
| `swapchain_format` | Optional. `.Invalid` maps to the D3D11 backend's native default swapchain format. Samples set `.BGRA8` explicitly so pipeline/pass color formats stay readable at the public API layer. |
| `vsync` | Optional. `false` presents immediately; `true` requests synchronized presentation when the backend supports it. |
| `debug` | Optional. Requests backend diagnostics. D3D11 falls back to a non-debug device if debug device creation fails. |
| `label` | Optional diagnostic label for the context. |

Defaults:

- A zeroed `Desc` is valid and creates a `.Null` context for smoke tests and validation.
- `.Auto` resolves to `.Null` until there is more than one production backend.
- `width = 0` and `height = 0` are accepted during initialization. `resize` uses stricter positive-size validation.
- `swapchain_format = .Invalid` uses the backend default. Prefer `.BGRA8` in D3D11 samples and applications.

Rejected or unsupported:

- Negative `width` or `height`.
- `.D3D11` without a native window.
- `.Vulkan`, which is intentionally deferred.

Representative smoke-test callsite:

```odin
ctx, ok := gfx.init({
	backend = .Null,
	label = "descriptor contracts",
})
```

Representative D3D11 callsite:

```odin
ctx, ok := gfx.init({
	backend = .D3D11,
	width = fb_width,
	height = fb_height,
	native_window = app.native_window_handle(&window),
	swapchain_format = .BGRA8,
	vsync = true,
	debug = true,
	label = "game gfx",
})
```

## Buffer_Desc

`Buffer_Desc` creates one GPU buffer.

Fields:

| Field | Contract |
| --- | --- |
| `label` | Optional diagnostic label. |
| `usage` | Required. Must include at least one role flag: `Vertex`, `Index`, `Uniform`, or `Storage`. Non-storage buffers must include exactly one lifetime/update flag: `Immutable`, `Dynamic_Update`, or `Stream_Update`. `Immutable` buffers require initial data. Storage buffers are GPU-only for now and must not include update/lifetime flags. |
| `size` | Required unless inferred from `data.size`. Must be positive after inference. |
| `storage_stride` | Optional. `0` means raw storage buffer when `Storage` usage is present. Nonzero means structured storage buffer, requires `Storage`, must be 4-byte aligned, and `size` must be a multiple of the stride. |
| `data` | Initial contents. Required for `Immutable` buffers and optional otherwise. If present, the range must cover `size`. |

Defaults:

- `size = 0` plus non-empty `data` infers `size = data.size`.
- `storage_stride = 0` creates a raw storage buffer when `usage` includes `Storage`.

Unsupported or rejected:

- Storage buffers with `Immutable`, `Dynamic_Update`, or `Stream_Update`.
- Raw storage buffers whose `size` is not 4-byte aligned.
- Structured storage buffers whose `storage_stride` or total size is not aligned to the structure size.

Representative callsite:

```odin
vertex_buffer, ok := gfx.create_buffer(&ctx, {
	label = "triangle vertices",
	usage = {.Vertex, .Immutable},
	data = gfx.range(vertices[:]),
})
```

## Image_Desc

`Image_Desc` creates a texture, storage image, color attachment, or depth-stencil attachment.

Fields:

| Field | Contract |
| --- | --- |
| `label` | Optional diagnostic label. |
| `kind` | Defaults to `.Image_2D`. Only `.Image_2D` is v0.1-supported. |
| `usage` | Required. Must include at least one role flag: `Texture`, `Storage_Image`, `Color_Attachment`, or `Depth_Stencil_Attachment`. |
| `width`, `height` | Required and must be positive. |
| `depth` | Optional for `.Image_2D`; `0` defaults to `1`. Values greater than `1` are unsupported for `.Image_2D`. |
| `mip_count` | Optional; `0` defaults to `1`. Must be positive when specified and cannot exceed `MAX_IMAGE_MIPS`. |
| `array_count` | Optional; `0` defaults to `1`. Must be positive when specified. |
| `sample_count` | Optional; `0` defaults to `1`. Must be positive when specified. |
| `format` | Required. Color images require a color format. Depth-stencil images require a depth format. |
| `data` | Optional single-mip initial contents. Used as mip 0 when `mips[0]` is empty. |
| `mips` | Optional explicit immutable mip data. Mip entries beyond `mip_count` are rejected. |

Usage rules:

- `Color_Attachment` and `Depth_Stencil_Attachment` cannot be combined.
- `Storage_Image` cannot be combined with `Depth_Stencil_Attachment`.
- `Immutable` images are texture-only for now.
- Dynamic image updates require `Texture` usage.
- Dynamic storage or attachment images are not implemented yet.
- `Dynamic_Update` and `Stream_Update` cannot be combined.

Initial data rules:

- Immutable images require initial pixel data for every declared mip.
- Immutable mip data must provide enough bytes for each mip. If `row_pitch` is `0`, the minimum row pitch is inferred from `width * pixel_size`.
- `row_pitch` and `slice_pitch` must be non-negative when specified.
- If `slice_pitch` is specified for immutable data, it must cover the declared 2D mip data.
- Dynamic initial `data` is allowed only for one-mip textures and must provide enough tightly packed bytes for mip 0.
- Color attachment, storage image, and depth-stencil image creation do not accept initial data yet.
- Dynamic images do not accept mip-chain initial data; use `update_image`.

Representative callsite:

```odin
texture, ok := gfx.create_image(&ctx, {
	label = "albedo",
	usage = {.Texture, .Immutable},
	width = image_width,
	height = image_height,
	format = .RGBA8,
	data = gfx.range(pixels[:]),
})
```

## Image_Update_Desc

`Image_Update_Desc` writes CPU pixel data into a dynamic texture.

Fields:

| Field | Contract |
| --- | --- |
| `image` | Required. Must be a valid image with `Dynamic_Update` or `Stream_Update` usage. |
| `mip_level` | Optional; `0` defaults to mip 0. Must be within the image mip range. |
| `array_layer` | Optional; `0` defaults to layer 0. Must be within the image array range. |
| `x`, `y` | Optional texel offset. Must be non-negative. |
| `width`, `height` | Optional update dimensions. `0` means the full mip width or height. Must be non-negative and fit inside the selected mip. |
| `data` | Required pixel bytes. Must provide enough bytes for the update rectangle. |
| `row_pitch` | Optional bytes per source row. `0` infers a tightly packed row. Must be non-negative and at least `width * pixel_size` when specified. |

Rules:

- Only `.Image_2D` color images are updateable in v0.1.
- Multisampled images cannot be updated.
- `width = 0` and `height = 0` mean full selected mip dimensions. If `x` or `y` is nonzero, explicitly provide dimensions for a partial rectangle.

Representative callsite:

```odin
ok := gfx.update_image(&ctx, {
	image = dynamic_texture,
	width = image_width,
	height = image_height,
	data = gfx.range(pixels[:]),
})
```

## Image_Resolve_Desc

`Image_Resolve_Desc` resolves one multisampled color image into a single-sampled image.

Fields:

| Field | Contract |
| --- | --- |
| `source` | Required. Must be a valid multisampled `.Image_2D` color attachment image. |
| `destination` | Required. Must be a valid single-sampled `.Image_2D` texture or color attachment image. |

Rules:

- Source and destination formats and dimensions must match.
- Only single-mip, single-layer resolves are v0.1-supported.
- Depth resolves and multisampled sampled views remain unsupported until a real sample needs them.

Representative callsite:

```odin
ok := gfx.resolve_image(&ctx, {
	source = msaa_color,
	destination = resolved_color,
})
```

## View_Desc

`View_Desc` creates exactly one `View` handle over an existing image or buffer.

Fields:

| Field | Contract |
| --- | --- |
| `label` | Optional diagnostic label. |
| `texture` | Creates a sampled image view. Requires a valid image with `Texture` usage. `format = .Invalid` defaults to the image format. `mip_count = 0` and `layer_count = 0` default to the remaining range. |
| `storage_image` | Creates a storage image view. Requires a valid image with `Storage_Image` usage. `format = .Invalid` defaults to the image format. `layer_count = 0` defaults to the remaining range. |
| `storage_buffer` | Creates a storage buffer byte-range view. Requires a valid buffer with `Storage` usage. `size = 0` defaults to the remaining buffer range. |
| `color_attachment` | Creates a color attachment view. Requires a valid image with `Color_Attachment` usage. |
| `depth_stencil_attachment` | Creates a depth-stencil attachment view. Requires a valid image with `Depth_Stencil_Attachment` usage. |

Shared view rules:

- Exactly one nested view flavor must name a valid resource handle.
- View format must match the parent image format for now.
- Mip and layer ranges must be non-negative, non-empty after defaulting, and within the parent image range.
- Sampled views over multisampled images are rejected for now; resolve into a single-sampled texture first.
- Multisampled storage image views and depth storage image views are unsupported.
- Storage buffer view ranges must fit inside the parent buffer. Structured storage views must align to `storage_stride`; raw storage views must be 4-byte aligned.

Representative callsite:

```odin
texture_view, ok := gfx.create_view(&ctx, {
	label = "albedo sampled view",
	texture = {image = texture},
})
```

## Sampler_Desc

`Sampler_Desc` creates immutable texture sampling state.

Fields:

| Field | Contract |
| --- | --- |
| `label` | Optional diagnostic label. |
| `min_filter`, `mag_filter`, `mip_filter` | Optional; zero defaults to `.Nearest`. Must be a valid `Filter` value. |
| `wrap_u`, `wrap_v`, `wrap_w` | Optional; zero defaults to `.Repeat`. Must be a valid `Wrap` value. |

Representative callsite:

```odin
sampler, ok := gfx.create_sampler(&ctx, {
	label = "linear clamp",
	min_filter = .Linear,
	mag_filter = .Linear,
	mip_filter = .Linear,
	wrap_u = .Clamp_To_Edge,
	wrap_v = .Clamp_To_Edge,
	wrap_w = .Clamp_To_Edge,
})
```

## Shader_Desc

`Shader_Desc` is the low-level backend bytecode descriptor normally produced from an `.ashader` package.

Fields:

| Field | Contract |
| --- | --- |
| `label` | Optional diagnostic label. |
| `stages` | Required. Must contain either a vertex+fragment graphics pair or one compute stage. Empty bytecode ranges are ignored. Duplicate stages are rejected. Graphics and compute stages cannot be mixed in one shader object. |
| `has_binding_metadata` | Must be true when any `bindings` entry is active. Generated `.ashader` descriptors set this. |
| `bindings` | Optional Slang-reflected binding metadata. Active entries must reference an existing stage, valid kind, valid logical/native slots, and compatible storage metadata. |
| `has_vertex_input_metadata` | Must be true when any `vertex_inputs` entry is active. Generated `.ashader` descriptors set this. |
| `vertex_inputs` | Optional Slang-reflected vertex input metadata. Active entries require a vertex stage, non-empty semantic, valid vertex format, and unique semantic/index pair. |

Rules:

- Uniform block metadata requires a nonzero reflected size.
- Resource view metadata accepts sampled, storage image, and storage buffer view kinds only.
- Storage image metadata currently accepts `.Invalid`, `.RGBA32F`, or `.R32F` reflected formats.
- Storage buffer metadata stride must be `0` for raw buffers or 4-byte aligned.
- Most code should call `shader.shader_desc(...)` from `shader` instead of handwriting this descriptor.

Representative callsite:

```odin
shader_desc, shader_desc_ok := shader_assets.shader_desc(&shader_package, .D3D11_DXBC, "triangle shader")
shader, shader_ok := gfx.create_shader(&ctx, shader_desc)
```

## Pipeline_Desc

`Pipeline_Desc` creates immutable graphics pipeline state.

Fields:

| Field | Contract |
| --- | --- |
| `label` | Optional diagnostic label. |
| `shader` | Required. Must be a live shader from the same context containing vertex and fragment stages. Compute-only shaders are rejected. |
| `primitive_type` | Optional; zero defaults to `.Triangles`. Must be valid. |
| `index_type` | Optional; zero defaults to `.None`. Must be valid. Non-`.None` pipelines require an index buffer before indexed draw. |
| `layout` | Required when the vertex shader has reflected vertex inputs. Attributes must have non-empty semantics, valid formats, valid buffer slots, offsets inside stride, and no duplicate semantic/index pairs. |
| `color_formats` | Optional for swapchain pipelines. Non-invalid formats must be color formats and contiguous from slot 0. |
| `depth_only` | Optional; when true, depth must be enabled and no color formats may be declared. |
| `colors` | Optional color target state. `write_mask = 0` defaults to RGBA. Blend factors and ops must be valid. |
| `depth` | Optional depth state. If enabled, `format` must be a depth format. Writes require enabled depth. |
| `raster` | Optional raster state. Fill, cull, and winding values must be valid. |

Rules:

- Slang-reflected vertex inputs are checked against the manual/generated `layout` before backend creation.
- Extra layout attributes are rejected when shader vertex input metadata is present.
- Per-vertex buffers require `step_rate = 0`; per-instance buffers require nonzero `step_rate`.
- Manual `Pipeline_Desc.layout` overrides remain supported; they must still match reflected shader inputs when metadata exists.

Representative callsite:

```odin
pipeline, ok := gfx.create_pipeline(&ctx, {
	label = "triangle pipeline",
	shader = shader,
	primitive_type = .Triangles,
	layout = triangle_shader.layout_desc(),
})
```

## Compute_Pipeline_Desc

`Compute_Pipeline_Desc` creates immutable compute pipeline state.

Fields:

| Field | Contract |
| --- | --- |
| `label` | Optional diagnostic label. |
| `shader` | Required. Must be a live shader from the same context containing a compute stage and no graphics stages. |

Rules:

- The active backend must report compute support.
- Graphics shaders are rejected before backend creation.

## Binding_Group_Layout_Desc

`Binding_Group_Layout_Desc` records a generated Slang binding-group layout. It is descriptor-only for now: it validates reflected layout data, but it does not create a GPU object or replace `Bindings`.

Fields:

| Field | Contract |
| --- | --- |
| `label` | Optional diagnostic label. |
| `entries` | Sparse logical binding entries. Each active entry has a non-empty reflected name, at least one shader stage, valid binding kind, and a kind-specific logical slot. |
| `native_bindings` | Sparse backend mappings for generated entries. Each active mapping names a backend target, stage, binding kind, logical slot, native slot, and native space. |

Rules:

- Uniform entries require a nonzero reflected size.
- Resource-view entries use the same view-kind, access, storage-image-format, and storage-buffer-stride rules as `Shader_Binding_Desc`.
- Sampler entries currently have no payload.
- Duplicate logical entries with the same kind and slot are rejected.
- Native mappings must reference an existing logical entry whose stage set includes the native stage.
- Native mappings are allowed only for concrete generated backend targets such as `.D3D11` and `.Vulkan`.

Representative callsite:

```odin
layout := textured_quad_shader.binding_group_layout_desc("material bindings")
if !gfx.validate_binding_group_layout_desc(&ctx, layout) {
	fmt.eprintln("bad generated binding layout: ", gfx.last_error(&ctx))
	return
}
```

This is a stepping stone toward optional binding-group objects. Normal draw code still uses generated helpers with `gfx.Bindings`.

## Bindings

`Bindings` supplies transient buffers, resource views, and samplers for the currently active render or compute pass.

Fields:

| Field | Contract |
| --- | --- |
| `vertex_buffers` | Render passes only. Each active binding requires a live vertex-capable buffer and non-negative byte offset within the buffer. |
| `index_buffer` | Render passes only. Requires a live index-capable buffer and non-negative byte offset within the buffer. |
| `views` | Each active binding requires a live sampled or storage view. Attachment views cannot be bound as resources. |
| `samplers` | Each active binding requires a live sampler. |

Rules:

- `apply_bindings` requires an active render or compute pass.
- Resource views bound in a render pass cannot alias active pass attachments.
- Resource views in one binding set cannot create read/write or write/write hazards over the same image or overlapping buffer range.
- D3D11 additionally validates reflected required bindings, view kinds, storage access, uniform sizes, and required vertex/index buffers at draw or dispatch time.

Representative callsite:

```odin
bindings: gfx.Bindings
bindings.vertex_buffers[0] = {buffer = vertex_buffer}
bindings.index_buffer = {buffer = index_buffer}
textured_quad_shader.set_view_tex(&bindings, texture_view)
textured_quad_shader.set_sampler_smp(&bindings, sampler)
ok := gfx.apply_bindings(&ctx, bindings)
```

## Pass_Desc

`Pass_Desc` begins a render pass. It does not expose a public `Swapchain` handle in v0.1; the framework owns one implicit window swapchain per `Context`.

Fields:

| Field | Contract |
| --- | --- |
| `label` | Optional diagnostic label. |
| `color_attachments` | Optional. A contiguous set of color attachment views starting at slot 0. Empty means the implicit swapchain color target. |
| `depth_stencil_attachment` | Optional. A depth-stencil attachment view. |
| `action` | Optional load/store and clear behavior. Zeroed actions are valid, but `default_pass_action()` is the recommended starting point because it gives explicit clear/store defaults. |

Targeting rules:

- If `color_attachments` and `depth_stencil_attachment` are all invalid, `begin_pass` targets the context's implicit window swapchain.
- If any explicit color or depth-stencil attachment is supplied, `begin_pass` targets those attachment views instead.
- Multi-window and multi-swapchain support is deferred until there is a concrete API and sample that need it.
- Pass action load/store enum values must be valid.
- Depth clear values must be between `0` and `1` when the depth load action is `.Clear`.

Representative swapchain pass:

```odin
action := gfx.default_pass_action()
action.colors[0].clear_value = gfx.Color{r = 0.02, g = 0.02, b = 0.025, a = 1}

ok := gfx.begin_pass(&ctx, {
	label = "main swapchain pass",
	action = action,
})
```

## Compute_Pass_Desc

`Compute_Pass_Desc` begins a compute-only pass.

Fields:

| Field | Contract |
| --- | --- |
| `label` | Optional diagnostic label. |

Rules:

- A zeroed `Compute_Pass_Desc` is valid when the backend supports compute.
- `begin_compute_pass` requires no other pass to be active.
- The active backend must report compute support.
- Render-only bindings such as vertex and index buffers are rejected in compute passes.

## Validation

Run:

```powershell
.\tools\test_gfx_descriptor_contracts.ps1
.\tools\test_gfx_image_transfer_contracts.ps1
.\tools\test_gfx_state_descriptor_contracts.ps1
```

These tests cover representative valid defaults and invalid shapes for `Desc`, `Buffer_Desc`, `Image_Desc`, `Image_Update_Desc`, `Image_Resolve_Desc`, `View_Desc`, `Sampler_Desc`, `Shader_Desc`, `Pipeline_Desc`, `Compute_Pipeline_Desc`, `Bindings`, and `Pass_Desc` on the null backend where possible, so most contract checks run without depending on D3D11 device setup.
