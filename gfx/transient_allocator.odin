package gfx

// Transient uniform / storage allocation API sketch — AAA roadmap item 23.
//
// This file is a header-only stub. Every entry point panics. The shapes
// here reflect the decisions in
// docs/private/gfx-transient-allocator-note.md, which composes with:
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
// The names here intentionally do not collide with the immediate-mode
// `apply_uniforms` path. Bodies land with item 24 (D3D11-backed
// allocator) and item 25 (`apply_uniform_at`). Multi-thread recorder
// support lands with APE-3.

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
// `capacity == 0` means "pick a backend default" and is implementation-
// defined; the implementation lands with APE-24. `usage` must contain at
// least one role (note §2). `Transient_Usage.Indirect` composes only
// with `.Storage` for compute-driven indirect or alone for CPU-prepared
// indirect; see note §5.
Transient_Allocator_Desc :: struct {
	label:    string,
	capacity: int,
	usage:    Transient_Usage_Set,
}

// Transient_Slice is one allocation out of a `Transient_Allocator`.
//
// `buffer` is the allocator's shared per-frame backing buffer; the slice
// lives at `[offset, offset + size)`. `mapped` is a CPU pointer into the
// persistently mapped backing buffer — write through it directly or cast
// to a typed pointer. Validity ends at the next
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
//       usage    = { .Uniform, .Storage },
//   })
create_transient_allocator :: proc(ctx: ^Context, desc: Transient_Allocator_Desc) -> (Transient_Allocator, bool) {
	panic("gfx.create_transient_allocator: unimplemented (APE-19 sketch only)")
}

// destroy_transient_allocator releases backing storage held by an allocator.
//
// All in-flight submits that read from the allocator's backing buffer
// must have completed before destruction; the allocator does not block
// on its own storage. `reset_transient_allocator` is the place to wait
// for previous-frame work to retire (note §6).
destroy_transient_allocator :: proc(ctx: ^Context, allocator: Transient_Allocator) {
	panic("gfx.destroy_transient_allocator: unimplemented (APE-19 sketch only)")
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
reset_transient_allocator :: proc(ctx: ^Context, allocator: Transient_Allocator, frame_done: Semaphore_Wait) -> bool {
	panic("gfx.reset_transient_allocator: unimplemented (APE-19 sketch only)")
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
	panic("gfx.transient_alloc: unimplemented (APE-19 sketch only)")
}

// transient_allocator_capacity reports the configured byte capacity.
//
// Useful for OOM diagnostics from the recorder thread. Returns 0 for an
// invalid handle.
transient_allocator_capacity :: proc(allocator: Transient_Allocator) -> int {
	panic("gfx.transient_allocator_capacity: unimplemented (APE-19 sketch only)")
}

// transient_allocator_used reports how many bytes have been handed out
// since the last `reset_transient_allocator`.
//
// Includes alignment padding. Returns 0 for an invalid handle.
transient_allocator_used :: proc(allocator: Transient_Allocator) -> int {
	panic("gfx.transient_allocator_used: unimplemented (APE-19 sketch only)")
}
