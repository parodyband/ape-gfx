param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\gfx_handle_lifecycle"
$OutPath = Join-Path $TestDir "gfx_handle_lifecycle.exe"
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

expect_error :: proc(ctx: ^gfx.Context, expected: string) {
	actual := gfx.last_error(ctx)
	if actual != expected {
		fmt.eprintln("expected error: ", expected)
		fmt.eprintln("actual error:   ", actual)
		os.exit(1)
	}
}

expect_error_code :: proc(ctx: ^gfx.Context, expected: gfx.Error_Code) {
	actual := gfx.last_error_code(ctx)
	if actual != expected {
		fmt.eprintln("expected error code: ", expected)
		fmt.eprintln("actual error code:   ", actual)
		os.exit(1)
	}
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
	ctx_a, ok_a := gfx.init({backend = .Null, label = "handle lifecycle a"})
	if !ok_a {
		fmt.eprintln("ctx_a init failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx_a)

	ctx_b, ok_b := gfx.init({backend = .Null, label = "handle lifecycle b"})
	if !ok_b {
		fmt.eprintln("ctx_b init failed: ", gfx.last_error(&ctx_b))
		os.exit(1)
	}
	defer gfx.shutdown(&ctx_b)

	direct, direct_ok := gfx.create_buffer(&ctx_a, {
		label = "direct create",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !direct_ok || !gfx.buffer_valid(direct) {
		fmt.eprintln("direct buffer creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}
	gfx.destroy(&ctx_a, direct)

	invalid, invalid_ok := gfx.create_buffer(&ctx_a, {
		label = "invalid direct create",
		usage = {.Vertex},
	})
	if invalid_ok || gfx.buffer_valid(invalid) {
		fail("invalid direct create unexpectedly succeeded")
	}
	expect_error(&ctx_a, "gfx.create_buffer: size must be positive or inferred from initial data")
	expect_error_code(&ctx_a, .Validation)

	first, first_ok := gfx.create_buffer(&ctx_a, {
		label = "first",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !first_ok {
		fmt.eprintln("first buffer creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}

	gfx.destroy(&ctx_a, first)
	gfx.destroy(&ctx_a, first)
	expect_error_info(&ctx_a, .Stale_Handle, "gfx.destroy_buffer: buffer handle is stale or destroyed")

	second, second_ok := gfx.create_buffer(&ctx_a, {
		label = "second",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !second_ok {
		fmt.eprintln("second buffer creation failed: ", gfx.last_error(&ctx_a))
		os.exit(1)
	}
	if second == first {
		fail("reused buffer slot did not advance the generation")
	}

	gfx.destroy(&ctx_b, second)
	expect_error(&ctx_b, "gfx.destroy_buffer: buffer handle belongs to a different context")
	expect_error_code(&ctx_b, .Wrong_Context)

	gfx.destroy(&ctx_a, second)

	ctx_leak, leak_ok := gfx.init({backend = .Null, label = "handle lifecycle leak"})
	if !leak_ok {
		fmt.eprintln("ctx_leak init failed: ", gfx.last_error(&ctx_leak))
		os.exit(1)
	}

	leaked, leaked_ok := gfx.create_buffer(&ctx_leak, {
		label = "leaked",
		usage = {.Vertex, .Dynamic_Update},
		size = 16,
	})
	if !leaked_ok {
		fmt.eprintln("leaked buffer creation failed: ", gfx.last_error(&ctx_leak))
		os.exit(1)
	}

	gfx.shutdown(&ctx_leak)
	expect_error(&ctx_leak, "gfx.shutdown: leaked resources: buffers=1 images=0 views=0 samplers=0 shaders=0 pipelines=0 compute_pipelines=0")
	expect_error_code(&ctx_leak, .Resource_Leak)

	fmt.println("gfx handle lifecycle validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
