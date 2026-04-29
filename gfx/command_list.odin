package gfx

// Command_List / Pass_Encoder API sketch — AAA roadmap item 9.
//
// This file is a header-only stub. No bodies are implemented; every entry
// point panics or returns zero. The shapes here reflect the decisions in
// docs/private/gfx-command-recording-note.md:
//
//   §5 — recording uses explicit command encoders (Command_List + per-pass
//        encoders). Context becomes a factory and submission point.
//   §6 — Command_List is single-owner-thread; encoders never cross threads
//        while open; lists transfer at finish/submit; Context is one-thread.
//   §7 — per-pass mutable state (in_pass, current_pipeline, bindings, pass
//        attachments) lives on the encoder, not on Context.
//
// The names here intentionally do not collide with the existing immediate-mode
// procs (`begin_pass`, `apply_pipeline`, `draw`, …). The existing Context-based
// API stays the shipping path until APE-6 audits and migrates each call.

// Command_Queue selects the queue submit_command_list targets.
//
// Today only `Graphics` is honored by the D3D11 backend. The enum exists so
// async compute and explicit transfer (items 21, 22 of the AAA roadmap) do
// not require a parallel API later.
Command_Queue :: enum {
	Graphics,
	Compute,
	Transfer,
}

// Command_List_State tracks the recording -> finished -> submitted lifecycle.
//
// `Recording`  — accepts begin_*_pass and per-encoder calls.
// `Finished`   — sealed by `finish_command_list`; may be moved across threads
//                and handed to the submission thread.
// `Submitted`  — consumed by `submit_command_list`; further use is invalid
//                until the list is destroyed.
Command_List_State :: enum {
	Recording,
	Finished,
	Submitted,
}

// Command_List is the unit of recorded GPU work.
//
// Owned by exactly one thread at a time (see command-recording-note §6.1).
// The owning thread records passes into the list, calls `finish_command_list`,
// and may then transfer ownership to the Context thread for `submit_command_list`.
//
// Per command-recording-note §7, the list carries the per-recorder error slot
// (drained onto Context at submit) and the backend-private recording state
// (a D3D11 deferred context, a Vulkan VkCommandBuffer + VkCommandPool checkout,
// or a D3D12 ID3D12GraphicsCommandList + allocator checkout).
Command_List :: struct {
	ctx: ^Context,
	frame_index: u64,
	state: Command_List_State,
	open_pass_kind: Pass_Kind,
	queue: Command_Queue,

	// Per-list error slot (command-recording-note §7.3). `submit_command_list`
	// drains a non-empty slot onto Context.last_error so user code can keep
	// observing errors through `gfx.last_error(ctx)`.
	last_error: string,
	last_error_code: Error_Code,
	last_error_storage: [256]u8,

	// Backend-private recording state. Opaque to the public API.
	backend_data: rawptr,
}

// Render_Pass_Encoder records draw work inside one render pass.
//
// Opened by `cmd_begin_render_pass`, closed by `cmd_end_render_pass`. Single-
// thread-affine for the life of the pass: never transfer an open encoder
// (command-recording-note §6.3). All per-pass mutable state that the current
// `^Context` carries today lives here once APE-6 lands.
Render_Pass_Encoder :: struct {
	list: ^Command_List,
	open: bool,
	current_pipeline: Pipeline,
	current_bindings: Bindings,
	color_attachments: [MAX_COLOR_ATTACHMENTS]View,
	depth_stencil_attachment: View,
}

// Compute_Pass_Encoder records dispatch work inside one compute pass.
//
// Opened by `cmd_begin_compute_pass`, closed by `cmd_end_compute_pass`.
// Same thread-affinity rule as `Render_Pass_Encoder`. Carries the per-pass
// resource-write tracking that lives on `^Context` today.
Compute_Pass_Encoder :: struct {
	list: ^Command_List,
	open: bool,
	current_pipeline: Compute_Pipeline,
	current_bindings: Bindings,
	resource_writes: [MAX_COMPUTE_PASS_RESOURCE_WRITES]View_State,
	resource_write_count: int,
}

// create_command_list allocates a new Command_List bound to `ctx`.
//
// Must be called on the Context thread; the returned list's initial owner is
// the caller and may be moved to a worker before recording begins.
create_command_list :: proc(ctx: ^Context) -> (Command_List, bool) {
	panic("gfx.create_command_list: unimplemented (APE-5 sketch only)")
}

// finish_command_list seals a Command_List for submission.
//
// Called on the recording thread after the last `cmd_end_*_pass`. After this
// returns true the list is in state `Finished` and may transfer to another
// thread for submission.
finish_command_list :: proc(list: ^Command_List) -> bool {
	panic("gfx.finish_command_list: unimplemented (APE-5 sketch only)")
}

// submit_command_list hands a finished list to the named queue.
//
// Called on the Context thread. Drains `list.last_error` onto `ctx` and
// transitions the list to state `Submitted`. Today only `.Graphics` is
// honored by the D3D11 backend; other queues are reserved for future work.
submit_command_list :: proc(ctx: ^Context, list: ^Command_List, queue: Command_Queue = .Graphics) -> bool {
	panic("gfx.submit_command_list: unimplemented (APE-5 sketch only)")
}

// destroy_command_list releases backend resources held by a list.
//
// Safe to call on a `Recording`, `Finished`, or `Submitted` list. Lists must
// be destroyed before their owning Context shuts down.
destroy_command_list :: proc(list: ^Command_List) {
	panic("gfx.destroy_command_list: unimplemented (APE-5 sketch only)")
}

// command_list_last_error returns the most recent record-time error.
//
// Use this from the worker thread before `finish_command_list` to surface
// validation failures detected during recording.
command_list_last_error :: proc(list: ^Command_List) -> string {
	panic("gfx.command_list_last_error: unimplemented (APE-5 sketch only)")
}

// command_list_last_error_code returns the machine-readable code that pairs
// with `command_list_last_error`.
command_list_last_error_code :: proc(list: ^Command_List) -> Error_Code {
	panic("gfx.command_list_last_error_code: unimplemented (APE-5 sketch only)")
}

// cmd_begin_render_pass opens a render pass on a Command_List.
//
// Returns the encoder that subsequent `cmd_apply_*` and `cmd_draw` calls
// take. The list must be in state `Recording` and have no other encoder open.
cmd_begin_render_pass :: proc(list: ^Command_List, desc: Pass_Desc) -> (Render_Pass_Encoder, bool) {
	panic("gfx.cmd_begin_render_pass: unimplemented (APE-5 sketch only)")
}

// cmd_end_render_pass closes the render pass owned by `encoder`.
//
// After this returns true the encoder is no longer usable; the parent list
// may open a new encoder or be finished.
cmd_end_render_pass :: proc(encoder: ^Render_Pass_Encoder) -> bool {
	panic("gfx.cmd_end_render_pass: unimplemented (APE-5 sketch only)")
}

// cmd_apply_pipeline binds a graphics pipeline on a render pass encoder.
cmd_apply_pipeline :: proc(encoder: ^Render_Pass_Encoder, pipeline: Pipeline) -> bool {
	panic("gfx.cmd_apply_pipeline: unimplemented (APE-5 sketch only)")
}

// cmd_apply_bindings binds vertex/index buffers, resource views, and samplers
// on a render pass encoder.
cmd_apply_bindings :: proc(encoder: ^Render_Pass_Encoder, bindings: Bindings) -> bool {
	panic("gfx.cmd_apply_bindings: unimplemented (APE-5 sketch only)")
}

// cmd_apply_uniforms uploads one reflected uniform block on a render pass
// encoder.
cmd_apply_uniforms :: proc(encoder: ^Render_Pass_Encoder, group: u32, slot: int, data: Range) -> bool {
	panic("gfx.cmd_apply_uniforms: unimplemented (APE-5 sketch only)")
}

// cmd_draw issues one indexed or non-indexed draw on a render pass encoder.
//
// Index vs vertex interpretation follows the active pipeline's `index_type`,
// matching the existing immediate-mode `gfx.draw`.
cmd_draw :: proc(encoder: ^Render_Pass_Encoder, base_element: i32, num_elements: i32, num_instances: i32 = 1) -> bool {
	panic("gfx.cmd_draw: unimplemented (APE-5 sketch only)")
}

// cmd_begin_compute_pass opens a compute pass on a Command_List.
//
// Returns the encoder for subsequent `cmd_apply_compute_*` and `cmd_dispatch`
// calls. The list must be in state `Recording` with no other encoder open.
cmd_begin_compute_pass :: proc(list: ^Command_List, desc: Compute_Pass_Desc = {}) -> (Compute_Pass_Encoder, bool) {
	panic("gfx.cmd_begin_compute_pass: unimplemented (APE-5 sketch only)")
}

// cmd_end_compute_pass closes the compute pass owned by `encoder`.
cmd_end_compute_pass :: proc(encoder: ^Compute_Pass_Encoder) -> bool {
	panic("gfx.cmd_end_compute_pass: unimplemented (APE-5 sketch only)")
}

// cmd_apply_compute_pipeline binds a compute pipeline on a compute pass
// encoder.
cmd_apply_compute_pipeline :: proc(encoder: ^Compute_Pass_Encoder, pipeline: Compute_Pipeline) -> bool {
	panic("gfx.cmd_apply_compute_pipeline: unimplemented (APE-5 sketch only)")
}

// cmd_apply_compute_bindings binds resource views and samplers on a compute
// pass encoder. Vertex/index buffer slots in `bindings` must be empty.
cmd_apply_compute_bindings :: proc(encoder: ^Compute_Pass_Encoder, bindings: Bindings) -> bool {
	panic("gfx.cmd_apply_compute_bindings: unimplemented (APE-5 sketch only)")
}

// cmd_apply_compute_uniforms uploads one reflected uniform block on a compute
// pass encoder.
cmd_apply_compute_uniforms :: proc(encoder: ^Compute_Pass_Encoder, group: u32, slot: int, data: Range) -> bool {
	panic("gfx.cmd_apply_compute_uniforms: unimplemented (APE-5 sketch only)")
}

// cmd_dispatch issues one compute dispatch with explicit thread-group counts.
cmd_dispatch :: proc(encoder: ^Compute_Pass_Encoder, group_count_x: u32 = 1, group_count_y: u32 = 1, group_count_z: u32 = 1) -> bool {
	panic("gfx.cmd_dispatch: unimplemented (APE-5 sketch only)")
}
