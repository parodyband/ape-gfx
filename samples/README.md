# Ape GFX Samples

These samples are ordered as a learning path, not alphabetically. Start at the top if you are new to the API.

## Running Samples

Compile all sample shaders first:

```powershell
odin run .\tools\ape -- compile-shaders -all
```

Run the full Windows/D3D11 validation pass:

```powershell
odin run .\tools\ape -- validate full
```

Individual D3D11 samples currently use Windows wrapper scripts:

```powershell
.\tools\run_d3d11_triangle_minimal.ps1 -AutoExitFrames 5
```

The wrappers compile the shader package each sample needs, then run the Odin sample with the correct `-collection:ape=...` path. The Odin tool is the source of truth for shader compilation and validation; the PowerShell sample scripts are convenience wrappers for Windows.

## Learning Order

1. `d3d11_clear`
   Minimal `gfx_app.run` loop, context creation, swapchain clear, and commit.

2. `d3d11_triangle_minimal`
   Smallest useful draw path: vertex buffer, generated shader bindings, binding-group layout, pipeline layout, pipeline, draw.

3. `d3d11_triangle`
   Full triangle sample with the current recommended shader-program helper path.

4. `d3d11_cube`
   Indexed geometry, depth testing, generated vertex layout, and transient uniform slices.

5. `d3d11_textured_quad`
   Texture upload, sampled image view, sampler binding, and generated resource setters.

6. `d3d11_textured_cube`
   Texture sampling on indexed 3D geometry with resize-correct projection.

7. `d3d11_dynamic_texture`
   CPU-updated texture data and repeated texture uploads.

8. `d3d11_render_to_texture`
   Offscreen color target, explicit barrier, then sampled resolve pass.

9. `d3d11_depth_render_to_texture`
   Depth target rendering followed by depth sampling and visualization.

10. `d3d11_msaa`
    Multisampled color target setup and resolve into a sampled texture.

11. `d3d11_mrt`
    Multiple render targets, per-target barriers, and display passes.

12. `d3d11_improved_shadows`
    Shadow-depth rendering plus a lit pass using multiple binding groups.

13. `d3d11_transient_uniforms`
    Focused transient allocator sample for many per-frame uniform slices.

14. `d3d11_triangle_indirect`
    Immutable indirect draw argument buffer consumed by `draw_indirect`.

15. `d3d11_dispatch_indirect`
    Direct dispatch and indirect dispatch producing the same compute output.

16. `d3d11_gpu_driven_indirect`
    Compute pass writes indirect draw arguments, render pass consumes them.

17. `d3d11_gfx_lab`
    Integration playground for the current D3D11-backed API surface. Use this after the focused samples.

## Support Packages

- `ape_math` is shared sample math code, not a standalone executable sample.
- `smoke` is a validation package used by tooling.
