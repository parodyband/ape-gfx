package gfx

// gpu_timing_supported reports whether the backend records GPU pass timestamps.
// Unsupported backends simply return false; this is an optional diagnostics path.
gpu_timing_supported :: proc(ctx: ^Context) -> bool {
	if ctx == nil || !ctx.initialized {
		return false
	}
	return backend_gpu_timing_supported(ctx)
}

// copy_gpu_timing_samples copies the most recently committed frame's GPU pass
// timings into out and returns the number written.
copy_gpu_timing_samples :: proc(ctx: ^Context, out: []Gpu_Timing_Sample) -> int {
	if ctx == nil || !ctx.initialized || len(out) == 0 {
		return 0
	}
	return backend_copy_gpu_timing_samples(ctx, out)
}
