# Ape GFX v0.1 Release Notes

Date: 2026-04-29

Status: v0.1 release notes for the current D3D11-first `gfx` contract.

`v0.1` is the point where Ape GFX stops being a loose prototype and becomes a usable low-level graphics API surface. It is still intentionally narrow: D3D11 on Windows is the real backend, Slang is the shader path, and the API is scoped to the graphics abstraction rather than a full engine or renderer.

## What This Release Is

Ape GFX `v0.1` is a desktop-first Odin graphics framework layer with:

- Sokol-like command flow.
- Explicit resource handles.
- Odin-native descriptor literals and `bit_set` usage flags.
- First-class resource views.
- Slang-authored shaders and generated Odin bindings.
- D3D11-backed rendering, compute, storage views, and validation.
- A normal validation command that builds and runs every checked-in D3D11 sample.

The contract is documented in `docs/gfx-v0.1-contract.md`.

## What You Can Build With It

This release is meant for a renderer or desktop game layer that wants to own higher-level decisions itself. The supported use case is:

- create a desktop window with `app`
- initialize one D3D11 `gfx.Context`
- create buffers, images, views, samplers, shaders, and pipelines
- render to the implicit window swapchain or explicit offscreen attachments
- create common offscreen color/depth targets with `Render_Target_Desc`
- sample offscreen color and depth targets
- run D3D11 compute passes with storage image or storage buffer views
- validate shader bindings, vertex layouts, uniforms, and pass compatibility from Slang metadata

The main proof point is:

```powershell
.\tools\run_d3d11_gfx_lab.ps1 -AutoExitFrames 5
```

That sample renders a depth-tested cube into an offscreen color/depth target, then samples the result in a swapchain pass. It uses generated Slang layouts, generated binding helpers, uniform updates, resize handling, and runtime shader reload through the shared sample helper.

## Stable In v0.1

The stable API surface is the low-level `gfx` package:

- `Context`
- `Buffer`
- `Image`
- `View`
- `Sampler`
- `Shader`
- `Pipeline`
- `Compute_Pipeline`
- `Render_Target`
- descriptor-driven `create_*` procedures returning `(handle, ok)`
- explicit `destroy` and `destroy_*` resource lifetime
- `begin_pass`, `apply_pipeline`, `apply_bindings`, `apply_uniforms`, `draw`, `end_pass`, `commit`
- `begin_compute_pass`, `apply_compute_pipeline`, `dispatch`, `end_compute_pass`
- `query_features`, `query_limits`, `query_backend_limits`, and `query_*_state`
- `last_error`, `last_error_code`, and `last_error_info`

`create_*` is the only public resource creation spelling. Earlier handle-only `make_*` aliases were removed before `v0.1-alpha` because the API is still pre-1.0 and failures should be explicit at the callsite.

## Shader Pipeline

Slang is the shader authoring language for this release.

The normal flow is:

1. Write `.slang` files under `assets/shaders`.
2. Compile with `tools/ape`, usually through `odin run .\tools\ape -- shader compile`.
3. Load `.ashader` packages through `shader`.
4. Create `gfx.Shader` handles from `gfx.Shader_Desc`.
5. Use generated Odin bindings for slots, uniforms, vertex layouts, and compute dispatch sizing.

Generated bindings currently cover:

- backend-neutral logical binding slots
- logical binding groups for `ParameterBlock<>` resources
- D3D11 native resource slots
- sampled texture and sampler bindings
- generated binding group layout helpers and resource setters
- generated pipeline layout helpers and explicit `gfx.Pipeline_Layout` handles
- active pipeline-layout validation for supplied transient `gfx.Bindings` views and samplers
- uniform block structs and `apply_uniform_*` helpers
- simple packed vertex layout helpers
- storage image and storage buffer metadata
- compute thread-group constants and dispatch helpers

Generated shader resource support is intentionally limited to shapes the public API can represent: `Texture2D`, `RWTexture2D`, samplers, raw storage buffers, and structured storage buffers.

Resource arrays and bindless-style declarations are rejected by `ape_shaderc` until `gfx` has an explicit binding-array contract.

Manual `Pipeline_Desc.layout` overrides remain supported for real engine use cases such as compact vertex formats, multiple vertex streams, instancing, or custom semantic conventions.

## D3D11 Backend

The D3D11 backend proves the current public API with:

- swapchain rendering
- resizing and swapchain recreation
- vertex and index buffers
- immutable and dynamic textures
- mip chains
- sampled texture views
- color attachment views
- depth-stencil attachment views
- low-level `Render_Target` creation helpers for common offscreen targets
- sampled depth textures
- multiple render targets
- MSAA color resolve
- storage image views
- raw and structured storage buffer views
- compute pipelines and compute passes
- storage-buffer readback
- D3D11 debug names from descriptor labels
- shared validation that rejects transient resource bindings with wrong groups, wrong slots, wrong view kinds, or incompatible storage metadata before backend binding
- shared compute hazard validation that rejects read-after-write across dispatches inside one compute pass
- validation before backend calls where possible

The `Null` backend remains useful for smoke tests. The Vulkan backend is scaffolded but not implemented.

## Validation

The default validation command is:

```powershell
odin run .\tools\ape -- validate full
```

The Windows wrapper delegates to the same Odin validation path:

```powershell
.\tools\validate_all.ps1
```

The core/tooling validation command is:

```powershell
odin run .\tools\ape -- validate core
```

The Windows wrapper delegates to the same Odin validation path:

```powershell
.\tools\validate_core.ps1
```

It validates the release by:

- compiling every checked-in shader
- running the null-backend smoke sample
- regenerating and checking public API docs
- checking the public API audit
- testing descriptor contracts
- testing typed error codes
- testing range helpers, handle lifecycle, image transfers, and state descriptors
- testing D3D11 backend limits, error codes, buffer transfers, compute, invalid layouts, invalid uniforms, invalid view kinds, resource hazards, compute read-after-write rejection, and storage views
- testing shader compiler rejection and metadata paths
- testing resource-array rejection in shader generation
- testing sample shader hot reload
- building every D3D11 sample
- running every D3D11 sample with `-AutoExitFrames 5`
- running `git diff --check`

`validate_core.ps1` runs the shader compilation, generated docs, null/core contract, shaderc, and hot-reload tooling checks without creating a D3D11 device or building/running D3D11 samples.

The validation suite passed locally for v0.1 on 2026-04-29.

## Samples

Current D3D11 samples:

| Sample | Script | Purpose |
| --- | --- | --- |
| Clear | `tools/run_d3d11_clear.ps1` | Window, swapchain, clear, present |
| Minimal Triangle | `tools/run_d3d11_triangle_minimal.ps1` | Smallest D3D11 triangle path with explicit setup |
| Triangle | `tools/run_d3d11_triangle.ps1` | Vertex buffer, generated layout, uniforms |
| Cube | `tools/run_d3d11_cube.ps1` | Indexed drawing, depth, resize-safe projection |
| Textured Quad | `tools/run_d3d11_textured_quad.ps1` | Immutable mip texture, sampled view, sampler |
| Textured Cube | `tools/run_d3d11_textured_cube.ps1` | JPG conversion sample path plus textured 3D draw |
| Dynamic Texture | `tools/run_d3d11_dynamic_texture.ps1` | Dynamic texture updates across mip levels |
| Render To Texture | `tools/run_d3d11_render_to_texture.ps1` | Offscreen color attachment then sampled texture |
| Depth Render To Texture | `tools/run_d3d11_depth_render_to_texture.ps1` | Offscreen depth/color pass and depth visualization |
| MRT | `tools/run_d3d11_mrt.ps1` | Two color attachments written in one pass |
| MSAA Resolve | `tools/run_d3d11_msaa.ps1` | 4x MSAA target resolved into a sampled texture |
| GFX Lab | `tools/run_d3d11_gfx_lab.ps1` | Realistic v0.1 API composition sample |
| Improved Shadows | `tools/run_d3d11_improved_shadows.ps1` | Multi-pass shadow map with separate generated material and shadow-resource groups |

## Compatibility Notes

If you were using earlier prototype code:

- Replace any old `make_*` callsites with `create_*` and handle the returned `ok` value.
- Create `View` handles explicitly. Images and buffers do not bind directly as shader resources or attachments.
- Use generated Slang `layout_desc()` helpers for simple packed vertex layouts.
- Use generated binding setters/constants instead of handwritten view and sampler slot numbers.
- Check `last_error_info` when a command returns `false`; the typed `Error_Code` is now the stable programmatic category.
- Use `gfx_app` for shader-program setup, resize handling, binding layout ownership, fail-fast sample calls, sample texture assets, and hot reload. Helper names are still easier to change than the low-level `gfx` contract while the project is pre-1.0.

## Known Limits

These are intentional `v0.1` limits:

- D3D11 is the only implemented runtime backend.
- Vulkan execution is deferred.
- Linux support is deferred.
- Web and mobile targets are out of scope.
- One implicit window swapchain per context.
- No public multi-window or multi-swapchain API.
- No hidden global graphics context.
- No automatic GPU resource lifetime management.
- No renderer/material/camera/gameplay framework layer.
- No KTX2/Basis texture pipeline yet.
- No async shader compilation or async hot reload.
- No bindless/resource arrays.
- No graphics-pass UAV/storage writes.
- No public backend-native object access.
- No tessellation or geometry shader stages.
- No indirect draws or dispatches.
- No D3D11 deferred contexts or multithreaded command recording.

## Still Provisional

These pieces exist, but should not be treated as long-term frozen yet:

- `.ashader` binary container versioning.
- Generated binding helper naming for less common shader shapes beyond the documented v0.1 contract.
- Storage and compute ergonomics beyond the current D3D11 compute samples.
- `app` as a sample-grade windowing layer.
- `gfx_app` helper names, especially shader reload helpers.
- Generated Markdown API docs format.

## Deferred Work

After v0.1-alpha, the next larger areas are:

- sketch resource-array and bindless reflection before freezing the group record shape further
- improve storage and compute ergonomics beyond the current samples
- add platform-neutral wrappers for null-backend validation, shader compilation, docs, and contract tests
- add Vulkan backend parity as an API pressure test after the D3D11 API feels boring
- replace sample texture conversion with a real KTX2/Basis asset path later
- revisit async shader hot reload after the shader dependency model is clearer

## Release Checklist

For `v0.1`, the tagged commit should have:

- `docs/gfx-v0.1-contract.md` is current.
- `docs/gfx-v0.1-release-notes.md` is current.
- Generated API docs are current and committed.
- `tools/validate_all.ps1` passes.
