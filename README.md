# Ape GFX

Ape GFX is a low-level graphics API for desktop games written in Odin.

The API is Sokol-like where that helps: explicit handles, small descriptors,
immediate-mode draw calls, and user-controlled resource lifetime. It is not
trying to copy Sokol wholesale. Sokol treats web, mobile, and older graphics
APIs as first-class targets; Ape GFX is deliberately narrower. The goal is a
modern desktop-native graphics substrate for engines that want WebGPU-style
resource contracts, Slang reflection, and explicit backend concepts without
browser or mobile constraints.

This repo is the graphics layer only. It is not a renderer, material system,
scene graph, gameplay framework, or asset pipeline.

## Current Status

Ape GFX is D3D12-first on Windows, with the public contract shaped around
Slang reflection and modern explicit graphics APIs:

- `gfx.Backend.D3D12` is the Windows backend target.
- `Backend.Auto` resolves to D3D12 when a native window is supplied.
- Shader packages use `D3D12_DXIL` plus Vulkan SPIR-V metadata.
- Generated shader bindings emit D3D12 native-slot constants.
- Samples are backend-neutral folders under `samples/`.
- The D3D12 runtime backend runs the current sample suite, including render
  targets, depth, MSAA, transient uniforms, compute, and indirect dispatch/draw.

The Vulkan backend remains a design pressure target, not current runtime work.

## Requirements

- Odin on `PATH`
- Slang shared libraries available to `tools/ape_shaderc`
- Windows for the D3D12 backend work
- PowerShell only for repo-level convenience wrappers

## Quick Start

Build the repo task runner:

```powershell
odin build .\tools\ape
```

Compile all sample shaders:

```powershell
odin run .\tools\ape -- shader compile -all
```

Run the core validation gate:

```powershell
odin run .\tools\ape -- validate core
```

Build every sample:

```powershell
odin run .\tools\ape -- sample build all
```

`validate full` compiles shaders, runs public contract/tooling tests, builds
every sample, and runs every sample with the auto-exit guard:

```powershell
odin run .\tools\ape -- validate full
```

## API Shape

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
- `gfx_app`: sample/application helpers for resize, shader setup, textures,
  and hot reload
- `app`: small window/event layer used by samples
- `tools/ape`: Odin task runner for shader compilation, docs, validation, and
  sample builds
- `tools/ape_shaderc`: Slang compiler/package tool
- `samples/ape_math`: sample-only matrix helpers

## Shaders

Shader sources live in `assets/shaders/*.slang`.

Compile one shader package:

```powershell
odin run .\tools\ape -- shader compile -shader-name textured_quad
```

Compile all checked-in sample shaders:

```powershell
odin run .\tools\ape -- shader compile -all
```

Each compile writes:

- D3D12 DXIL bytecode
- Vulkan SPIR-V bytecode for later backend work
- `build/shaders/<name>.ashader`
- generated Odin bindings in `assets/shaders/generated/<name>/bindings.odin`

Generated bindings are the preferred way to use shader slots,
`ParameterBlock<>` resource groups, uniforms, simple vertex layouts, storage
metadata, and compute dispatch helpers. Manual `Pipeline_Desc.layout`
overrides still exist for compact vertex formats, instancing, multiple
streams, and other engine-level layouts.

## Samples

Samples are backend-neutral and build through `tools/ape`:

```powershell
odin run .\tools\ape -- sample build triangle_minimal
odin run .\tools\ape -- sample build all
```

Current samples:

- `clear`
- `triangle_minimal`
- `triangle`
- `cube`
- `textured_quad`
- `textured_cube`
- `dynamic_texture`
- `render_to_texture`
- `depth_render_to_texture`
- `mrt`
- `msaa`
- `gfx_lab`
- `improved_shadows`
- `transient_uniforms`
- `triangle_indirect`
- `dispatch_indirect`
- `gpu_driven_indirect`

`gfx_lab` remains the main API ergonomics sample.

## Docs

Regenerate the checked-in API docs with:

```powershell
odin run .\tools\ape -- docs generate
```

Useful public docs:

- `docs/gfx-descriptor-contracts.md`
- `docs/gfx-error-model.md`
- `docs/gfx-public-api-audit.md`
- `docs/gfx-slang-reflection-contract.md`
- `docs/api/README.md`
