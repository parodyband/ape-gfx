param()

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ShaderDir = Join-Path $Root.Path "assets\shaders"

$Matches = Get-ChildItem -LiteralPath $ShaderDir -Filter "*.slang" -File |
	Select-String -Pattern "register\s*\("

if ($Matches) {
	Write-Host "Sample Slang shaders should not use routine manual register annotations:"
	foreach ($Match in $Matches) {
		Write-Host ("{0}:{1}: {2}" -f $Match.Path, $Match.LineNumber, $Match.Line.Trim())
	}
	throw "register-free sample shader check failed"
}

Write-Host "Sample Slang shaders are register-free"
