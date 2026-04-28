param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\validation_tests\gfx_range_helpers"
$OutPath = Join-Path $TestDir "gfx_range_helpers.exe"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $MainPath -Value @'
package main

import "core:fmt"
import "core:os"
import gfx "ape:engine/gfx"

fail :: proc(message: string) {
	fmt.eprintln(message)
	os.exit(1)
}

main :: proc() {
	slice_values := [?]u32{1, 2, 3, 4}
	slice_range := gfx.range(slice_values[:])
	if slice_range.ptr == nil || slice_range.size != size_of(type_of(slice_values)) {
		fail("gfx.range(slice) produced an unexpected range")
	}

	empty_slice := slice_values[0:0]
	empty_range := gfx.range(empty_slice)
	if empty_range.ptr != nil || empty_range.size != 0 {
		fail("gfx.range(empty slice) should produce an empty range")
	}

	fixed_values := [?]u16{1, 2, 3}
	fixed_range := gfx.range(&fixed_values)
	if fixed_range.ptr == nil || fixed_range.size != size_of(type_of(fixed_values)) {
		fail("gfx.range(fixed array pointer) produced an unexpected range")
	}

	raw_value := u32(42)
	raw_range := gfx.range_raw(rawptr(&raw_value), size_of(u32))
	if raw_range.ptr == nil || raw_range.size != size_of(u32) {
		fail("gfx.range_raw produced an unexpected range")
	}

	fmt.println("gfx range helper validation passed")
}
'@

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)
