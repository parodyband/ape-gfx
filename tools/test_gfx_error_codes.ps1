param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$GfxSources = Get-ChildItem -LiteralPath (Join-Path $Root.Path "gfx") -Filter "*.odin"
$GfxSourceText = ($GfxSources | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

if ($GfxSourceText -match "\binfer_error_code\b") {
	throw "gfx error codes must not be inferred from message strings"
}
if ($GfxSourceText -match "\bstring_contains\b" -or $GfxSourceText -match "\bstring_has_prefix\b") {
	throw "gfx error-code validation found old string-scanning helpers"
}
if ($GfxSourceText -match "\bset_error\s*::" -or $GfxSourceText -match "\bset_errorf\s*::") {
	throw "gfx generic set_error helpers must stay removed; use typed helpers"
}
if ($GfxSourceText -match "\bset_error\s*\(" -or $GfxSourceText -match "\bset_errorf\s*\(") {
	throw "gfx failure sites must use typed error helpers, not generic set_error"
}

$TestDir = Join-Path $Root.Path "build\validation_tests\gfx_error_codes"
$OutPath = Join-Path $TestDir "gfx_error_codes.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import gfx "ape:gfx"

fail :: proc(message: string) {
	fmt.eprintln(message)
	os.exit(1)
}

expect_error_info :: proc(ctx: ^gfx.Context, expected_code: gfx.Error_Code, expected_message: string) {
	info := gfx.last_error_info(ctx)
	if info.code != expected_code || info.message != expected_message {
		fmt.eprintln("expected error code: ", expected_code)
		fmt.eprintln("actual error code:   ", info.code)
		fmt.eprintln("expected message:    ", expected_message)
		fmt.eprintln("actual message:      ", info.message)
		os.exit(1)
	}
}

main :: proc() {
	ctx, ok := gfx.init({backend = .Null, label = "error code validation"})
	if !ok {
		fmt.eprintln("gfx init failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx)

	if gfx.last_error_code(&ctx) != .None {
		fail("fresh context should start with Error_Code.None")
	}

	invalid_buffer, invalid_buffer_ok := gfx.create_buffer(&ctx, {
		label = "missing size",
		usage = {.Vertex},
	})
	if invalid_buffer_ok || gfx.buffer_valid(invalid_buffer) {
		fail("invalid buffer unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Validation, "gfx.create_buffer: size must be positive or inferred from initial data")

	if gfx.begin_compute_pass(&ctx, {}) {
		fail("null backend compute pass unexpectedly succeeded")
	}
	expect_error_info(&ctx, .Unsupported, "gfx.begin_compute_pass: backend does not support compute")

	gfx.destroy_buffer(&ctx, gfx.Buffer_Invalid)
	expect_error_info(&ctx, .Invalid_Handle, "gfx.destroy_buffer: buffer handle is invalid")

	stale_buffer, stale_buffer_ok := gfx.create_buffer(&ctx, {
		label = "stale handle",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !stale_buffer_ok || !gfx.buffer_valid(stale_buffer) {
		fmt.eprintln("stale buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	gfx.destroy(&ctx, stale_buffer)
	gfx.destroy(&ctx, stale_buffer)
	expect_error_info(&ctx, .Stale_Handle, "gfx.destroy_buffer: buffer handle is stale or destroyed")

	ctx_other, other_ok := gfx.init({backend = .Null, label = "wrong context error code"})
	if !other_ok {
		fmt.eprintln("ctx_other init failed: ", gfx.last_error(&ctx_other))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx_other)

	wrong_context_buffer, wrong_context_ok := gfx.create_buffer(&ctx, {
		label = "wrong context",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !wrong_context_ok || !gfx.buffer_valid(wrong_context_buffer) {
		fmt.eprintln("wrong-context buffer creation failed: ", gfx.last_error(&ctx))
		os.exit(1)
	}
	gfx.destroy(&ctx_other, wrong_context_buffer)
	expect_error_info(&ctx_other, .Wrong_Context, "gfx.destroy_buffer: buffer handle belongs to a different context")
	gfx.destroy(&ctx, wrong_context_buffer)

	ctx_leak, leak_ok := gfx.init({backend = .Null, label = "leak error code"})
	if !leak_ok {
		fmt.eprintln("ctx_leak init failed: ", gfx.last_error(&ctx_leak))
		os.exit(1)
	}

	leaked, leaked_ok := gfx.create_buffer(&ctx_leak, {
		label = "leaked",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !leaked_ok || !gfx.buffer_valid(leaked) {
		fmt.eprintln("leaked buffer creation failed: ", gfx.last_error(&ctx_leak))
		os.exit(1)
	}

	gfx.shutdown(&ctx_leak)
	expect_error_info(&ctx_leak, .Resource_Leak, "gfx.shutdown: leaked resources: buffers=1 images=0 views=0 samplers=0 shaders=0 pipelines=0 compute_pipelines=0")

	fmt.println("gfx error code validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
