# Ape GFX v0.1 Contract

Date: 2026-04-28

This document defines the intended `v0.1` contract for `gfx`. It is the line between the low-level graphics framework we are hardening and the engine or renderer layers we are intentionally not building yet.

`v0.1` is D3D11-first. Vulkan, Linux, compressed texture assets, renderer systems, and higher-level game framework decisions stay outside this contract until the D3D11-backed API stops moving.

## Contract Status

### Stable For v0.1

Stable means user code should be able to rely on the shape for normal `v0.1` use. We can still fix bugs and improve diagnostics without changing the public call pattern.

- `gfx` remains the public low-level graphics package.
- One `gfx.Context` owns backend state, the implicit window swapchain, resources, command state, and diagnostics.
- Resource handles are opaque generational IDs. Zero is always invalid.
- Resource lifetime is explicit: create with `create_*`, release with `destroy` or `destroy_*`.
- Primary creation procedures return `(handle, ok)`.
- Sokol-style `make_*` helpers remain compatibility aliases, but primary samples should use `create_*`.
- The render command flow is `begin_pass`, `apply_pipeline`, `apply_bindings`, `apply_uniforms`, `draw`, `end_pass`, `commit`.
- The compute command flow is `begin_compute_pass`, `apply_compute_pipeline`, `apply_bindings`, `dispatch`, `end_compute_pass`.
- Buffers, images, views, samplers, shaders, graphics pipelines, and compute pipelines are public resource types.
- `View` is the single public view handle for sampled textures, storage images, storage buffers, color attachments, and depth-stencil attachments.
- Descriptors use Odin struct literals, `bit_set` usage flags, and zero-value defaults only where documented.
- Runtime validation fails before backend calls for invalid descriptors, invalid handles, incompatible views, pass ordering mistakes, and reflected shader binding mismatches.
- Programmatic errors use `gfx.Error_Code` through `last_error_code` and `last_error_info`.
- Human-readable errors remain available through `last_error`.
- Public query helpers expose backend-free state through `query_features`, `query_limits`, `query_backend_limits`, and `query_*_state`.
- Slang is the shader authoring and reflection source.
- `.ashader` packages loaded through `shader` are the expected runtime shader input.
- Generated Slang bindings are the recommended way to set resource slots, uniform blocks, compute dispatch sizing, and simple vertex layouts.
- D3D11 is the production backend for this contract.
- `Null` is stable for command-flow smoke tests.

### Provisional

Provisional means the feature exists and is useful, but we expect to refine details before a stronger compatibility promise.

- The binary `.ashader` container format can still change before a tagged release.
- Generated binding helper names for documented v0.1 shader shapes are listed in `docs/gfx-slang-reflection-contract.md`; less common future shapes may still refine helper naming.
- D3D11 compute, storage image views, and storage buffer views are present, but the storage/compute surface should keep evolving only from real use cases.
- `app` is a minimal sample/windowing facade. It is not the long-term platform contract.
- `samples/ape_sample` shader reload helpers are dev/sample utilities, not core `gfx` API.
- Generated API Markdown format under `docs/api` is a validation aid. The public API is the Odin package itself.
- Vulkan SPIR-V output from `ape_shaderc` is useful for future backend work, but no Vulkan runtime contract exists yet.

### Unsupported In v0.1

Unsupported means user code should not depend on it. If a call path exists accidentally, it is not part of the contract.

- Vulkan backend execution.
- Linux windowing/platform support.
- Web, mobile, OpenGL, Metal, D3D12, or WebGPU targets.
- Multiple windows or multiple public swapchains.
- Hidden global graphics contexts.
- Automatic GPU resource lifetime management.
- Renderer, material, camera, scene, asset database, or gameplay framework layers.
- Bindless resources and descriptor arrays.
- Graphics-pass UAV/storage writes.
- Async shader compilation or async hot reload.
- KTX2/Basis texture pipeline.
- Public backend-native object access.
- 3D textures, cube textures, and image arrays as supported image kinds.
- Multisampled sampled views. Resolve first, then sample the single-sampled image.
- Depth resolves.
- Tessellation and geometry shader stages.
- Indirect draws or dispatches.
- Deferred D3D11 contexts or multithreaded command recording.
- Vulkan-style explicit barriers, queues, command buffers, descriptor sets, or image layouts in the public API.

## Public Package Boundary

The supported package boundary is:

- `gfx`: public low-level graphics API.
- `shader`: `.ashader` package loading and conversion to `gfx.Shader_Desc`.
- `app`: sample-grade desktop window creation and native-window access.

Backend implementation files, generated build outputs, and sample helper packages are not part of the stable framework API.

Reference docs:

- `docs/api/markdown/gfx.md`
- `docs/gfx-public-api-audit.md`
- `docs/gfx-descriptor-contracts.md`
- `docs/gfx-slang-reflection-contract.md`
- `docs/gfx-error-model.md`

## Integration Model

Use the repo as an Odin collection:

```powershell
odin build samples\d3d11_triangle -collection:ape="D:\path\to\ape_gfx"
```

A normal application imports the public packages:

```odin
import app "ape:app"
import gfx "ape:gfx"
import shader_assets "ape:shader"
```

Generated shader bindings are imported per shader:

```odin
import triangle_shader "ape:assets/shaders/generated/triangle"
```

Compile shaders before running samples or applications:

```powershell
.\tools\compile_shaders.ps1 -ShaderName triangle
```

The runtime load path is:

```odin
pkg, pkg_ok := shader_assets.load("build/shaders/triangle.ashader")
defer shader_assets.unload(&pkg)

shader_desc, shader_desc_ok := shader_assets.shader_desc(&pkg, .D3D11_DXBC, "triangle shader")
shader, shader_ok := gfx.create_shader(&ctx, shader_desc)
```

## Context And Backend Contract

Create one context from `gfx.Desc`:

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

Rules:

- `.D3D11` is the real backend.
- `.Null` is for tests and smoke validation.
- `.Vulkan` is not implemented.
- `native_window` must name a valid platform window for D3D11.
- `resize(&ctx, width, height)` recreates swapchain-dependent resources after a framebuffer resize.
- `shutdown(&ctx)` releases backend state and reports leaked resources through `last_error_info`.

## Resource Contract

Resource creation follows one pattern:

```odin
buffer, ok := gfx.create_buffer(&ctx, {
	label = "mesh vertices",
	usage = {.Vertex, .Immutable},
	data = gfx.range(vertices[:]),
})
if !ok {
	fmt.eprintln("buffer creation failed: ", gfx.last_error(&ctx))
	return
}
defer gfx.destroy(&ctx, buffer)
```

Stable resources:

- `Buffer`
- `Image`
- `View`
- `Sampler`
- `Shader`
- `Pipeline`
- `Compute_Pipeline`

Stable resource rules:

- Handles are context-owned. A handle from one context is invalid in another.
- Destroyed handles become stale.
- `destroy` is overloaded for all public resource handles.
- `query_*_state` returns backend-free state for diagnostics and validation.
- Labels are optional and used for diagnostics/native debug names.

Descriptor details live in `docs/gfx-descriptor-contracts.md`. That document is the source of truth for zero-value behavior, required fields, defaults, and rejected shapes.

## View Contract

`View` is intentionally first-class. Images and buffers do not bind directly as shader resources or attachments.

Stable view flavors:

- `texture`: sampled image view.
- `storage_image`: storage image view.
- `storage_buffer`: storage buffer byte-range view.
- `color_attachment`: render-target view.
- `depth_stencil_attachment`: depth-stencil view.

Rules:

- Exactly one `View_Desc` flavor may be populated.
- Sampled and storage views are bound through generated binding groups or `Bindings.views`.
- Attachment views are used only in `Pass_Desc`.
- Runtime validation rejects a sampled view in a storage slot, a storage view in a sampled slot, and attachment views in resource binding slots.
- Views must not create read/write hazards inside one pass or dispatch.

## Render Pass Contract

The stable render path is:

```odin
action := gfx.default_pass_action()
action.colors[0].clear_value = gfx.Color{r = 0.02, g = 0.02, b = 0.025, a = 1}

gfx.begin_pass(&ctx, {
	label = "main pass",
	action = action,
})
gfx.apply_pipeline(&ctx, pipeline)
gfx.apply_bindings(&ctx, bindings)
triangle_shader.apply_uniform_FrameUniforms(&ctx, &uniforms)
gfx.draw(&ctx, 0, vertex_count)
gfx.end_pass(&ctx)
gfx.commit(&ctx)
```

Rules:

- A pass with no explicit attachments targets the implicit window swapchain.
- Explicit offscreen passes use color/depth attachment `View` handles.
- Color attachments must be contiguous from slot 0.
- Pipeline color/depth formats must match the active pass shape.
- `draw` is indexed when the active pipeline has a non-`.None` `index_type`.
- `commit` presents the implicit swapchain and advances the frame.

## Compute Contract

The stable compute path is:

```odin
gfx.begin_compute_pass(&ctx, {label = "compute"})
gfx.apply_compute_pipeline(&ctx, compute_pipeline)
gfx.apply_bindings(&ctx, bindings)
compute_shader.dispatch_threads(&ctx, width, height)
gfx.end_compute_pass(&ctx)
```

Rules:

- The active backend must report `query_features(&ctx).compute`.
- Compute shaders must be separate from graphics shaders.
- Render-only bindings such as vertex and index buffers are rejected in compute passes.
- Storage buffers and storage images bind through reflected binding groups or `Bindings.views` slots.
- Readback is explicit through `read_buffer`.

## Shader Contract

Slang is the shader source language. Runtime code does not compile Slang directly.

Stable shader flow:

1. Author `.slang` files under `assets/shaders`.
2. Compile with `tools/compile_shaders.ps1`.
3. Load `.ashader` packages with `shader`.
4. Create `gfx.Shader` from `gfx.Shader_Desc`.
5. Use generated bindings for layouts, uniforms, slots, and compute dispatch sizing.

Stable generated helpers:

- Binding slot constants such as `VIEW_ape_texture`.
- Logical group constants such as `GROUP_0`.
- Reflected D3D11 native slot constants such as `D3D11_FS_VIEW_ape_texture`.
- View metadata constants such as `VIEW_KIND_*`, `VIEW_ACCESS_*`, `VIEW_FORMAT_*`, and `VIEW_STRIDE_*`.
- Uniform structs and `apply_uniform_*` helpers when reflection is representable.
- Simple packed vertex layout helpers such as `VERTEX_STRIDE`, `ATTR_*_OFFSET`, and `layout_desc`.
- Binding group layout descriptors such as `binding_group_layout_desc`, used with `gfx.create_binding_group_layout`.
- Binding group resource setters such as `set_group_view_*` and `set_group_sampler_*`.
- `ParameterBlock<>` resource groups mapped to generated logical groups.
- Compute thread-group constants and dispatch helpers.

Generated resource binding support is intentionally narrow. `Texture2D`, `RWTexture2D`, samplers, raw storage buffers, and structured storage buffers are covered. Cube textures, 3D textures, image arrays, resource arrays, and bindless-style layouts are rejected until the public view and binding model can represent them directly.

Generated vertex layout support is intentionally narrow:

- `float` maps to `.Float32`.
- `float2` maps to `.Float32x2`.
- `float3` maps to `.Float32x3`.
- `float4` maps to `.Float32x4`.

Manual `Pipeline_Desc.layout` overrides remain supported for compact formats, multiple streams, instancing, and custom vertex layouts. They still must match reflected shader inputs when metadata exists.

## Error Contract

Stable error categories:

- `None`
- `Validation`
- `Unsupported`
- `Invalid_Handle`
- `Wrong_Context`
- `Stale_Handle`
- `Backend`
- `Device_Lost`
- `Resource_Leak`

Use:

```odin
info := gfx.last_error_info(&ctx)
fmt.eprintln("gfx failed: ", info.code, " ", info.message)
```

Rules:

- Creation procedures return invalid handles and `false` on failure.
- Command procedures return `false` on failure.
- Error codes are set explicitly, not inferred from message strings.
- Human messages can become more specific without changing the code category.

The detailed contract lives in `docs/gfx-error-model.md`.

## Validation Contract

Run the full local gate before treating a change as compatible:

```powershell
.\tools\validate_all.ps1
```

This gate:

- compiles checked-in shaders
- regenerates/checks public API docs
- validates the public API audit
- validates descriptor, range, error, handle, image transfer, and state contracts
- validates D3D11 backend limits, error codes, transfers, storage, compute, resource hazards, and reflected binding failures
- builds every D3D11 sample
- runs every D3D11 sample with `-AutoExitFrames 5`
- runs `git diff --check`

The realistic usage sample is:

```powershell
.\tools\run_d3d11_gfx_lab.ps1 -AutoExitFrames 5
```

That sample is the main API ergonomics test for `v0.1`.

## Tag Criteria

For v0.1, require:

- Current generated API docs.
- A clean `tools/validate_all.ps1` run on 2026-04-28.

The `v0.1` tag should point at a clean commit with any generated docs drift already committed.
