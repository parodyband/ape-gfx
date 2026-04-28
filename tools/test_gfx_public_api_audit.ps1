param()

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

& (Join-Path $PSScriptRoot "generate_api_docs.ps1")

$GfxDocPath = Join-Path $Root.Path "docs\api\markdown\gfx.md"
$AuditPath = Join-Path $Root.Path "docs\gfx-public-api-audit.md"

if (-not (Test-Path -LiteralPath $GfxDocPath)) {
	throw "missing generated gfx Markdown API doc: $GfxDocPath"
}
if (-not (Test-Path -LiteralPath $AuditPath)) {
	throw "missing gfx public API audit: $AuditPath"
}

$DocSymbols = @()
foreach ($Line in Get-Content -LiteralPath $GfxDocPath) {
	if ($Line -match '^### `([^`]+)`') {
		$DocSymbols += $Matches[1]
	}
}

$AuditSymbols = @{}
foreach ($Line in Get-Content -LiteralPath $AuditPath) {
	if ($Line -match '^\|\s*`([^`]+)`\s*\|') {
		$AuditSymbols[$Matches[1]] = $true
	}
}

$Missing = @()
foreach ($Symbol in $DocSymbols) {
	if (-not $AuditSymbols.ContainsKey($Symbol)) {
		$Missing += $Symbol
	}
}

$Extra = @()
foreach ($Symbol in $AuditSymbols.Keys) {
	if ($DocSymbols -notcontains $Symbol) {
		$Extra += $Symbol
	}
}

if ($Missing.Count -gt 0) {
	throw "gfx public API audit is missing symbols: $($Missing -join ', ')"
}
if ($Extra.Count -gt 0) {
	throw "gfx public API audit contains symbols not present in generated docs: $($Extra -join ', ')"
}

Write-Host "gfx public API audit validation passed for $($DocSymbols.Count) symbols"
