# Ape GFX Slang Reflection Contract

Date: 2026-04-28

This document defines the current v0.1 reflection contract between Slang source files, `tools/ape_shaderc`, generated Odin binding packages, `.ashader` packages, `engine/shader`, and `engine/gfx`.

The goal is narrow and practical: simple desktop-game shaders should generate safe Odin helpers, while unsupported shader shapes should fail during shader compilation with useful messages.

## Scope

This contract covers:

- `.ashader` package versioning.
- Fixed entry point names.
- Supported targets and stages.
- Generated binding helper names.
- Vertex input layout generation.
- Uniform block struct generation.
- Resource binding metadata.
- Compute dispatch helpers.
- Known unsupported shapes.

This contract does not promise:

- Runtime Slang compilation.
- Web, mobile, OpenGL, Metal, or D3D12 shader outputs.
- A stable Vulkan runtime path.
- Bindless/resource arrays.
- Auto-generated multi-buffer vertex layouts.
- Full HLSL/Slang type coverage.

## Pipeline

The intended flow is:

```text
assets/shaders/*.slang
  -> tools/ape_shaderc
  -> build/shaders/*.ashader
  -> assets/shaders/generated/<shader>/bindings.odin
  -> engine/shader.load
  -> engine/shader.shader_desc
  -> gfx.create_shader
```

Compile one shader with:

```powershell
.\tools\compile_shaders.ps1 -ShaderName triangle
```

Compile all checked-in sample shaders with one `ape_shaderc` invocation:

```powershell
.\tools\compile_shaders.ps1 -All
```

Compile a compute shader with:

```powershell
.\tools\compile_shaders.ps1 -ShaderName my_compute_shader -Kind compute
```

## Entry Points And Targets

Graphics shaders use fixed entry point names:

| Stage | Slang entry point |
| --- | --- |
| Vertex | `vs_main` |
| Fragment | `fs_main` |

Compute shaders use:

| Stage | Slang entry point |
| --- | --- |
| Compute | `cs_main` |

`ape_shaderc` currently emits:

| Target | Status |
| --- | --- |
| `D3D11_DXBC` | v0.1 runtime target. |
| `Vulkan_SPIRV` | Build artifact for future backend work. No v0.1 runtime contract. |

Graphics compilation emits vertex and fragment payloads for both targets. Compute compilation emits compute payloads for both targets.

## `.ashader` Package Versioning

The `.ashader` binary package starts with:

- magic: `APSH`
- package version
- stage record count
- binding record count
- vertex input record count

Current writer version:

```text
PACKAGE_VERSION = 8
```

`engine/shader` currently reads package versions `1` through `8` and rejects versions newer than the runtime knows about.

Version policy for v0.1:

- The package format remains provisional until a tagged v0.1 release.
- Increment the package version whenever the binary record layout changes.
- Keep `engine/shader` able to read older package versions when practical.
- Do not expect old runtimes to read newer packages.
- Regenerate shader packages and bindings when `ape_shaderc` or `engine/shader` changes.

## Generated Binding Package

Each shader gets an Odin package:

```text
assets/shaders/generated/<shader>/bindings.odin
```

The package name is:

```odin
<shader>_shader
```

The generated file imports `gfx "ape:engine/gfx"` only when helpers or constants need `gfx` types.

Generated files are build artifacts, but they are checked in because they are part of the sample and validation workflow. Do not edit them by hand.

## Binding Slot Constants

`ape_shaderc` emits two kinds of binding slot constants:

- native target/stage constants
- logical cross-target constants used by `gfx.Bindings`

Native constants include target and stage:

```odin
D3D11_FS_VIEW_ape_texture :: 0
D3D11_FS_VIEW_ape_texture_SPACE :: 0
VK_FS_VIEW_ape_texture :: 32
VK_FS_VIEW_ape_texture_SPACE :: 0
D3D11_FS_SMP_ape_sampler :: 0
D3D11_FS_SMP_ape_sampler_SPACE :: 0
VK_FS_SMP_ape_sampler :: 64
VK_FS_SMP_ape_sampler_SPACE :: 0
```

Logical constants are target-independent:

```odin
VIEW_ape_texture :: 0
SMP_ape_sampler :: 0
UB_FrameUniforms :: 0
```

Use logical constants and generated helper procedures in application code. Native constants exist for diagnostics and backend metadata.

Near-term direction: shader authors should not need routine manual `register(...)` annotations for ordinary samples. `ape_shaderc` should reflect Slang-assigned native slots, assign stable GFX logical slots from reflected names, and generate the named Odin helpers used by samples and applications. Manual register annotations remain available for compatibility and targeted backend experiments, not as the preferred sample style.

Generated packages also expose a binding contract helper for tools, tests, and future higher-level binding APIs:

```odin
BINDING_RECORD_COUNT :: 6

Binding_Record_Desc :: struct {
	target: gfx.Backend,
	stage: gfx.Shader_Stage,
	kind: gfx.Shader_Binding_Kind,
	name: cstring,
	logical_slot: u32,
	native_slot: u32,
	native_space: u32,
	size: u32,
	view_kind: gfx.View_Kind,
	access: gfx.Shader_Resource_Access,
	storage_image_format: gfx.Pixel_Format,
	storage_buffer_stride: u32,
}

binding_records :: proc() -> [BINDING_RECORD_COUNT]Binding_Record_Desc
```

This is the first explicit Slang-generated binding layout contract. It keeps the simple `gfx.Bindings` call path intact while making reflected names, logical slots, native slots, and native spaces available for later binding group and pipeline layout design.

Logical slots are assigned per binding kind:

| Kind | Prefix | Limit |
| --- | --- | --- |
| Uniform block | `UB_` | 16 |
| Resource view | `VIEW_` | 32 |
| Sampler | `SMP_` | 16 |

Bindings with the same kind and reflected name share one logical slot across stages and targets.

## Uniform Blocks

Uniform block reflection emits an Odin struct, size/alignment constants, field offsets, field sizes, and an `apply_uniform_*` helper.

Example:

```odin
FrameUniforms :: struct {
	ape_frame: [4]f32,
}

SIZE_FrameUniforms :: 16
ALIGN_FrameUniforms :: 16
OFFSET_FrameUniforms_ape_frame :: 0
SIZE_FrameUniforms_ape_frame :: 16

apply_uniform_FrameUniforms :: proc(ctx: ^gfx.Context, value: ^$T) -> bool {
	#assert(size_of(T) == SIZE_FrameUniforms)
	return gfx.apply_uniform(ctx, UB_FrameUniforms, value)
}
```

Supported uniform field shapes:

| Slang field type | Generated Odin type |
| --- | --- |
| `float` | `f32` |
| `int` / `int32_t` | `i32` |
| `uint` / `uint32_t` | `u32` |
| `floatN` | `[N]f32` |
| `intN` | `[N]i32` |
| `uintN` | `[N]u32` |
| `floatRxC` | `[R][C]f32` |
| `intRxC` | `[R][C]i32` |
| `uintRxC` | `[R][C]u32` |

Generated structs include explicit padding fields when reflected offsets require gaps. `#assert` checks keep generated Odin layout aligned with Slang reflection.

Unsupported uniform field shapes:

- arrays
- nested structs as uniform fields
- booleans
- 8-bit, 16-bit, 64-bit, and half-precision fields
- overlapping reflected fields
- uniform blocks whose layout differs across stages or targets

Expected failure message for unsupported fields:

```text
ape_shaderc: uniform field has unsupported host layout: <block>.<field>
```

## Vertex Layouts

Generated vertex layouts are intentionally simple:

- one vertex input struct
- tightly packed attributes
- one vertex buffer by default
- per-vertex stepping by default
- semantic index `0` only

Supported vertex field types:

| Slang field type | Generated `gfx.Vertex_Format` |
| --- | --- |
| `float` | `.Float32` |
| `float2` | `.Float32x2` |
| `float3` | `.Float32x3` |
| `float4` | `.Float32x4` |

Generated helpers:

```odin
VERTEX_STRIDE :: 24
ATTR_POSITION_OFFSET :: 0
ATTR_POSITION_SIZE :: 12
ATTR_POSITION_FORMAT :: gfx.Vertex_Format.Float32x3

layout_desc :: proc(
	buffer_slot: u32 = 0,
	stride: u32 = VERTEX_STRIDE,
	step_func: gfx.Vertex_Step_Function = .Per_Vertex,
	step_rate: u32 = 0,
) -> gfx.Layout_Desc
```

`layout_desc()` accepts override parameters so a caller can choose a different buffer slot, stride, step function, or step rate while keeping the reflected attribute offsets.

Unsupported generated vertex layout shapes:

| Unsupported shape | Failure message |
| --- | --- |
| Vertex input parameter is not a struct | `generated vertex layouts only support struct vertex inputs` |
| Field has no semantic | `vertex input field is missing a semanticName` |
| Semantic index is nonzero, such as `TEXCOORD1` | `generated vertex layouts do not support nonzero semantic indices yet` |
| Duplicate semantic/index pair | `generated vertex layouts do not support duplicate vertex semantics` |
| Integer attributes | `unsupported vertex input type for generated layout` |
| Matrix attributes | `unsupported vertex input type for generated layout` |
| Array attributes | `unsupported vertex input type for generated layout` |
| Layout differs between D3D11 and SPIR-V reflection | `reflected vertex input layout differs across targets` |

Manual `Pipeline_Desc.layout` overrides remain supported. Use a manual layout for:

- compact packed formats such as `.Uint8x4_Norm`
- multiple vertex buffers
- custom semantic indices
- custom instancing layouts
- any vertex shape outside the generated packed path

Manual layouts still must match reflected shader inputs when vertex input metadata exists.

## Resource Views

Slang-reflected resource bindings become `gfx.Shader_Binding_Desc` entries and generated metadata constants.

Sampled texture example:

```odin
VIEW_ape_texture :: 0
VIEW_KIND_ape_texture :: gfx.View_Kind.Sampled
VIEW_ACCESS_ape_texture :: gfx.Shader_Resource_Access.Read

set_view_ape_texture :: proc(bindings: ^gfx.Bindings, view: gfx.View) {
	if bindings == nil {
		return
	}
	bindings.views[VIEW_ape_texture] = view
}
```

Sampler example:

```odin
SMP_ape_sampler :: 0

set_sampler_ape_sampler :: proc(bindings: ^gfx.Bindings, sampler: gfx.Sampler) {
	if bindings == nil {
		return
	}
	bindings.samplers[SMP_ape_sampler] = sampler
}
```

Supported resource view shapes:

| Slang shape | Generated view kind |
| --- | --- |
| sampled texture resource | `gfx.View_Kind.Sampled` |
| read-only buffer resource | `gfx.View_Kind.Storage_Buffer` or sampled fallback depending reflection shape |
| `RWTexture2D<float>` | `gfx.View_Kind.Storage_Image`, format `.R32F` |
| `RWTexture2D<float4>` | `gfx.View_Kind.Storage_Image`, format `.RGBA32F` |
| `RWByteAddressBuffer` / raw buffer | `gfx.View_Kind.Storage_Buffer`, stride `0` |
| `RWStructuredBuffer<T>` / structured buffer | `gfx.View_Kind.Storage_Buffer`, reflected stride |

Access metadata:

| Reflected access | Generated access |
| --- | --- |
| shader resource | `.Read` |
| unordered access with no explicit access | `.Read_Write` |
| `read` | `.Read` |
| `write` | `.Write` |
| `readWrite` | `.Read_Write` |

Storage image format support is intentionally narrow:

| Slang result type | Generated format |
| --- | --- |
| `float` | `.R32F` |
| `float4` | `.RGBA32F` |

Unsupported storage image result types fail with:

```text
ape_shaderc: unsupported storage image result type; supported generated formats are float and float4
```

Structured storage buffer rules:

- Reflected element stride must be nonzero.
- Stride must be 4-byte aligned.
- Scalar, vector, and struct element shapes are supported when their reflected sizes are representable.
- Raw storage buffers use stride `0`.

Unsupported structured storage buffers fail with one of:

```text
ape_shaderc: unsupported structured storage buffer element type
ape_shaderc: structured storage buffer element stride must be 4-byte aligned
```

## Compute Reflection

Compute shaders must provide a reflected `threadGroupSize` for `cs_main`.

Generated constants:

```odin
COMPUTE_THREAD_GROUP_SIZE_X :: 8
COMPUTE_THREAD_GROUP_SIZE_Y :: 8
COMPUTE_THREAD_GROUP_SIZE_Z :: 1
COMPUTE_THREAD_GROUP_INVOCATIONS :: 64
```

Generated helpers:

```odin
dispatch_group_count :: proc(thread_count: u32, group_size: u32) -> u32

dispatch_groups_for_threads :: proc(
	thread_count_x: u32,
	thread_count_y: u32 = 1,
	thread_count_z: u32 = 1,
) -> (u32, u32, u32)

dispatch_threads :: proc(
	ctx: ^gfx.Context,
	thread_count_x: u32,
	thread_count_y: u32 = 1,
	thread_count_z: u32 = 1,
) -> bool
```

Rules:

- Thread group size must be a 3-element array.
- All values must be positive.
- Reflected thread group size must match across targets.

Expected failures:

```text
ape_shaderc: compute entry point has no threadGroupSize
ape_shaderc: compute entry point threadGroupSize must be a 3-element array
ape_shaderc: compute threadGroupSize values must be positive integers
ape_shaderc: reflected compute thread group size differs across targets
```

## Runtime Shader Descriptor

`engine/shader.shader_desc(pkg, target, label)` converts a package into `gfx.Shader_Desc`.

It fills:

- stage bytecode and entry names
- binding metadata when package version is at least `2`
- vertex input metadata when package version is at least `3`
- storage view metadata when package version is at least `5`
- storage image format metadata when package version is at least `6`
- storage buffer stride metadata when package version is at least `7`
- native binding space metadata when package version is at least `8`

`gfx.create_shader` and `gfx.create_pipeline` validate that reflected metadata matches runtime descriptors and bindings.

## Post-v0.1 Binding Group Direction

The current contract deliberately stops at reflected binding metadata and named helper procedures. The next design pass should build optional binding groups on top of this data instead of replacing `gfx.Bindings`.

Near-term compiler work comes first. `ape_shaderc` should move from the older compile-request API and command-line-style arguments to Slang's modern session/component API before binding groups become a public `gfx` contract.

Planned order:

- [x] Add an `ape_shaderc` batch mode so one tool invocation can compile all sample shaders.
- [x] Keep PowerShell scripts as thin wrappers around the Odin tool for normal sample shader compilation.
- [ ] Next: bind the modern Slang API surface needed for `IGlobalSession`, `ISession`, modules, entry points, component composition, linked programs, generated code blobs, and entry-point metadata.
- Preserve the current `.ashader` and generated Odin output while the new compiler path reaches parity.
- Traverse Slang program layout data deeply enough to represent `ParameterBlock<>`, implicit constant buffers, native slots, and native spaces without hand-authored binding registers.

Open questions:

- Whether generated `Binding_Record_Desc` arrays are enough to derive a `Binding_Group_Layout`.
- How `ParameterBlock<>` should map to logical binding groups when Slang assigns target-specific native groups or spaces.
- Whether a `Pipeline_Layout` object should exist only when it enables reuse across multiple generated shader packages.
- How D3D11 should emulate groups by flattening reflected group entries into stage slots while Vulkan later maps them to descriptor sets.

The rule stays the same for samples: use register-free Slang source, let `ape_shaderc` publish the reflected contract, and keep manual binding layouts as explicit escape hatches.

## Validation

Current shader reflection validation is covered by:

```powershell
.\tools\compile_shaders.ps1 -All
.\tools\test_shaderc_register_free_samples.ps1
.\tools\test_shaderc_invalid_vertex_layout.ps1
.\tools\test_shaderc_storage_resource_metadata.ps1
.\tools\test_d3d11_invalid_pipeline_layout.ps1
.\tools\test_d3d11_invalid_uniform_size.ps1
.\tools\test_d3d11_invalid_view_kind.ps1
.\tools\test_d3d11_resource_hazards.ps1
.\tools\test_d3d11_storage_views.ps1
.\tools\test_d3d11_compute_pass.ps1
```

The full gate is:

```powershell
.\tools\validate_all.ps1
```

## Stable Helper Names

These generated names are intended to stay stable through v0.1:

| Helper or constant | Meaning |
| --- | --- |
| `VERTEX_STRIDE` | Packed generated vertex stride. |
| `ATTR_<SEMANTIC>_OFFSET` | Attribute byte offset in the packed generated layout. |
| `ATTR_<SEMANTIC>_SIZE` | Attribute byte size. |
| `ATTR_<SEMANTIC>_FORMAT` | Generated `gfx.Vertex_Format`. |
| `layout_desc` | Generated `gfx.Layout_Desc` helper. |
| `<UniformBlock>` | Generated uniform block struct. |
| `SIZE_<UniformBlock>` | Reflected uniform block byte size. |
| `ALIGN_<UniformBlock>` | Reflected uniform block alignment. |
| `OFFSET_<UniformBlock>_<field>` | Reflected uniform field offset. |
| `SIZE_<UniformBlock>_<field>` | Reflected uniform field size. |
| `apply_uniform_<UniformBlock>` | Typed uniform upload helper. |
| `UB_<name>` | Logical uniform block slot. |
| `VIEW_<name>` | Logical resource view slot. |
| `SMP_<name>` | Logical sampler slot. |
| `<TARGET>_<STAGE>_UB_<name>` | Native uniform slot. |
| `<TARGET>_<STAGE>_UB_<name>_SPACE` | Native uniform binding space. |
| `<TARGET>_<STAGE>_VIEW_<name>` | Native resource view slot. |
| `<TARGET>_<STAGE>_VIEW_<name>_SPACE` | Native resource view binding space. |
| `<TARGET>_<STAGE>_SMP_<name>` | Native sampler slot. |
| `<TARGET>_<STAGE>_SMP_<name>_SPACE` | Native sampler binding space. |
| `BINDING_RECORD_COUNT` | Number of generated target/stage binding records. |
| `Binding_Record_Desc` | Generated binding contract record type. |
| `binding_records` | Helper returning the generated binding contract records. |
| `VIEW_KIND_<name>` | Reflected `gfx.View_Kind`. |
| `VIEW_ACCESS_<name>` | Reflected `gfx.Shader_Resource_Access`. |
| `VIEW_FORMAT_<name>` | Reflected storage image format when relevant. |
| `VIEW_STRIDE_<name>` | Reflected storage buffer stride when relevant. |
| `set_view_<name>` | Helper for `gfx.Bindings.views`. |
| `set_sampler_<name>` | Helper for `gfx.Bindings.samplers`. |
| `COMPUTE_THREAD_GROUP_SIZE_X/Y/Z` | Reflected compute group size. |
| `COMPUTE_THREAD_GROUP_INVOCATIONS` | Product of reflected group size values. |
| `dispatch_group_count` | Helper for ceil-dividing thread counts. |
| `dispatch_groups_for_threads` | Helper returning dispatch group counts. |
| `dispatch_threads` | Helper that calls `gfx.dispatch`. |
