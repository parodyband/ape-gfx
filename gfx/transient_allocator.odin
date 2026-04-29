package gfx

// Transient uniform / storage allocation API — AAA roadmap items 23 (sketch)
// and 24 (D3D11-backed implementation).
//
// Design composes with:
//
//   gfx-command-recording-note.md §6 / §7 — single-thread `Context`,
//                                            per-recorder mutable state
//                                            lives off `Context`.
//   gfx-queue-submission-note.md   §3 / §5 — `Timeline_Semaphore` is the
//                                            public sync primitive; submits
//                                            signal a value when their
//                                            work completes.
//   gfx-barriers-note.md           §9     — `Resource_Usage` names buffer
//                                            states; `Indirect_Argument`
//                                            is first-class.
//
// APE-25 will land `apply_uniform_at` for offset-aware uniform binding;
// today the typical consumer copies through `Transient_Slice.mapped` into
// the existing immediate-mode `apply_uniforms` path.

// TRANSIENT_UNIFORM_ALIGNMENT is the public alignment for slices returned
// with `Transient_Usage.Uniform`.
//
// 256 is the strictest of the three target backends (D3D12 CB offset);
// using it on D3D11 too keeps per-frame heap usage portable across
// builds. See gfx-transient-allocator-note.md §4.
TRANSIENT_UNIFORM_ALIGNMENT :: 256

// TRANSIENT_STORAGE_ALIGNMENT is the public alignment for slices returned
// with `Transient_Usage.Storage`.
TRANSIENT_STORAGE_ALIGNMENT :: 64

// TRANSIENT_VERTEX_ALIGNMENT is the public alignment for slices returned
// with `Transient_Usage.Vertex`.
TRANSIENT_VERTEX_ALIGNMENT :: 4

// TRANSIENT_INDEX_ALIGNMENT is the public alignment for slices returned
// with `Transient_Usage.Index`.
TRANSIENT_INDEX_ALIGNMENT :: 4

// TRANSIENT_INDIRECT_ALIGNMENT is the public alignment for slices returned
// with `Transient_Usage.Indirect`.
TRANSIENT_INDIRECT_ALIGNMENT :: 4

@(private)
TRANSIENT_DEFAULT_CAPACITY :: 4 * 1024 * 1024

// Transient_Allocator is the opaque handle for a per-frame linear allocator.
//
// Created by `create_transient_allocator`, drained by
// `reset_transient_allocator`, fed by `transient_alloc`. Owned by exactly
// one thread at a time — the typical shape is one allocator per recorder
// thread. See gfx-transient-allocator-note.md §2.
Transient_Allocator :: distinct u64
Transient_Allocator_Invalid :: Transient_Allocator(0)

// Transient_Usage names which role a transient allocation will fulfill.
//
// One usage per `transient_alloc` call. The allocator's
// `Transient_Usage_Set` (declared at creation) gates which roles the
// backing buffer may serve; asking for a role outside that set is a
// validation error. See note §3.
Transient_Usage :: enum {
	Uniform,
	Storage,
	Vertex,
	Index,
	Indirect,
}

// Transient_Usage_Set is the bit set baked into the allocator's backing
// buffer at creation. Empty is rejected.
Transient_Usage_Set :: bit_set[Transient_Usage; u32]

// Transient_Allocator_Desc creates a `Transient_Allocator`.
//
// `capacity == 0` means "pick a backend default" (currently 4 MiB per
// requested role). `usage` must contain at least one role (note §2).
// `Transient_Usage.Indirect` composes only with `.Storage` for compute-
// driven indirect or alone for CPU-prepared indirect; see note §5.
Transient_Allocator_Desc :: struct {
	label:    string,
	capacity: int,
	usage:    Transient_Usage_Set,
}

// Transient_Slice is one allocation out of a `Transient_Allocator`.
//
// `buffer` is the role-specific backing buffer for the requested usage;
// the slice lives at `[offset, offset + size)`. `mapped` is a CPU pointer
// into the persistently mapped backing buffer — write through it directly
// or cast to a typed pointer. Validity ends at the next
// `reset_transient_allocator` on the parent allocator; do not retain
// `mapped` across that boundary.
//
// `offset` is aligned per `TRANSIENT_*_ALIGNMENT` for the requested
// usage; `size` is rounded up to the same alignment so consecutive
// allocations stay aligned. See note §3 / §4.
Transient_Slice :: struct {
	buffer: Buffer,
	offset: int,
	size:   int,
	mapped: rawptr,
}

@(private)
Transient_Chunk :: struct {
	enabled:  bool,
	buffer:   Buffer,
	capacity: int,
	cursor:   int,
	mapped:   rawptr,
}

@(private)
Transient_Allocator_State :: struct {
	valid:    bool,
	label:    string,
	capacity: int,
	usage:    Transient_Usage_Set,
	chunks:   [Transient_Usage]Transient_Chunk,
}

// create_transient_allocator allocates a new per-frame linear allocator.
//
// Must be called on the Context thread. The returned allocator's owning
// thread is the caller and may be moved to a worker before the first
// `transient_alloc`, mirroring `Command_List` ownership. Returns
// `Transient_Allocator_Invalid` and `false` on validation/backend
// failure; check `last_error(ctx)`.
//
// example:
//   allocator, ok := gfx.create_transient_allocator(&ctx, {
//       label    = "frame uniforms",
//       capacity = 4 * 1024 * 1024,
//       usage    = { .Uniform },
//   })
create_transient_allocator :: proc(ctx: ^Context, desc: Transient_Allocator_Desc) -> (Transient_Allocator, bool) {
	if !require_initialized(ctx, "gfx.create_transient_allocator") {
		return Transient_Allocator_Invalid, false
	}

	if desc.usage == {} {
		set_validation_error(ctx, "gfx.create_transient_allocator: usage must include at least one role")
		return Transient_Allocator_Invalid, false
	}
	if desc.capacity < 0 {
		set_validation_error(ctx, "gfx.create_transient_allocator: capacity must be non-negative")
		return Transient_Allocator_Invalid, false
	}
	if .Indirect in desc.usage && (.Uniform in desc.usage || .Vertex in desc.usage || .Index in desc.usage) {
		set_validation_error(ctx, "gfx.create_transient_allocator: Indirect composes only with Storage")
		return Transient_Allocator_Invalid, false
	}

	capacity := desc.capacity
	if capacity == 0 {
		capacity = TRANSIENT_DEFAULT_CAPACITY
	}

	handle_id := alloc_resource_id(ctx, &ctx.transient_allocator_pool, "gfx.create_transient_allocator")
	if handle_id == 0 {
		return Transient_Allocator_Invalid, false
	}
	handle := Transient_Allocator(handle_id)
	transient_register_context(ctx)

	state := Transient_Allocator_State {
		valid    = true,
		label    = desc.label,
		capacity = capacity,
		usage    = desc.usage,
	}

	for role in Transient_Usage {
		if role not_in desc.usage {
			continue
		}

		buffer, mapped, ok := backend_create_transient_chunk(ctx, role, capacity, desc.label)
		if !ok {
			transient_release_chunks(ctx, &state)
			cancel_resource_id(&ctx.transient_allocator_pool, handle_id)
			return Transient_Allocator_Invalid, false
		}
		state.chunks[role] = {
			enabled  = true,
			buffer   = buffer,
			capacity = capacity,
			cursor   = 0,
			mapped   = mapped,
		}
	}

	if ctx.transient_allocator_states == nil {
		ctx.transient_allocator_states = make(map[Transient_Allocator]Transient_Allocator_State)
	}
	ctx.transient_allocator_states[handle] = state
	return handle, true
}

// destroy_transient_allocator releases backing storage held by an allocator.
//
// All in-flight submits that read from the allocator's backing buffer
// must have completed before destruction; the allocator does not block
// on its own storage. `reset_transient_allocator` is the place to wait
// for previous-frame work to retire (note §6).
destroy_transient_allocator :: proc(ctx: ^Context, allocator: Transient_Allocator) {
	if !require_initialized(ctx, "gfx.destroy_transient_allocator") {
		return
	}
	if !require_resource(ctx, &ctx.transient_allocator_pool, u64(allocator), "gfx.destroy_transient_allocator", "transient allocator") {
		return
	}

	state, ok := ctx.transient_allocator_states[allocator]
	if !ok {
		release_resource_id(&ctx.transient_allocator_pool, u64(allocator))
		return
	}

	transient_release_chunks(ctx, &state)
	delete_key(&ctx.transient_allocator_states, allocator)
	release_resource_id(&ctx.transient_allocator_pool, u64(allocator))
}

// reset_transient_allocator returns the bump pointer to zero after the
// previous frame's GPU work has retired.
//
// `frame_done` names a `Timeline_Semaphore` value that must be reached
// before the reset proceeds; the call blocks the calling thread until
// then. Pass `{Timeline_Semaphore_Invalid, 0}` to assert that the caller
// has already waited (e.g. via `timeline_semaphore_wait` for its own
// frame pacing) and skip the wait.
//
// After the reset the persistently mapped pointer remains valid; only
// `Transient_Slice` offsets returned by the previous frame are stale.
// Returns false on validation or backend failure; check `last_error(ctx)`.
//
// Note: The timeline semaphore primitive is itself a sketch (see queue.odin).
// Until APE-3 / APE-17 stand up real submits, callers must pass the no-wait
// sentinel `{Timeline_Semaphore_Invalid, 0}` and serialize frame pacing
// themselves (vsync + immediate-mode `commit` already provides this).
reset_transient_allocator :: proc(ctx: ^Context, allocator: Transient_Allocator, frame_done: Semaphore_Wait) -> bool {
	if !require_initialized(ctx, "gfx.reset_transient_allocator") {
		return false
	}
	if !require_resource(ctx, &ctx.transient_allocator_pool, u64(allocator), "gfx.reset_transient_allocator", "transient allocator") {
		return false
	}

	if frame_done.semaphore != Timeline_Semaphore_Invalid {
		set_unsupported_error(ctx, "gfx.reset_transient_allocator: timeline semaphores are not implemented yet; pass {Timeline_Semaphore_Invalid, 0} and serialize frame pacing on the caller side")
		return false
	}

	state, ok := &ctx.transient_allocator_states[allocator]
	if !ok || !state.valid {
		set_invalid_handle_error(ctx, "gfx.reset_transient_allocator: allocator state is missing")
		return false
	}

	for role in Transient_Usage {
		chunk := &state.chunks[role]
		if !chunk.enabled {
			continue
		}

		mapped, ok := backend_reset_transient_chunk(ctx, chunk.buffer)
		if !ok {
			return false
		}
		chunk.mapped = mapped
		chunk.cursor = 0
	}

	return true
}

// transient_alloc carves a frame-scoped slice out of an allocator's
// backing buffer.
//
// `usage` selects alignment (TRANSIENT_*_ALIGNMENT) and must be a member
// of the allocator's `Transient_Usage_Set`. `size` is in bytes; the
// returned `Transient_Slice.size` is `size` rounded up to the role's
// alignment. Returns `Transient_Slice{}` and `false` on out-of-capacity
// or validation failure.
//
// The call must run on the allocator's owning thread; allocators are
// not internally thread-safe (note §2).
//
// example:
//   slice, ok := gfx.transient_alloc(allocator, size_of(Per_Frame_Uniforms), .Uniform)
//   if ok {
//       (^Per_Frame_Uniforms)(slice.mapped)^ = per_frame
//   }
transient_alloc :: proc(allocator: Transient_Allocator, size: int, usage: Transient_Usage) -> (Transient_Slice, bool) {
	if size <= 0 {
		return {}, false
	}

	state := transient_allocator_state(allocator)
	if state == nil || !state.valid {
		return {}, false
	}
	if usage not_in state.usage {
		return {}, false
	}

	chunk := &state.chunks[usage]
	if !chunk.enabled || chunk.mapped == nil {
		return {}, false
	}

	alignment := transient_alignment(usage)
	aligned_offset := align_up(chunk.cursor, alignment)
	aligned_size := align_up(size, alignment)
	if aligned_offset > chunk.capacity || aligned_size > chunk.capacity - aligned_offset {
		return {}, false
	}

	chunk.cursor = aligned_offset + aligned_size
	return Transient_Slice {
		buffer = chunk.buffer,
		offset = aligned_offset,
		size   = aligned_size,
		mapped = rawptr(uintptr(chunk.mapped) + uintptr(aligned_offset)),
	}, true
}

// transient_allocator_capacity reports the configured byte capacity per role.
//
// Useful for OOM diagnostics from the recorder thread. Returns 0 for an
// invalid handle.
transient_allocator_capacity :: proc(allocator: Transient_Allocator) -> int {
	state := transient_allocator_state(allocator)
	if state == nil || !state.valid {
		return 0
	}
	return state.capacity
}

// transient_allocator_used reports how many bytes have been handed out
// since the last `reset_transient_allocator`, summed across roles.
//
// Includes alignment padding. Returns 0 for an invalid handle.
transient_allocator_used :: proc(allocator: Transient_Allocator) -> int {
	state := transient_allocator_state(allocator)
	if state == nil || !state.valid {
		return 0
	}
	used := 0
	for role in Transient_Usage {
		chunk := &state.chunks[role]
		if chunk.enabled {
			used += chunk.cursor
		}
	}
	return used
}

@(private)
global_transient_contexts: map[u32]^Context

@(private)
transient_register_context :: proc(ctx: ^Context) {
	if ctx == nil || ctx.context_id == 0 {
		return
	}
	if global_transient_contexts == nil {
		global_transient_contexts = make(map[u32]^Context)
	}
	global_transient_contexts[ctx.context_id] = ctx
}

@(private)
transient_unregister_context :: proc(ctx: ^Context) {
	if ctx == nil || ctx.context_id == 0 {
		return
	}
	delete_key(&global_transient_contexts, ctx.context_id)
}

@(private)
transient_allocator_state :: proc(allocator: Transient_Allocator) -> ^Transient_Allocator_State {
	if u64(allocator) == 0 {
		return nil
	}
	context_id := handle_context_id(u64(allocator))
	ctx, ok := global_transient_contexts[context_id]
	if !ok || ctx == nil {
		return nil
	}
	state, found := &ctx.transient_allocator_states[allocator]
	if !found {
		return nil
	}
	return state
}

@(private)
transient_alignment :: proc(usage: Transient_Usage) -> int {
	switch usage {
	case .Uniform:
		return TRANSIENT_UNIFORM_ALIGNMENT
	case .Storage:
		return TRANSIENT_STORAGE_ALIGNMENT
	case .Vertex:
		return TRANSIENT_VERTEX_ALIGNMENT
	case .Index:
		return TRANSIENT_INDEX_ALIGNMENT
	case .Indirect:
		return TRANSIENT_INDIRECT_ALIGNMENT
	}
	return 1
}

@(private)
align_up :: proc(value, alignment: int) -> int {
	return (value + alignment - 1) & ~(alignment - 1)
}

@(private)
transient_release_chunks :: proc(ctx: ^Context, state: ^Transient_Allocator_State) {
	for role in Transient_Usage {
		chunk := &state.chunks[role]
		if !chunk.enabled {
			continue
		}
		backend_destroy_transient_chunk(ctx, chunk.buffer)
		chunk^ = {}
	}
}
