# Ape GFX Samples

These samples are ordered as a learning path, not alphabetically. The folders
are backend-neutral; D3D12 is the Windows backend target for the current
migration.

## Running Samples

Compile all sample shaders first:

```powershell
odin run .\tools\ape -- shader compile -all
```

Build every sample:

```powershell
odin run .\tools\ape -- sample build all
```

Run support is wired through the same task runner:

```powershell
odin run .\tools\ape -- sample run triangle_minimal -auto-exit-frames 5
```

The full validation path builds and runs every sample with a short auto-exit
window:

```powershell
odin run .\tools\ape -- validate full
```

## Learning Order

1. `clear`
   Minimal `gfx_app.run` loop, context creation, swapchain clear, and commit.

2. `triangle_minimal`
   Smallest useful draw path: vertex buffer, generated shader bindings, binding-group layout, pipeline layout, pipeline, draw.

3. `triangle`
   Full triangle sample with the current recommended shader-program helper path.

4. `cube`
   Indexed geometry, depth testing, generated vertex layout, and transient uniform slices.

5. `textured_quad`
   Texture upload, sampled image view, sampler binding, and generated resource setters.

6. `textured_cube`
   Texture sampling on indexed 3D geometry with resize-correct projection.

7. `dynamic_texture`
   CPU-updated texture data and repeated texture uploads.

8. `render_to_texture`
   Offscreen color target, explicit barrier, then sampled resolve pass.

9. `depth_render_to_texture`
   Depth target rendering followed by depth sampling and visualization.

10. `msaa`
    Multisampled color target setup and resolve into a sampled texture.

11. `mrt`
    Multiple render targets, per-target barriers, and display passes.

12. `improved_shadows`
    Shadow-depth rendering plus a lit pass using multiple binding groups.

13. `transient_uniforms`
    Focused transient allocator sample for many per-frame uniform slices.

14. `triangle_indirect`
    Immutable indirect draw argument buffer consumed by `draw_indirect`.

15. `dispatch_indirect`
    Direct dispatch and indirect dispatch producing the same compute output.

16. `gpu_driven_indirect`
    Compute pass writes indirect draw arguments, render pass consumes them.

17. `gfx_lab`
    Integration playground for the current API surface. Use this after the focused samples.

## Support Packages

- `ape_math` is shared sample math code, not a standalone executable sample.
- `smoke` is a validation package used by tooling.
