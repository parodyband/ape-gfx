# Ape GFX

Ape GFX is a low-level graphics API for desktop games written in Odin.

The API is Sokol-like on purpose. You create explicit resource handles, describe resources with Odin struct literals, issue immediate render commands, and keep resource lifetime under your control. The goal is not to clone Sokol, though. Sokol is designed as a broad portability layer where web, mobile, desktop, and multiple graphics APIs all matter. That is a good tradeoff for many tools, but it becomes limiting when the target is a high-end desktop renderer.

Ape GFX takes a narrower position: desktop-native first, modern explicit graphics concepts, and no web or mobile constraints. The long-term direction is closer to a WebGPU-style contract for resource views, binding layouts, validation, and shader reflection, but aimed at native desktop development instead of the browser sandbox. Slang is the shader language and reflection source. D3D11 is the working backend. Vulkan is still a future pressure test, not current work.

This repo is not trying to be a full game engine yet. No renderer layer, no material system, no scene graph, no web or mobile targets.

## Current status

`gfx` now has a `v0.1` graphics API contract:

- explicit handles for `Buffer`, `Image`, `View`, `Sampler`, `Shader`, `Pipeline`, `Compute_Pipeline`, `Binding_Group_Layout`, and `Binding_Group`
- Odin-style `create_*` procedures that return `(handle, ok)`
- `destroy` overloads for public resource handles
- descriptor literals and `bit_set` usage flags
- one public `View` handle for sampled textures, storage images, storage buffers, color attachments, and depth-stencil attachments
- render passes, compute passes, offscreen targets, depth, MRT, MSAA resolve, dynamic texture updates, storage views, and buffer readback on D3D11
- Slang-generated bindings for resource slots, `ParameterBlock<>` binding groups, uniform helpers, simple vertex layouts, storage metadata, and compute dispatch sizing
- typed error reporting through `gfx.last_error_code` and `gfx.last_error_info`
- generated API docs and a full validation script

The current contract lives in `docs/gfx-v0.1-contract.md`. The release notes live in `docs/gfx-v0.1-release-notes.md`.

## Requirements

- Odin on `PATH`
- Windows PowerShell
- Windows with Direct3D 11 for GPU samples
- Slang shared libraries available to `tools/ape_shaderc`

Shader compilation uses the Slang API through `tools/ape_shaderc`. The old `slangc` command-line path is not the main path anymore.

## Quick start

Run the null-backend smoke check:

```powershell
.\tools\build_smoke.ps1
```

Run the realistic D3D11 API sample for five frames:

```powershell
.\tools\run_d3d11_gfx_lab.ps1 -AutoExitFrames 5
```

Run the full validation gate:

```powershell
.\tools\validate_all.ps1
```

`validate_all.ps1` compiles shaders, regenerates/checks public API docs, runs contract tests, builds every D3D11 sample, runs every D3D11 sample with `-AutoExitFrames 5`, and finishes with `git diff --check`.

## API shape

The render loop is intentionally small:

```odin
gfx.begin_pass(&ctx, {
	label = "main pass",
	action = gfx.default_pass_action(),
})

gfx.apply_pipeline(&ctx, pipeline)
gfx.apply_bindings(&ctx, bindings)
triangle_shader.apply_uniform_FrameUniforms(&ctx, &frame_uniforms)
gfx.draw(&ctx, 0, vertex_count)

gfx.end_pass(&ctx)
gfx.commit(&ctx)
```

The compute path uses the same binding model:

```odin
gfx.begin_compute_pass(&ctx, {label = "compute"})
gfx.apply_compute_pipeline(&ctx, compute_pipeline)
gfx.apply_bindings(&ctx, bindings)
compute_shader.dispatch_threads(&ctx, width, height)
gfx.end_compute_pass(&ctx)
```

Resource creation is explicit:

```odin
vertex_buffer, ok := gfx.create_buffer(&ctx, {
	label = "triangle vertices",
	usage = {.Vertex, .Immutable},
	data = gfx.range(vertices[:]),
})
if !ok {
	fmt.eprintln("vertex buffer failed: ", gfx.last_error(&ctx))
	return
}
defer gfx.destroy(&ctx, vertex_buffer)
```

## Packages

- `gfx`: public graphics API, validation, and backend dispatch
- `shader`: `.ashader` loading and conversion to `gfx.Shader_Desc`
- `app`: small window/event layer used by samples
- `tools/ape_shaderc`: Slang compiler/package tool
- `samples/ape_sample`: provisional app-facing helper layer used by samples for resize handling, shader-program setup, binding layout ownership, and shader reload
- `samples/ape_math`: sample-only matrix helpers

`gfx`, `shader`, and the sample-grade `app` package are the stable current boundary. `samples/ape_sample` is the practical helper path used by samples today; the reusable parts are being promoted into a supported companion package instead of staying sample-only.

## Shaders

Shader sources live in `assets/shaders/*.slang`.

Compile one shader package:

```powershell
.\tools\compile_shaders.ps1 -ShaderName textured_quad
```

Compile a compute shader package:

```powershell
.\tools\compile_shaders.ps1 -ShaderName my_compute_shader -Kind compute
```

Each compile writes:

- D3D11 DXBC bytecode
- Vulkan SPIR-V bytecode for later backend work
- `build/shaders/<name>.ashader`
- generated Odin bindings in `assets/shaders/generated/<name>/bindings.odin`

Generated bindings are the preferred way to use shader slots, `ParameterBlock<>` resource groups, uniforms, simple vertex layouts, and compute dispatch helpers. Manual `Pipeline_Desc.layout` overrides still exist for compact vertex formats, instancing, multiple streams, and other engine-level layouts.

## Samples

Each D3D11 sample has a build script and a run script. Run scripts accept `-AutoExitFrames 5`.

| Sample | Script | What it proves |
| --- | --- | --- |
| Clear | `tools/run_d3d11_clear.ps1` | Window, swapchain, clear, present |
| Minimal Triangle | `tools/run_d3d11_triangle_minimal.ps1` | Smallest D3D11 triangle path |
| Triangle | `tools/run_d3d11_triangle.ps1` | Vertex buffer, generated layout, uniforms |
| Cube | `tools/run_d3d11_cube.ps1` | Indexed drawing, depth, resize-safe projection |
| Textured Quad | `tools/run_d3d11_textured_quad.ps1` | Immutable mip texture, sampled view, sampler |
| Textured Cube | `tools/run_d3d11_textured_cube.ps1` | Temporary JPG-to-APTX texture path plus 3D draw |
| Dynamic Texture | `tools/run_d3d11_dynamic_texture.ps1` | `gfx.update_image` across mip levels |
| Render To Texture | `tools/run_d3d11_render_to_texture.ps1` | Offscreen color attachment sampled later |
| Depth Render To Texture | `tools/run_d3d11_depth_render_to_texture.ps1` | Offscreen depth/color pass and sampled depth |
| MRT | `tools/run_d3d11_mrt.ps1` | Two color attachments in one pass |
| MSAA Resolve | `tools/run_d3d11_msaa.ps1` | 4x MSAA target resolved into a sampled texture |
| GFX Lab | `tools/run_d3d11_gfx_lab.ps1` | Non-trivial v0.1 usage path |
| Improved Shadows | `tools/run_d3d11_improved_shadows.ps1` | Multi-pass depth shadow map with separate generated material and shadow-resource groups |

`d3d11_gfx_lab` is the main API ergonomics sample. It renders a depth-tested cube into offscreen color/depth targets, then samples the color target in a swapchain pass.

## Docs

Use these as the active docs:

- `docs/gfx-v0.1-contract.md`: what is stable, provisional, and unsupported
- `docs/gfx-v0.1-release-notes.md`: current v0.1 release snapshot
- `docs/gfx-descriptor-contracts.md`: descriptor defaults, required fields, and rejected shapes
- `docs/gfx-error-model.md`: stable typed error codes
- `docs/gfx-public-api-audit.md`: public symbol inventory and status
- `docs/api/README.md`: generated API docs index
