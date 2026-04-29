package gfx

MAX_VERTEX_BUFFERS :: 8
MAX_VERTEX_ATTRIBUTES :: 16
MAX_COLOR_ATTACHMENTS :: 8
MAX_RESOURCE_VIEWS :: 32
MAX_SAMPLERS :: 16
MAX_UNIFORM_BLOCKS :: 16
MAX_BINDING_GROUPS :: 8
MAX_SHADER_BINDINGS :: 64
MAX_BINDING_GROUP_ENTRIES :: MAX_SHADER_BINDINGS
MAX_IMAGE_MIPS :: 16

COLOR_MASK_R :: u8(1 << 0)
COLOR_MASK_G :: u8(1 << 1)
COLOR_MASK_B :: u8(1 << 2)
COLOR_MASK_A :: u8(1 << 3)
COLOR_MASK_RGB :: COLOR_MASK_R | COLOR_MASK_G | COLOR_MASK_B
COLOR_MASK_RGBA :: COLOR_MASK_RGB | COLOR_MASK_A

// Backend selects the native graphics implementation used by a Context.
Backend :: enum {
	Auto,
	Null,
	D3D11,
	Vulkan,
}

// GPU resource handles are opaque generational IDs. Zero is always invalid.
Buffer :: distinct u64
Image :: distinct u64
View :: distinct u64
Sampler :: distinct u64
Shader :: distinct u64
Pipeline :: distinct u64
Compute_Pipeline :: distinct u64
Binding_Group_Layout :: distinct u64
Pipeline_Layout :: distinct u64
Binding_Group :: distinct u64

// Invalid handle sentinels returned when resource creation fails.
Buffer_Invalid :: Buffer(0)
Image_Invalid :: Image(0)
View_Invalid :: View(0)
Sampler_Invalid :: Sampler(0)
Shader_Invalid :: Shader(0)
Pipeline_Invalid :: Pipeline(0)
Compute_Pipeline_Invalid :: Compute_Pipeline(0)
Binding_Group_Layout_Invalid :: Binding_Group_Layout(0)
Pipeline_Layout_Invalid :: Pipeline_Layout(0)
Binding_Group_Invalid :: Binding_Group(0)

// Buffer_Usage_Flag describes the intended roles and CPU update path for a buffer.
Buffer_Usage_Flag :: enum {
	Vertex,
	Index,
	Uniform,
	Storage,
	Immutable,
	Dynamic_Update,
	Stream_Update,
}

Buffer_Usage :: bit_set[Buffer_Usage_Flag; u32]

// Index_Type selects the element format for the bound index buffer.
Index_Type :: enum {
	None,
	Uint16,
	Uint32,
}

// Image_Usage_Flag describes sampled, storage, attachment, and CPU update roles for an image.
Image_Usage_Flag :: enum {
	Texture,
	Storage_Image,
	Color_Attachment,
	Depth_Stencil_Attachment,
	Immutable,
	Dynamic_Update,
	Stream_Update,
}

Image_Usage :: bit_set[Image_Usage_Flag; u32]

// Image_Kind describes the dimensional shape of an image resource.
Image_Kind :: enum {
	Image_2D,
	Image_3D,
	Cube,
}

// View_Kind describes how a View interprets its parent image or buffer.
View_Kind :: enum {
	Sampled,
	Storage_Image,
	Storage_Buffer,
	Color_Attachment,
	Depth_Stencil_Attachment,
}

// Resource_Usage names the GPU role a Buffer or Image subresource is in at a
// point in the command stream. It is the public vocabulary for the barrier
// API (AAA roadmap item 18 / APE-14): pass attachment `initial_usage` /
// `final_usage`, binding-group entry usage, and the `from` / `to` fields of
// future explicit barrier verbs all use this enum. See
// docs/private/gfx-barriers-note.md §2 and §9 for the model.
//
// One usage per subresource at a time. The hybrid barrier model picked in
// APE-13 (auto inside a pass, explicit between passes/queues) keeps the user
// writing usages while the runtime translates to backend states.
//
// Backend mapping per value:
//
//   None
//     D3D11   no-op (D3D11 has no public state).
//     D3D12   D3D12_RESOURCE_STATE_COMMON.
//     Vulkan  VK_IMAGE_LAYOUT_UNDEFINED, no access mask.
//     Meaning: pre-first-use. The first transition out of None is auto-emitted
//     by §9.1 attachments or by the first barrier that names the resource.
//
//   Sampled
//     D3D11   SRV bind (informational).
//     D3D12   D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE |
//             D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE.
//     Vulkan  VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
//             VK_ACCESS_2_SHADER_SAMPLED_READ_BIT.
//
//   Storage_Read
//     D3D11   SRV bind on a structured/byteaddress buffer or storage image
//             (informational; D3D11 does not split UAV read from write).
//     D3D12   D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE |
//             D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE on UAV-capable
//             resources used read-only this pass.
//     Vulkan  VK_IMAGE_LAYOUT_GENERAL (images),
//             VK_ACCESS_2_SHADER_STORAGE_READ_BIT.
//
//   Storage_Write
//     D3D11   UAV bind (informational).
//     D3D12   D3D12_RESOURCE_STATE_UNORDERED_ACCESS.
//     Vulkan  VK_IMAGE_LAYOUT_GENERAL (images),
//             VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT. Repeating Storage_Write on
//             the same view across two dispatches in one compute pass triggers
//             an in-pass UAV barrier (gfx-barriers-note.md §9.1, case 4.5).
//
//   Color_Target
//     D3D11   OMSetRenderTargets (informational).
//     D3D12   D3D12_RESOURCE_STATE_RENDER_TARGET.
//     Vulkan  VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
//             VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT.
//
//   Depth_Target_Read
//     D3D11   OMSetRenderTargets with read-only DSV (informational).
//     D3D12   D3D12_RESOURCE_STATE_DEPTH_READ.
//     Vulkan  VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
//             VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT. Used for early-Z
//             passes that bind the depth image as both attachment and sampled
//             texture (gfx-barriers-note.md case 4.6).
//
//   Depth_Target_Write
//     D3D11   OMSetRenderTargets with read/write DSV (informational).
//     D3D12   D3D12_RESOURCE_STATE_DEPTH_WRITE.
//     Vulkan  VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
//             VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT.
//
//   Copy_Source
//     D3D11   CopyResource / CopySubresourceRegion source (informational).
//     D3D12   D3D12_RESOURCE_STATE_COPY_SOURCE.
//     Vulkan  VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
//             VK_ACCESS_2_TRANSFER_READ_BIT.
//
//   Copy_Dest
//     D3D11   CopyResource / CopySubresourceRegion destination, UpdateSubresource
//             target (informational).
//     D3D12   D3D12_RESOURCE_STATE_COPY_DEST.
//     Vulkan  VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
//             VK_ACCESS_2_TRANSFER_WRITE_BIT.
//
//   Indirect_Argument
//     D3D11   ExecuteIndirect-style argument buffer bind (informational).
//     D3D12   D3D12_RESOURCE_STATE_INDIRECT_ARGUMENT.
//     Vulkan  VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT (buffers only — there is
//             no image layout for this state). Read by draw_indirect /
//             dispatch_indirect (AAA roadmap items 11-15).
//
//   Present
//     D3D11   IDXGISwapChain::Present source (informational).
//     D3D12   D3D12_RESOURCE_STATE_PRESENT (alias of COMMON).
//     Vulkan  VK_IMAGE_LAYOUT_PRESENT_SRC_KHR. Only valid on swapchain images;
//             pass attachments use it as `initial_usage` / `final_usage` to
//             ride the §9.4 auto-transition path.
Resource_Usage :: enum {
	None,
	Sampled,
	Storage_Read,
	Storage_Write,
	Color_Target,
	Depth_Target_Read,
	Depth_Target_Write,
	Copy_Source,
	Copy_Dest,
	Indirect_Argument,
	Present,
}

// Error_Code classifies the most recent context error for programmatic handling.
Error_Code :: enum {
	None,
	Validation,
	Unsupported,
	Invalid_Handle,
	Wrong_Context,
	Stale_Handle,
	Backend,
	Device_Lost,
	Resource_Leak,
}

// Error_Info groups the most recent context error code and human-readable message.
Error_Info :: struct {
	code: Error_Code,
	message: string,
}

// Buffer_State is returned by query_buffer_state for validation and diagnostics.
Buffer_State :: struct {
	valid: bool,
	usage: Buffer_Usage,
	size: int,
	storage_stride: int,
}

// Image_State is returned by query_image_state for validation and diagnostics.
Image_State :: struct {
	valid: bool,
	kind: Image_Kind,
	usage: Image_Usage,
	width: i32,
	height: i32,
	depth: i32,
	mip_count: i32,
	array_count: i32,
	sample_count: i32,
	format: Pixel_Format,
}

// View_State is returned by query_view_state for validation and diagnostics.
View_State :: struct {
	valid: bool,
	kind: View_Kind,
	image: Image,
	buffer: Buffer,
	width: i32,
	height: i32,
	offset: int,
	size: int,
	mip_level: i32,
	base_layer: i32,
	layer_count: i32,
	format: Pixel_Format,
	sample_count: i32,
	storage_stride: int,
}

// Features reports optional behavior supported by the active backend.
Features :: struct {
	backend: Backend,
	render_to_texture: bool,
	multiple_render_targets: bool,
	msaa_render_targets: bool,
	depth_attachment: bool,
	depth_only_pass: bool,
	sampled_depth: bool,
	storage_images: bool,
	storage_buffers: bool,
	compute: bool,
	dynamic_textures: bool,
	mipmapped_textures: bool,
	buffer_updates: bool,
	buffer_readback: bool,
}

// Limits reports public API limits plus backend-specific limits when queried from a Context.
Limits :: struct {
	max_vertex_buffers: int,
	max_vertex_attributes: int,
	max_color_attachments: int,
	max_resource_views: int,
	max_samplers: int,
	max_uniform_blocks: int,
	max_binding_groups: int,
	max_shader_bindings: int,
	max_image_mips: int,
	max_image_dimension_2d: int,
	max_image_array_layers: int,
	max_image_sample_count: int,
	max_compute_thread_groups_per_dimension: int,
}

// Pixel_Format describes image, view, attachment, and storage image formats.
Pixel_Format :: enum {
	Invalid,
	RGBA8,
	BGRA8,
	RGBA16F,
	RGBA32F,
	R32F,
	D24S8,
	D32F,
}

// Filter selects nearest or linear sampling for a Sampler.
Filter :: enum {
	Nearest,
	Linear,
}

// Wrap selects texture-coordinate behavior outside the [0, 1] range.
Wrap :: enum {
	Repeat,
	Clamp_To_Edge,
	Mirrored_Repeat,
}

// Shader_Stage identifies one compiled shader stage inside a Shader_Desc.
Shader_Stage :: enum {
	Vertex,
	Fragment,
	Compute,
}

// Shader_Stage_Set is a bit set of shader stages used by reflected layouts.
Shader_Stage_Set :: bit_set[Shader_Stage; u32]

@(private)
Pass_Kind :: enum {
	None,
	Render,
	Compute,
}

// Shader_Binding_Kind identifies reflected shader binding categories.
Shader_Binding_Kind :: enum {
	Uniform_Block,
	Resource_View,
	Sampler,
}

// Shader_Resource_Access describes reflected read/write intent for resource views.
Shader_Resource_Access :: enum {
	Unknown,
	Read,
	Write,
	Read_Write,
}

// Primitive_Type selects the topology used by a graphics pipeline.
Primitive_Type :: enum {
	Triangles,
	Lines,
	Points,
}

// Fill_Mode selects solid or wireframe rasterization.
Fill_Mode :: enum {
	Solid,
	Wireframe,
}

// Vertex_Format describes one vertex attribute element.
Vertex_Format :: enum {
	Invalid,
	Float32,
	Float32x2,
	Float32x3,
	Float32x4,
	Uint8x4_Norm,
}

// Vertex_Step_Function selects per-vertex or per-instance stepping for a vertex buffer.
Vertex_Step_Function :: enum {
	Per_Vertex,
	Per_Instance,
}

// Compare_Func selects depth comparison behavior.
Compare_Func :: enum {
	Always,
	Never,
	Less,
	Less_Equal,
	Equal,
	Greater_Equal,
	Greater,
	Not_Equal,
}

// Cull_Mode selects which triangle faces are discarded.
Cull_Mode :: enum {
	None,
	Front,
	Back,
}

// Face_Winding selects the front-face winding order.
Face_Winding :: enum {
	Clockwise,
	Counter_Clockwise,
}

// Blend_Factor selects source/destination blend factors. Default uses backend default state.
Blend_Factor :: enum {
	Default,
	Zero,
	One,
	Src_Color,
	One_Minus_Src_Color,
	Src_Alpha,
	One_Minus_Src_Alpha,
	Dst_Color,
	One_Minus_Dst_Color,
	Dst_Alpha,
	One_Minus_Dst_Alpha,
	Blend_Color,
	One_Minus_Blend_Color,
	Src_Alpha_Saturated,
}

// Blend_Op selects the color or alpha blend equation.
Blend_Op :: enum {
	Default,
	Add,
	Subtract,
	Reverse_Subtract,
	Min,
	Max,
}

// Load_Action selects how an attachment is initialized when a pass begins.
Load_Action :: enum {
	Clear,
	Load,
	Dont_Care,
}

// Store_Action selects whether an attachment value is preserved when a pass ends.
Store_Action :: enum {
	Store,
	Dont_Care,
}

// Range is a raw byte span used for uploads, readback, and shader bytecode.
Range :: struct {
	ptr: rawptr,
	size: int,
}

// Color is a linear RGBA color value.
Color :: struct {
	r: f32,
	g: f32,
	b: f32,
	a: f32,
}

// Color_Attachment_Action controls load/store behavior for one color attachment.
//
// A fully zero-init Color_Attachment_Action means "use the framework default":
// clear to opaque black `{0, 0, 0, 1}`, store the result. Setting any field
// (including `clear_value`) opts the slot out of defaulting and uses the
// supplied values verbatim. See `pass_action_with_defaults`.
Color_Attachment_Action :: struct {
	load_action: Load_Action,
	store_action: Store_Action,
	clear_value: Color,
}

// Depth_Attachment_Action controls load/store behavior for a depth attachment.
//
// A fully zero-init Depth_Attachment_Action means "use the framework default":
// clear to `1.0`, store the result. Setting any field (including a
// `clear_value` of 0) opts out of defaulting and uses the supplied values.
Depth_Attachment_Action :: struct {
	load_action: Load_Action,
	store_action: Store_Action,
	clear_value: f32,
}

// Stencil_Attachment_Action controls load/store behavior for a stencil attachment.
//
// The framework default is clear-to-zero, store. Because every default field
// is the enum/integer zero value, the zero-init form already matches the
// default; no explicit defaulting is needed.
Stencil_Attachment_Action :: struct {
	load_action: Load_Action,
	store_action: Store_Action,
	clear_value: u8,
}

// Pass_Action groups all attachment load/store actions for begin_pass.
//
// Zero-init contract (AAA roadmap item 35): a fully zero-init `Pass_Action`
// produces the same rendering as `default_pass_action()` — clear color to
// opaque black, clear depth to 1.0, clear stencil to 0, store every
// attachment. Defaults apply per attachment slot: any color slot whose
// `Color_Attachment_Action` is fully zero is filled in with the color
// default; the depth slot is filled in when its `Depth_Attachment_Action`
// is fully zero. Slots with any field set (e.g. only `clear_value`) keep
// the user-supplied values verbatim. Resolution happens at the descriptor
// boundary in `begin_pass`; see `pass_action_with_defaults` for the same
// transform exposed for inspection.
Pass_Action :: struct {
	colors: [MAX_COLOR_ATTACHMENTS]Color_Attachment_Action,
	depth: Depth_Attachment_Action,
	stencil: Stencil_Attachment_Action,
}

// Desc configures a graphics Context.
Desc :: struct {
	backend: Backend,
	width: i32,
	height: i32,
	native_window: rawptr,
	swapchain_format: Pixel_Format,
	vsync: bool,
	debug: bool,
	label: string,
}

// Buffer_Desc creates a Buffer. storage_stride > 0 creates a structured storage buffer.
Buffer_Desc :: struct {
	label: string,
	usage: Buffer_Usage,
	size: int,
	storage_stride: int,
	data: Range,
}

// Buffer_Update_Desc describes a CPU-to-GPU buffer update.
Buffer_Update_Desc :: struct {
	buffer: Buffer,
	offset: int,
	data: Range,
}

// Buffer_Read_Desc describes a synchronous GPU-to-CPU buffer readback.
Buffer_Read_Desc :: struct {
	buffer: Buffer,
	offset: int,
	data: Range,
}

// Image_Desc creates an Image resource and optional immutable initial contents.
//
// Zero-count default (AAA roadmap item 34): leave `mip_count`, `array_count`,
// `sample_count`, and `depth` at zero to mean "1". A descriptor that omits all
// counts produces a single-mip, single-layer, single-sample image — the most
// common shape — without forcing every call site to spell out the ones.
// Negative values are rejected.
Image_Desc :: struct {
	label: string,
	kind: Image_Kind,
	usage: Image_Usage,
	width: i32,
	height: i32,
	depth: i32,        // 0 means 1.
	mip_count: i32,    // 0 means 1.
	array_count: i32,  // 0 means 1.
	sample_count: i32, // 0 means 1.
	format: Pixel_Format,
	data: Range,
	mips: [MAX_IMAGE_MIPS]Image_Subresource_Data,
}

// Image_Subresource_Data supplies initial data for one image mip level.
Image_Subresource_Data :: struct {
	data: Range,
	row_pitch: i32,
	slice_pitch: i32,
}

// Image_Update_Desc describes a CPU-to-GPU image subregion update.
Image_Update_Desc :: struct {
	image: Image,
	mip_level: i32,
	array_layer: i32,
	x: i32,
	y: i32,
	width: i32,
	height: i32,
	data: Range,
	row_pitch: i32,
}

// Image_Resolve_Desc resolves a multisampled color image into a single-sampled image.
Image_Resolve_Desc :: struct {
	source: Image,
	destination: Image,
}

// Texture_View_Desc creates a sampled texture view.
Texture_View_Desc :: struct {
	image: Image,
	format: Pixel_Format,
	base_mip: i32,
	mip_count: i32,
	base_layer: i32,
	layer_count: i32,
}

// Storage_Image_View_Desc creates a storage image view.
Storage_Image_View_Desc :: struct {
	image: Image,
	format: Pixel_Format,
	mip_level: i32,
	base_layer: i32,
	layer_count: i32,
}

// Storage_Buffer_View_Desc creates a storage buffer byte range view.
Storage_Buffer_View_Desc :: struct {
	buffer: Buffer,
	offset: int,
	size: int,
}

// Color_Attachment_View_Desc creates a render-target attachment view.
Color_Attachment_View_Desc :: struct {
	image: Image,
	format: Pixel_Format,
	mip_level: i32,
	layer: i32,
}

// Depth_Stencil_Attachment_View_Desc creates a depth-stencil attachment view.
Depth_Stencil_Attachment_View_Desc :: struct {
	image: Image,
	format: Pixel_Format,
	mip_level: i32,
	layer: i32,
}

// View_Desc creates exactly one view flavor over a parent image or buffer.
View_Desc :: struct {
	label: string,
	texture: Texture_View_Desc,
	storage_image: Storage_Image_View_Desc,
	storage_buffer: Storage_Buffer_View_Desc,
	color_attachment: Color_Attachment_View_Desc,
	depth_stencil_attachment: Depth_Stencil_Attachment_View_Desc,
}

// Render_Target_Desc creates the common image/view bundle for one offscreen render target.
//
// `sample_count` follows the Image_Desc zero-count convention: 0 means 1.
Render_Target_Desc :: struct {
	label: string,
	width: i32,
	height: i32,
	sample_count: i32, // 0 means 1.
	color_format: Pixel_Format,
	depth_format: Pixel_Format,
	sampled_color: bool,
	sampled_depth: bool,
}

// Render_Target groups explicit handles for a simple offscreen color/depth target.
Render_Target :: struct {
	width: i32,
	height: i32,
	sample_count: i32,
	color_format: Pixel_Format,
	depth_format: Pixel_Format,
	color_image: Image,
	color_attachment: View,
	color_sample: View,
	depth_image: Image,
	depth_stencil_attachment: View,
	depth_sample: View,
}

// Sampler_Desc creates a texture sampler state.
Sampler_Desc :: struct {
	label: string,
	min_filter: Filter,
	mag_filter: Filter,
	mip_filter: Filter,
	wrap_u: Wrap,
	wrap_v: Wrap,
	wrap_w: Wrap,
}

// Shader_Stage_Desc provides backend bytecode for one shader stage.
Shader_Stage_Desc :: struct {
	stage: Shader_Stage,
	entry: string,
	bytecode: Range,
}

// Shader_Binding_Desc carries Slang-reflected binding metadata for runtime validation.
//
// `array_count` carries the descriptor-array element count reflected from
// Slang (AAA roadmap item 28 / APE-24). `0` and `1` both mean "scalar
// binding"; a value `> 1` declares a fixed-size descriptor array. The runtime
// cross-checks this against the matching `Binding_Group_Layout_Entry_Desc`
// when a pipeline binds against the layout. `unsized = true` reserves the
// binding for the runtime / bindless `Binding_Heap` path.
Shader_Binding_Desc :: struct {
	active: bool,
	stage: Shader_Stage,
	kind: Shader_Binding_Kind,
	group: u32,
	slot: u32,
	native_slot: u32,
	native_space: u32,
	array_count: u32,
	unsized: bool,
	name: string,
	size: u32,
	view_kind: View_Kind,
	access: Shader_Resource_Access,
	storage_image_format: Pixel_Format,
	storage_buffer_stride: u32,
}

// Binding_Group_Uniform_Block_Layout_Desc describes one reflected uniform block entry.
Binding_Group_Uniform_Block_Layout_Desc :: struct {
	size: u32,
}

// Binding_Group_Resource_View_Layout_Desc describes one reflected resource view entry.
Binding_Group_Resource_View_Layout_Desc :: struct {
	view_kind: View_Kind,
	access: Shader_Resource_Access,
	storage_image_format: Pixel_Format,
	storage_buffer_stride: u32,
}

// Binding_Group_Layout_Entry_Desc describes one logical entry in a generated binding group.
//
// `array_count` is the descriptor-array element count reflected from Slang
// (AAA roadmap item 28 / APE-24). `0` and `1` both mean "scalar binding"; a
// value `> 1` declares a fixed-size descriptor array that occupies the slot
// range `[slot, slot + array_count)` in the entry's per-kind slot space.
//
// `unsized = true` reserves the entry for the runtime / bindless `Binding_Heap`
// path (see `gfx/bindless.odin` and gfx-bindless-note.md §5.3). Item 28 ships
// fixed arrays only; `unsized = true` is rejected at layout creation until the
// `Binding_Heap` backend lands.
Binding_Group_Layout_Entry_Desc :: struct {
	active: bool,
	stages: Shader_Stage_Set,
	kind: Shader_Binding_Kind,
	slot: u32,
	array_count: u32,
	unsized: bool,
	name: string,
	uniform_block: Binding_Group_Uniform_Block_Layout_Desc,
	resource_view: Binding_Group_Resource_View_Layout_Desc,
}

// Binding_Group_Native_Binding_Desc maps one logical binding entry to a backend native slot.
Binding_Group_Native_Binding_Desc :: struct {
	active: bool,
	target: Backend,
	stage: Shader_Stage,
	kind: Shader_Binding_Kind,
	slot: u32,
	native_slot: u32,
	native_space: u32,
}

// Binding_Group_Layout_Desc is generated from Slang reflection and creates Binding_Group_Layout handles.
Binding_Group_Layout_Desc :: struct {
	label: string,
	group: u32,
	entries: [MAX_BINDING_GROUP_ENTRIES]Binding_Group_Layout_Entry_Desc,
	native_bindings: [MAX_SHADER_BINDINGS]Binding_Group_Native_Binding_Desc,
}

// Pipeline_Layout_Desc composes generated binding group layouts for one pipeline family.
Pipeline_Layout_Desc :: struct {
	label: string,
	group_layouts: [MAX_BINDING_GROUPS]Binding_Group_Layout,
}

// Binding_Group_Desc creates an object-backed binding group from a generated layout handle.
Binding_Group_Desc :: struct {
	label: string,
	layout: Binding_Group_Layout,
	views: [MAX_RESOURCE_VIEWS]View,
	samplers: [MAX_SAMPLERS]Sampler,
	// arrays carries fixed-size descriptor-array payloads (see
	// gfx/bindless.odin and gfx-bindless-note.md §5). Slot count is
	// MAX_BINDING_GROUP_ARRAYS; entries with active = false are ignored.
	// validate_binding_group_desc enforces the shape once item 28 lands;
	// today the field is locked declaration-only and zero-init means
	// "no fixed arrays", so existing literals stay valid.
	arrays: [MAX_BINDING_GROUP_ARRAYS]Binding_Group_Array_Desc,
}

// Shader_Vertex_Input_Desc carries Slang-reflected vertex input metadata.
Shader_Vertex_Input_Desc :: struct {
	active: bool,
	semantic: string,
	semantic_index: u32,
	format: Vertex_Format,
}

// Shader_Desc creates a backend shader object from compiled stage bytecode and metadata.
Shader_Desc :: struct {
	label: string,
	stages: [3]Shader_Stage_Desc,
	has_binding_metadata: bool,
	bindings: [MAX_SHADER_BINDINGS]Shader_Binding_Desc,
	has_vertex_input_metadata: bool,
	vertex_inputs: [MAX_VERTEX_ATTRIBUTES]Shader_Vertex_Input_Desc,
}

// Depth_State configures depth testing for a graphics pipeline.
Depth_State :: struct {
	format: Pixel_Format,
	enabled: bool,
	write_enabled: bool,
	compare: Compare_Func,
}

// Raster_State configures rasterization for a graphics pipeline.
Raster_State :: struct {
	fill_mode: Fill_Mode,
	cull_mode: Cull_Mode,
	winding: Face_Winding,
}

// Blend_State configures color blending for one render target.
Blend_State :: struct {
	enabled: bool,
	src_factor: Blend_Factor,
	dst_factor: Blend_Factor,
	op: Blend_Op,
	src_alpha_factor: Blend_Factor,
	dst_alpha_factor: Blend_Factor,
	alpha_op: Blend_Op,
}

// Color_State configures write mask and blending for one color attachment slot.
Color_State :: struct {
	write_mask: u8,
	blend: Blend_State,
}

// Vertex_Buffer_Layout describes stride and stepping for one vertex buffer slot.
Vertex_Buffer_Layout :: struct {
	stride: u32,
	step_func: Vertex_Step_Function,
	step_rate: u32,
}

// Vertex_Attribute_Desc maps one shader vertex semantic to a buffer format and offset.
Vertex_Attribute_Desc :: struct {
	semantic: cstring,
	semantic_index: u32,
	format: Vertex_Format,
	buffer_slot: u32,
	offset: u32,
}

// Layout_Desc groups vertex buffer layouts and attributes for a graphics pipeline.
Layout_Desc :: struct {
	buffers: [MAX_VERTEX_BUFFERS]Vertex_Buffer_Layout,
	attrs: [MAX_VERTEX_ATTRIBUTES]Vertex_Attribute_Desc,
}

// Pipeline_Desc creates an immutable graphics pipeline.
Pipeline_Desc :: struct {
	label: string,
	shader: Shader,
	pipeline_layout: Pipeline_Layout,
	primitive_type: Primitive_Type,
	index_type: Index_Type,
	layout: Layout_Desc,
	color_formats: [MAX_COLOR_ATTACHMENTS]Pixel_Format,
	depth_only: bool,
	colors: [MAX_COLOR_ATTACHMENTS]Color_State,
	depth: Depth_State,
	raster: Raster_State,
}

// Compute_Pipeline_Desc creates an immutable compute pipeline.
Compute_Pipeline_Desc :: struct {
	label: string,
	shader: Shader,
	pipeline_layout: Pipeline_Layout,
}

// Buffer_Binding binds a buffer handle with a byte offset.
Buffer_Binding :: struct {
	buffer: Buffer,
	offset: int,
}

// Bindings contains transient resources applied before draw or dispatch.
Bindings :: struct {
	vertex_buffers: [MAX_VERTEX_BUFFERS]Buffer_Binding,
	index_buffer: Buffer_Binding,
	views: [MAX_BINDING_GROUPS][MAX_RESOURCE_VIEWS]View,
	samplers: [MAX_BINDING_GROUPS][MAX_SAMPLERS]Sampler,
}

// Pass_Desc begins a render pass. With no explicit attachments, the pass targets the context's implicit window swapchain.
Pass_Desc :: struct {
	label: string,
	color_attachments: [MAX_COLOR_ATTACHMENTS]View,
	depth_stencil_attachment: View,
	action: Pass_Action,
}

// Compute_Pass_Desc begins a compute-only pass.
Compute_Pass_Desc :: struct {
	label: string,
}

@(private)
Resource_Pool :: struct {
	generations: [dynamic]u32,
	live: [dynamic]bool,
	free_slots: [dynamic]u32,
	live_count: int,
}

@(private)
Shader_State :: struct {
	valid: bool,
	has_vertex: bool,
	has_fragment: bool,
	has_compute: bool,
	has_binding_metadata: bool,
	bindings: [MAX_SHADER_BINDINGS]Shader_Binding_Desc,
	has_vertex_input_metadata: bool,
	vertex_inputs: [MAX_VERTEX_ATTRIBUTES]Shader_Vertex_Input_Desc,
}

@(private)
Pipeline_State :: struct {
	valid: bool,
	shader: Shader,
	pipeline_layout: Pipeline_Layout,
}

@(private)
Compute_Pipeline_State :: struct {
	valid: bool,
	shader: Shader,
	pipeline_layout: Pipeline_Layout,
}

@(private)
Binding_Group_Layout_State :: struct {
	valid: bool,
	desc: Binding_Group_Layout_Desc,
}

@(private)
Pipeline_Layout_State :: struct {
	valid: bool,
	desc: Pipeline_Layout_Desc,
}

@(private)
Binding_Group_State :: struct {
	valid: bool,
	layout: Binding_Group_Layout,
	desc: Binding_Group_Desc,
}

@(private)
MAX_COMPUTE_PASS_RESOURCE_WRITES :: MAX_BINDING_GROUPS * MAX_RESOURCE_VIEWS

// Context owns all GPU resources and current frame state for one backend instance.
Context :: struct {
	desc: Desc,
	backend: Backend,
	initialized: bool,
	in_pass: bool,
	pass_kind: Pass_Kind,
	frame_index: u64,
	context_id: u32,
	buffer_pool: Resource_Pool,
	image_pool: Resource_Pool,
	view_pool: Resource_Pool,
	sampler_pool: Resource_Pool,
	shader_pool: Resource_Pool,
	pipeline_pool: Resource_Pool,
	compute_pipeline_pool: Resource_Pool,
	binding_group_layout_pool: Resource_Pool,
	pipeline_layout_pool: Resource_Pool,
	binding_group_pool: Resource_Pool,
	transient_allocator_pool: Resource_Pool,
	transient_allocator_states: map[Transient_Allocator]Transient_Allocator_State,
	shader_states: map[Shader]Shader_State,
	pipeline_states: map[Pipeline]Pipeline_State,
	compute_pipeline_states: map[Compute_Pipeline]Compute_Pipeline_State,
	binding_group_layout_states: map[Binding_Group_Layout]Binding_Group_Layout_State,
	pipeline_layout_states: map[Pipeline_Layout]Pipeline_Layout_State,
	binding_group_states: map[Binding_Group]Binding_Group_State,
	current_pipeline: Pipeline,
	current_compute_pipeline: Compute_Pipeline,
	current_bindings: Bindings,
	compute_pass_resource_writes: [MAX_COMPUTE_PASS_RESOURCE_WRITES]View_State,
	compute_pass_resource_write_count: int,
	pass_color_attachments: [MAX_COLOR_ATTACHMENTS]View,
	pass_depth_stencil_attachment: View,
	backend_data: rawptr,
	last_error: string,
	last_error_code: Error_Code,
	last_error_storage: [256]u8,
}

// default_pass_action returns clear/store defaults for color, depth, and stencil attachments.
//
// Equivalent to `pass_action_with_defaults({})`. A zero-init `Pass_Action` passed
// to `begin_pass` produces the same rendering — see the `Pass_Action` doc.
default_pass_action :: proc() -> Pass_Action {
	return pass_action_with_defaults({})
}

// backend_name returns a stable lowercase display name for a Backend.
backend_name :: proc(backend: Backend) -> string {
	switch backend {
	case .Auto:
		return "auto"
	case .Null:
		return "null"
	case .D3D11:
		return "d3d11"
	case .Vulkan:
		return "vulkan"
	}

	return "unknown"
}

// buffer_valid reports whether a Buffer handle is nonzero.
buffer_valid :: proc(buffer: Buffer) -> bool {
	return u64(buffer) != 0
}

// image_valid reports whether an Image handle is nonzero.
image_valid :: proc(image: Image) -> bool {
	return u64(image) != 0
}

// view_valid reports whether a View handle is nonzero.
view_valid :: proc(view: View) -> bool {
	return u64(view) != 0
}

// sampler_valid reports whether a Sampler handle is nonzero.
sampler_valid :: proc(sampler: Sampler) -> bool {
	return u64(sampler) != 0
}

// shader_valid reports whether a Shader handle is nonzero.
shader_valid :: proc(shader: Shader) -> bool {
	return u64(shader) != 0
}

// pipeline_valid reports whether a Pipeline handle is nonzero.
pipeline_valid :: proc(pipeline: Pipeline) -> bool {
	return u64(pipeline) != 0
}

// compute_pipeline_valid reports whether a Compute_Pipeline handle is nonzero.
compute_pipeline_valid :: proc(pipeline: Compute_Pipeline) -> bool {
	return u64(pipeline) != 0
}

// binding_group_layout_valid reports whether a Binding_Group_Layout handle is nonzero.
binding_group_layout_valid :: proc(layout: Binding_Group_Layout) -> bool {
	return u64(layout) != 0
}

// pipeline_layout_valid reports whether a Pipeline_Layout handle is nonzero.
pipeline_layout_valid :: proc(layout: Pipeline_Layout) -> bool {
	return u64(layout) != 0
}

// binding_group_valid reports whether a Binding_Group handle is nonzero.
binding_group_valid :: proc(group: Binding_Group) -> bool {
	return u64(group) != 0
}
