package gfx

// Queue / Timeline submission API draft — AAA roadmap item 21.
//
// These types define the future explicit-submission model used by transient
// allocators and bindless slot lifetime rules. Entry points report Unsupported
// until command recording and backend queues exist.
//
//   gfx-command-recording-note.md  — Command_List + per-pass encoders are
//                                    the unit of recorded work; `Context` is
//                                    one-thread-only.
//   gfx-barriers-note.md §9.3      — cross-queue handoff is explicit; queue
//                                    ownership transfer is paired verbs on
//                                    source and destination lists.
//   gfx-barriers-note.md §9.4      — present-after-render rides the §9.1
//                                    attachment auto-transition path; this
//                                    file owns the *submit/present* surface,
//                                    not the per-frame attachment moves.
//
// The names here intentionally do not collide with the existing immediate-mode
// `gfx.commit`. The existing `commit(ctx)` stays as the shipping convenience
// wrapper until APE-22 (roadmap item 22) decides whether it survives on top
// of the explicit graphics submission path defined here.
//
// Backend story:
//
//   D3D11   — one logical Graphics queue, no real timelines. `acquire_*_queue`
//             returns the same Queue for Graphics and a sentinel for Compute /
//             Transfer; explicit multi-queue submits return Unsupported until
//             queue runtime exists; Timeline_Semaphore maps to a CPU-side u64
//             plus a single ID3D11Query for fence emulation; Present rides
//             IDXGISwapChain::Present.
//   D3D12   — one ID3D12CommandQueue per kind; Timeline_Semaphore maps 1:1
//             onto ID3D12Fence; Present rides IDXGISwapChain::Present and the
//             frame fence is signaled on the graphics queue.
//   Vulkan  — one VkQueue per kind (chosen from queue families at init);
//             Timeline_Semaphore maps onto VK_KHR_timeline_semaphore;
//             Present rides vkQueuePresentKHR with a binary acquire/present
//             semaphore pair living inside the swapchain wrapper.

// Queue is the opaque handle for a GPU work submission target.
//
// `Context` exposes one Queue per Queue_Kind it supports (see
// `acquire_graphics_queue` / `acquire_compute_queue` / `acquire_transfer_queue`).
// Multiple queues of the same kind are not on the public roadmap; if a backend
// presents several (e.g. Vulkan transfer-only families), it picks one and hides
// the rest.
Queue :: distinct u64
Queue_Invalid :: Queue(0)

// Queue_Kind classifies what work a Queue accepts.
//
// Mirrors `Command_Queue` from command_list.odin and is used at queue
// acquisition time. The two enums are kept distinct so `Command_List`'s
// recorded affinity (which family it was *built for*) is not conflated with
// the runtime Queue handle (which family it is *submitted to*).
Queue_Kind :: enum {
	Graphics,
	Compute,
	Transfer,
}

// Timeline_Semaphore is a monotonically increasing u64 visible to GPU and CPU.
//
// Modelled after Vulkan's VK_KHR_timeline_semaphore and D3D12's ID3D12Fence:
// any submit may *wait* until the semaphore reaches a value, and any submit
// *signals* a (typically larger) value when its work completes. CPU code may
// read or block on a value via `timeline_semaphore_value` and
// `timeline_semaphore_wait`.
//
// Binary semaphores (the swapchain acquire/present pair) are not exposed
// publicly. They live inside the swapchain wrapper and are managed by
// `present`; see §6 of the queue-submission note.
Timeline_Semaphore :: distinct u64
Timeline_Semaphore_Invalid :: Timeline_Semaphore(0)

// Semaphore_Wait names a wait-before-execute edge for a submission.
//
// `value` is the timeline value the semaphore must reach before the submitted
// command lists may begin executing. Multiple waits on the same submit are
// AND-ed: every named value must be reached.
Semaphore_Wait :: struct {
	semaphore: Timeline_Semaphore,
	value:     u64,
}

// Semaphore_Signal names a signal-after-execute edge for a submission.
//
// `value` must be strictly greater than the semaphore's current value. The
// signal happens after every command list in the submit completes.
Semaphore_Signal :: struct {
	semaphore: Timeline_Semaphore,
	value:     u64,
}

// Submit_Info is the description for a single `submit` call.
//
// `command_lists` are submitted in array order on `queue`. Every list must be
// in state `Finished` (see command_list.odin) and built for a Queue_Kind that
// matches the target queue. Empty `command_lists` is allowed when the submit
// only signals — useful for CPU-driven timeline progress.
//
// Per-list error slots are drained onto `Context.last_error` during `submit`
// (see command-recording-note §7.3); a non-empty slot does not by itself
// fail the submit.
Submit_Info :: struct {
	command_lists: []^Command_List,
	waits:         []Semaphore_Wait,
	signals:       []Semaphore_Signal,
}

// Present_Info is the description for a single `present` call.
//
// `waits` is the set of timeline values that must be reached before the
// swapchain image is handed to the display engine. The typical caller puts
// the per-frame "render done" signal here; `present` already waits internally
// on the swapchain's acquire-binary semaphore.
//
// Per barrier-note §9.4 the swapchain image's `Color_Target -> Present`
// transition is emitted inside the render pass that targets it; `present`
// itself does not transition resources.
Present_Info :: struct {
	waits: []Semaphore_Wait,
}

// acquire_graphics_queue returns the Queue handle for the graphics family.
//
// Stable for the life of the Context. Returns `Queue_Invalid` if the backend
// does not expose a graphics queue (shouldn't happen for a valid Context).
acquire_graphics_queue :: proc(ctx: ^Context) -> Queue {
	set_unsupported_error(ctx, "gfx.acquire_graphics_queue: explicit queues are not implemented yet")
	return Queue_Invalid
}

// acquire_compute_queue returns the Queue handle for the async-compute family.
//
// On D3D11 this returns the same Queue as `acquire_graphics_queue` and the
// runtime serializes; on D3D12/Vulkan this is a distinct queue when the
// adapter exposes one.
acquire_compute_queue :: proc(ctx: ^Context) -> Queue {
	set_unsupported_error(ctx, "gfx.acquire_compute_queue: explicit queues are not implemented yet")
	return Queue_Invalid
}

// acquire_transfer_queue returns the Queue handle for the copy-only family.
//
// Same fold-to-graphics rule as `acquire_compute_queue` on D3D11.
acquire_transfer_queue :: proc(ctx: ^Context) -> Queue {
	set_unsupported_error(ctx, "gfx.acquire_transfer_queue: explicit queues are not implemented yet")
	return Queue_Invalid
}

// queue_kind reports the family a Queue belongs to.
//
// TODO(queue runtime): store the queue kind in backend/context state and read
// it from the Queue handle. The current placeholder returns Graphics until
// explicit queues are implemented.
queue_kind :: proc(queue: Queue) -> Queue_Kind {
	return .Graphics
}

// create_timeline_semaphore allocates a Timeline_Semaphore with `initial_value`.
//
// Returns `Timeline_Semaphore_Invalid` on failure; check `last_error(ctx)`.
create_timeline_semaphore :: proc(ctx: ^Context, initial_value: u64 = 0) -> Timeline_Semaphore {
	set_unsupported_error(ctx, "gfx.create_timeline_semaphore: timeline semaphores are not implemented yet")
	return Timeline_Semaphore_Invalid
}

// destroy_timeline_semaphore releases a Timeline_Semaphore.
//
// All in-flight submits that wait on or signal the semaphore must have
// completed (or be cancelled by Context shutdown) before destruction.
destroy_timeline_semaphore :: proc(ctx: ^Context, semaphore: Timeline_Semaphore) {
	set_unsupported_error(ctx, "gfx.destroy_timeline_semaphore: timeline semaphores are not implemented yet")
}

// timeline_semaphore_value reads the current GPU-visible value.
timeline_semaphore_value :: proc(ctx: ^Context, semaphore: Timeline_Semaphore) -> u64 {
	set_unsupported_error(ctx, "gfx.timeline_semaphore_value: timeline semaphores are not implemented yet")
	return 0
}

// timeline_semaphore_signal advances the semaphore from the CPU side.
//
// `value` must be strictly greater than the current value.
timeline_semaphore_signal :: proc(ctx: ^Context, semaphore: Timeline_Semaphore, value: u64) -> bool {
	set_unsupported_error(ctx, "gfx.timeline_semaphore_signal: timeline semaphores are not implemented yet")
	return false
}

// timeline_semaphore_wait blocks the calling thread until `value` is reached.
//
// `timeout_ns` of 0 polls; ~max u64 is "wait forever". Returns false on
// timeout or backend error; check `last_error(ctx)` to disambiguate.
timeline_semaphore_wait :: proc(ctx: ^Context, semaphore: Timeline_Semaphore, value: u64, timeout_ns: u64) -> bool {
	set_unsupported_error(ctx, "gfx.timeline_semaphore_wait: timeline semaphores are not implemented yet")
	return false
}

// submit hands an ordered batch of finished command lists to a Queue.
//
// Must be called on the Context thread. Drains per-list error slots onto
// `ctx` (recording-note §7.3) and transitions each list to `Submitted`.
// Returns false on validation/backend failure; check `last_error(ctx)`.
//
// Validation rules (sketch — refined as items 18-20 land):
//
//   - every list is in state `Finished`
//   - every list's recorded `queue` matches `queue_kind(queue)`
//   - every signal value is strictly greater than its semaphore's current
//     pending-max (no out-of-order signals on one semaphore)
//   - lists already submitted are rejected (`.Stale_Handle`-equivalent)
//
// The single-queue / single-list shape is `submit(queue, { command_lists = {&list} })`.
submit :: proc(ctx: ^Context, queue: Queue, info: Submit_Info) -> bool {
	set_unsupported_error(ctx, "gfx.submit: explicit queues are not implemented yet")
	return false
}

// present queues the current swapchain image for display.
//
// Always targets the graphics queue acquired from `ctx`; there is no
// `Queue` parameter because cross-queue present is not on the roadmap.
// Advances `ctx.frame_index` after the swapchain returns. The
// acquire-next-image binary semaphore for the *following* frame is
// scheduled internally.
//
// Per barrier-note §9.4 the `Color_Target -> Present` transition has already
// been emitted by the render pass that wrote the swapchain image; `present`
// only consumes the timeline waits in `info` and forwards to the swapchain.
present :: proc(ctx: ^Context, info: Present_Info = {}) -> bool {
	set_unsupported_error(ctx, "gfx.present: explicit presentation is not implemented yet; use gfx.commit for the immediate-mode path")
	return false
}
