param(
	[string]$OutDir = "docs\api\raw",
	[string]$MarkdownDir = "docs\api\markdown"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ToolDir = Join-Path $Root.Path "build\tools"

New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null

$ApePath = Join-Path $ToolDir "ape-docs-generate-$PID.exe"

try {
	Invoke-Native -Command "odin" -Arguments @("build", (Join-Path $Root.Path "tools\ape"), "-out:$ApePath")
	Invoke-Native -Command $ApePath -Arguments @(
		"docs", "generate",
		"-root", $Root.Path,
		"-out-dir", $OutDir,
		"-markdown-dir", $MarkdownDir
	)
}
finally {
	Remove-Item -LiteralPath $ApePath -ErrorAction SilentlyContinue
}
