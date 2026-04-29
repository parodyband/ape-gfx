# Ape GFX Slang Reflection Contract

Date: 2026-04-28

This document defines the current v0.1 reflection contract between Slang source files, `tools/ape_shaderc`, generated Odin binding packages, `.ashader` packages, `shader`, and `gfx`.

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
  -> shader.load
  -> shader.shader_desc
  -> gfx.create_shader
```

Compile one shader with:

```powershell
odin run .\tools\ape -- shader compile -shader-name triangle
```

The Windows convenience wrapper delegates to the same Odin tool:

```powershell
.\tools\compile_shaders.ps1 -ShaderName triangle
```

Compile all checked-in sample shaders:

```powershell
odin run .\tools\ape -- shader compile -all
```

Compile a compute shader with:

```powershell
odin run .\tools\ape -- shader compile -shader-name my_compute_shader -kind compute
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
PACKAGE_VERSION = 9
```

`shader` currently reads package versions `1` through `9` and rejects versions newer than the runtime knows about.

Version policy for v0.1:

- The package format remains provisional until a tagged v0.1 release.
- Increment the package version whenever the binary record layout changes.
- Keep `shader` able to read older package versions when practical.
- Do not expect old runtimes to read newer packages.
- Regenerate shader packages and bindings when `ape_shaderc` or `shader` changes.

## Generated Binding Package

Each shader gets an Odin package:

```text
assets/shaders/generated/<shader>/bindings.odin
```

The package name is:

```odin
<shader>_shader
```

The generated file imports `gfx "ape:gfx"` only when helpers or constants need `gfx` types.

Generated files are build artifacts, but they are checked in because they are part of the sample and validation workflow. Do not edit them by hand.

## Binding Slot Constants

`ape_shaderc` emits two kinds of binding slot constants:

- native target/stage constants
- logical cross-target constants used by `gfx.Bindings`

Native constants include target and stage:

```odin
D3D11_FS_VIEW_ape_texture :: 0
D3D11_FS_VIEW_ape_texture_SPACE :: 0
VK_FS_VIEW_ape_texture :: 0
VK_FS_VIEW_ape_texture_SPACE :: 0
D3D11_FS_SMP_ape_sampler :: 0
D3D11_FS_SMP_ape_sampler_SPACE :: 0
VK_FS_SMP_ape_sampler :: 1
VK_FS_SMP_ape_sampler_SPACE :: 0
```

Logical constants are target-independent:

```odin
GROUP_0 :: 0
VIEW_ape_texture :: 0
SMP_ape_sampler :: 0
UB_FrameUniforms :: 0
```

Use logical constants and generated helper procedures in application code. Native constants exist for diagnostics and backend metadata.

Near-term direction: shader authors should not need routine manual `register(...)` annotations for ordinary samples. `ape_shaderc` reflects Slang-assigned native slots, including Vulkan-style `descriptorTableSlot` bindings, assigns stable GFX logical slots from reflected names, and generates the named Odin helpers used by samples and applications. Manual register annotations are reserved for targeted backend tests and debugging, not as the preferred sample style.

Generated packages also expose a binding contract helper for tools, tests, and future higher-level binding APIs:

```odin
BINDING_RECORD_COUNT :: 6

Binding_Uniform_Block_Desc :: struct {
	size: u32,
}

Binding_Resource_View_Desc :: struct {
	view_kind: gfx.View_Kind,
	access: gfx.Shader_Resource_Access,
	storage_image_format: gfx.Pixel_Format,
	storage_buffer_stride: u32,
}

Binding_Record_Desc :: struct {
	target: gfx.Backend,
	stage: gfx.Shader_Stage,
	kind: gfx.Shader_Binding_Kind,
	name: cstring,
	group: u32,
	logical_slot: u32,
	native_slot: u32,
	native_space: u32,
	uniform_block: Binding_Uniform_Block_Desc,
	resource_view: Binding_Resource_View_Desc,
}

binding_records :: proc() -> [BINDING_RECORD_COUNT]Binding_Record_Desc

binding_group_layout_desc :: proc(group: u32 = 0, label: string = "") -> gfx.Binding_Group_Layout_Desc
pipeline_layout_desc :: proc(
	group_0: gfx.Binding_Group_Layout = gfx.Binding_Group_Layout_Invalid,
	group_1: gfx.Binding_Group_Layout = gfx.Binding_Group_Layout_Invalid,
	group_2: gfx.Binding_Group_Layout = gfx.Binding_Group_Layout_Invalid,
	group_3: gfx.Binding_Group_Layout = gfx.Binding_Group_Layout_Invalid,
	group_4: gfx.Binding_Group_Layout = gfx.Binding_Group_Layout_Invalid,
	group_5: gfx.Binding_Group_Layout = gfx.Binding_Group_Layout_Invalid,
	group_6: gfx.Binding_Group_Layout = gfx.Binding_Group_Layout_Invalid,
	group_7: gfx.Binding_Group_Layout = gfx.Binding_Group_Layout_Invalid,
	label: string = "",
) -> gfx.Pipeline_Layout_Desc
```

This is the explicit Slang-generated binding layout contract. It keeps the simple `gfx.Bindings` call path intact while making reflected names, logical groups, logical slots, native slots, and native spaces available for binding groups and pipeline layouts.

`Binding_Record_Desc` uses explicit payload structs for kind-specific metadata:

- `uniform_block` is valid when `kind == .Uniform_Block`.
- `resource_view` is valid when `kind == .Resource_View`.
- `Sampler` records have no payload today.

The outer record stays common so tools can sort or match by backend, stage, reflected name, logical group, logical slot, native slot, and native space without switching on the payload first.

`binding_group_layout_desc` folds those records into descriptor-only `gfx.Binding_Group_Layout_Desc` data:

- `group` selects which logical group to emit.
- `entries` describe logical binding entries by kind, logical slot, reflected name, stage set, and kind-specific payload.
- `native_bindings` preserve backend/stage native slot and space mappings.
- `gfx.validate_binding_group_layout_desc` can validate the generated descriptor before handle creation.

`pipeline_layout_desc` composes live `gfx.Binding_Group_Layout` handles into a `gfx.Pipeline_Layout_Desc`. Shaders with binding metadata now require a pipeline layout when creating graphics or compute pipelines.

Generated packages also emit `set_group_view_*` and `set_group_sampler_*` helpers for `gfx.Binding_Group_Desc`. The intended path is to create `gfx.Binding_Group_Layout` handles from `binding_group_layout_desc(GROUP_N)`, compose them into a `gfx.Pipeline_Layout`, fill `Binding_Group_Desc` values with generated setters, create `gfx.Binding_Group` handles, and apply one or more groups with optional base geometry bindings. Uniform blocks stay on `apply_uniform_*` until a real buffer-backed uniform binding model exists.

Logical slots are assigned per binding kind:

| Kind | Prefix | Limit |
| --- | --- | --- |
| Uniform block | `UB_` | 16 |
| Resource view | `VIEW_` | 32 |
| Sampler | `SMP_` | 16 |

Bindings with the same kind, reflected group, and reflected name share one logical slot across stages and targets.

## Parameter Blocks And Logical Groups

`ParameterBlock<T>` is the preferred Slang shape for reusable shader resources.

Supported first-pass mapping:

- Global ordinary constant buffers stay in logical group `0`.
- If a shader has only `ParameterBlock<>` resources, the first block maps to group `0`.
- If a shader has global bindings plus `ParameterBlock<>` resources, global bindings stay in group `0` and parameter blocks start at group `1`.
- Each supported resource field inside a parameter block becomes a generated binding name of `<block>.<field>`.
- D3D11 metadata flattens groups to native stage slots. Vulkan metadata preserves the reflected native space for future descriptor-set mapping.

Supported parameter-block fields today:

- `Texture2D<T>` sampled textures
- `SamplerState`
- `RWTexture2D<float>` and `RWTexture2D<float4>`
- raw and structured storage buffers already supported by normal resource reflection

Unsupported parameter-block fields fail during shader generation:

- ordinary data fields
- `ConstantBuffer<T>` fields
- nested parameter blocks
- arrays or bindless-style resource arrays
- unsupported resource shapes such as cube textures

Uniform data inside `ParameterBlock<>` is not part of generated binding groups in the current contract. Keep per-draw data in ordinary constant buffers and use the generated `apply_uniform_*` helpers. `ParameterBlock<>` ordinary data fields and `ConstantBuffer<T>` fields fail shader generation so there is one uniform path.

## Descriptor Arrays And Bindless Direction

Descriptor arrays and bindless-style resource sets are intentionally rejected until the public binding model can represent them without pretending they are single resources.

Rejected shapes include:

- top-level resource arrays such as `Texture2D<float4> textures[2]`
- top-level sampler arrays such as `SamplerState samplers[2]`
- resource or sampler arrays inside `ParameterBlock<>`
- unsized or bindless-style arrays

Expected failure:

```text
ape_shaderc: resource arrays are not supported yet; descriptor arrays and bindless resources need a separate binding contract: <name>
```

The future reflection model should preserve these facts before any generated Odin helper is emitted:

- `count`: finite descriptor count for fixed arrays.
- `unsized`: whether the array is bindless or runtime-sized.
- `element_kind`: sampled view, storage image, storage buffer, or sampler.
- `element_access`: read, write, or read-write for resource views.
- `element_payload`: storage image format or storage buffer stride when relevant.
- `logical_group` and `logical_slot`: the first logical slot for the array binding.
- backend native slot and space for each target.

The likely public API shape is an explicit binding-array descriptor or object, not `N` generated single-resource setters. Fixed arrays and bindless sets should therefore wait until there is a sample that needs them and a deliberate `gfx` contract for limits, partial updates, validation, and D3D11 fallback behavior.

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
	return gfx.apply_uniform(ctx, GROUP_0, UB_FrameUniforms, value)
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

Generated structs do not synthesize hidden padding fields yet. Shader generation fails when reflected offsets or trailing block size require padding the generated Odin struct cannot represent. `#assert` checks remain in generated bindings as a final guard.

Unsupported uniform field shapes:

- arrays
- nested structs as uniform fields
- booleans
- 8-bit, 16-bit, 64-bit, and half-precision fields
- implicit padding before a field or at the end of a block
- overlapping reflected fields
- uniform blocks whose layout differs across stages or targets

Expected failure messages include:

```text
ape_shaderc: unsupported uniform field <block>.<field>: <reason>
ape_shaderc: uniform block layout has unsupported host padding before <block>.<field>
ape_shaderc: uniform block has unsupported trailing host padding: <block>
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
GROUP_0 :: 0
VIEW_ape_texture :: 0
VIEW_KIND_ape_texture :: gfx.View_Kind.Sampled
VIEW_ACCESS_ape_texture :: gfx.Shader_Resource_Access.Read

set_view_ape_texture :: proc(bindings: ^gfx.Bindings, view: gfx.View) {
	if bindings == nil {
		return
	}
	bindings.views[GROUP_0][VIEW_ape_texture] = view
}
```

Sampler example:

```odin
GROUP_0 :: 0
SMP_ape_sampler :: 0

set_sampler_ape_sampler :: proc(bindings: ^gfx.Bindings, sampler: gfx.Sampler) {
	if bindings == nil {
		return
	}
	bindings.samplers[GROUP_0][SMP_ape_sampler] = sampler
}
```

Supported resource view shapes:

| Slang shape | Generated view kind |
| --- | --- |
| `Texture2D<T>` sampled texture resource | `gfx.View_Kind.Sampled` |
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

`shader.shader_desc(pkg, target, label)` converts a package into `gfx.Shader_Desc`.

It fills:

- stage bytecode and entry names
- binding metadata when package version is at least `2`
- vertex input metadata when package version is at least `3`
- storage view metadata when package version is at least `5`
- storage image format metadata when package version is at least `6`
- storage buffer stride metadata when package version is at least `7`
- native binding space metadata when package version is at least `8`
- logical binding group metadata when package version is at least `9`

`gfx.create_shader` and `gfx.create_pipeline` validate that reflected metadata matches runtime descriptors and bindings.

## Binding Group Direction

The current contract uses generated reflection data to create object-backed binding group layouts and binding groups. `gfx.Bindings` remains the low-level immediate binding path for geometry buffers and explicit escape hatches, while generated binding groups are the preferred path for reusable shader resources.

`ape_shaderc` now uses Slang's modern session/module/component API as its only shader compile path. Reflection is read from the linked `ProgramLayout` plus entry-point metadata produced by that path.

Planned order:

- [x] Add an `ape_shaderc` batch mode so one tool invocation can compile all sample shaders.
- [x] Keep PowerShell scripts as thin wrappers around the Odin tool for normal sample shader compilation.
- [x] Bind and validate the minimum modern Slang API surface for `IGlobalSession`, `ISession`, target/profile setup, and session creation.
- [x] Use the modern module/component path for normal `.ashader` package generation.
- [x] Read reflection JSON from modern `ProgramLayout` and used-binding data from entry-point metadata.
- [x] Add focused descriptor-table validation for register-free constant buffers, sampled textures, samplers, storage images, and storage buffers across D3D11 and Vulkan records.
- [x] Parse Slang reflection JSON once per stage into a small binding model before generating binding records.
- [x] Settle generated binding record payload semantics before the generated binding-group contract.
- [x] Generate the first descriptor-only single-group layout helper on top of reflected names, logical slots, native slots, and native spaces.
- [x] Add a `Binding_Group_Desc` / `apply_binding_group` path for generated resource views and samplers.
- [x] Exercise binding groups in `d3d11_gfx_lab` and `d3d11_improved_shadows` so the API is tested by a simple display pass and shared material/pass resource groups.
- [x] Tighten `apply_binding_group` validation so generated layouts must match the currently applied pipeline's reflected logical slots, stages, names, payload metadata, and backend native slots.
- [x] Replace the transient public apply path with `Binding_Group_Layout` and `Binding_Group` handles.
- [x] Traverse Slang reflection JSON deeply enough to represent `ParameterBlock<>` resources, multiple logical groups, native slots, and native spaces without hand-authored binding registers.
- [x] Generate group-aware Odin helpers and package binding records.
- [x] Validate and apply multiple object-backed binding groups through `gfx.apply_binding_groups`.
- [x] Add negative shaderc coverage for unsupported `ParameterBlock<>` shapes: ordinary data, `ConstantBuffer<T>`, nested parameter blocks, resource arrays, and unsupported texture shapes.
- [x] Add public `Pipeline_Layout` handles and require them for shaders with reflected binding metadata.
- [x] Generate `pipeline_layout_desc` helpers and migrate samples to compose generated binding group layouts into pipeline layouts.
- [x] Harden transient `gfx.Bindings` against active `Pipeline_Layout` metadata for supplied views and samplers.
- [x] Sketch descriptor-array and bindless reflection requirements, and reject top-level binding arrays with a clear shaderc error.
- [x] Extend the modern Slang API surface for deeper program layout traversal and entry-point metadata where JSON is too weak.
- [x] Decide whether uniform data inside `ParameterBlock<>` belongs in generated binding groups or stays on `apply_uniform_*`.
- [x] Harden uniform host-layout reflection for unsupported arrays, nested structs, scalar widths, and implicit padding.

Open questions:

- How to expose resource arrays or bindless-style layouts without weakening the simple generated helper path.

The rule stays the same for samples: use register-free Slang source, let `ape_shaderc` publish the reflected contract, and keep manual binding layouts as explicit escape hatches.

Roadmap note: `gfx_app` owns the reusable shader-program and resize helpers. The transient `gfx.Bindings` path now validates supplied views and samplers against active `Pipeline_Layout` metadata before backend binding. The next shader-contract-specific task is the descriptor-array and bindless public API design.

## Validation

Current shader reflection validation is covered by:

```powershell
odin run .\tools\ape -- shader compile -all
odin run .\tools\ape -- shader test -all
.\tools\test_d3d11_invalid_pipeline_layout.ps1
.\tools\test_d3d11_invalid_uniform_size.ps1
.\tools\test_d3d11_invalid_view_kind.ps1
.\tools\test_d3d11_resource_hazards.ps1
.\tools\test_d3d11_storage_views.ps1
.\tools\test_d3d11_compute_pass.ps1
```

The full gate is:

```powershell
odin run .\tools\ape -- validate full
```

The Windows wrapper delegates to the same Odin validation path:

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
| `GROUP_<n>` | Logical binding group index. |
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
| `Binding_Uniform_Block_Desc` | Generated uniform-block record payload. |
| `Binding_Resource_View_Desc` | Generated resource-view record payload. |
| `Binding_Record_Desc` | Generated binding contract record type. |
| `binding_records` | Helper returning the generated binding contract records. |
| `binding_group_layout_desc` | Helper returning descriptor-only generated binding group layout data. |
| `pipeline_layout_desc` | Helper returning descriptor-only generated pipeline layout data from live group-layout handles. |
| `set_group_view_<name>` | Helper for `gfx.Binding_Group_Desc.views`. |
| `set_group_sampler_<name>` | Helper for `gfx.Binding_Group_Desc.samplers`. |
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
