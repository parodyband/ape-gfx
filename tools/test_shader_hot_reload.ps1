$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TestDir = Join-Path $Root.Path "build\shader_hot_reload_test"
$OutPath = Join-Path $TestDir "shader_hot_reload_test.exe"
$SourcePath = Join-Path $TestDir "reload_test.slang"
$PackagePath = Join-Path $TestDir "reload_test.ashader"
$CompilerPath = Join-Path $TestDir "fake_compile_shader.ps1"
$MainPath = Join-Path $TestDir "main.odin"

New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

Set-Content -LiteralPath $SourcePath -Value "initial shader source"
Set-Content -LiteralPath $PackagePath -Value "initial shader package"

$escapedPackagePath = $PackagePath.Replace("'", "''")
@"
param([string]`$ShaderName)
Set-Content -LiteralPath '$escapedPackagePath' -Value "compiled `$ShaderName"
"@ | Set-Content -LiteralPath $CompilerPath

$main = @'
package main

import "core:fmt"
import "core:os"
import os2 "core:os/os2"
import "core:time"
import ape_sample "ape:samples/ape_sample"

main :: proc() {
	source_path := `__SOURCE_PATH__`
	package_path := `__PACKAGE_PATH__`
	compiler_path := `__COMPILER_PATH__`
	working_dir := `__WORKING_DIR__`

	reloader: ape_sample.Shader_Reloader
	if !ape_sample.shader_reload_init(&reloader, {
		shader_name = "reload_test",
		source_path = source_path,
		package_path = package_path,
		compile_script_path = compiler_path,
		working_dir = working_dir,
		debounce = 1 * time.Millisecond,
	}) {
		fmt.eprintln(ape_sample.shader_reload_last_error(&reloader))
		os2.exit(1)
	}

	time.sleep(20 * time.Millisecond)
	changed := [?]u8{'c', 'h', 'a', 'n', 'g', 'e', 'd'}
	if !os.write_entire_file(source_path, changed[:]) {
		fmt.eprintln("failed to update temporary shader source")
		os2.exit(1)
	}

	result := ape_sample.shader_reload_poll(&reloader)
	if result.status != .Pending {
		fmt.eprintln("expected pending reload after source change")
		os2.exit(1)
	}

	time.sleep(20 * time.Millisecond)
	result = ape_sample.shader_reload_poll(&reloader)
	if result.status != .Recompiled {
		fmt.eprintln("expected shader reload to recompile, got ", result.status)
		fmt.eprintln(ape_sample.shader_reload_last_error(&reloader))
		os2.exit(1)
	}

	bytes, ok := os.read_entire_file(package_path)
	if !ok {
		fmt.eprintln("failed to read temporary shader package")
		os2.exit(1)
	}
	defer delete(bytes)

	if len(bytes) == 0 {
		fmt.eprintln("temporary shader package was not written")
		os2.exit(1)
	}
}
'@

$main = $main.Replace("__SOURCE_PATH__", $SourcePath)
$main = $main.Replace("__PACKAGE_PATH__", $PackagePath)
$main = $main.Replace("__COMPILER_PATH__", $CompilerPath)
$main = $main.Replace("__WORKING_DIR__", $Root.Path)
Set-Content -LiteralPath $MainPath -Value $main

Invoke-Native -Command "odin" -Arguments @(
	"run",
	$TestDir,
	"-collection:ape=$($Root.Path)",
	"-out:$OutPath"
)

Write-Host "Shader hot reload test passed"
