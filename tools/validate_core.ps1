param(
	[switch]$SkipShaderCompile,
	[switch]$SkipGitDiffCheck
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native.ps1")

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Invoke-ValidationStep {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[scriptblock]$Action
	)

	Write-Host ""
	Write-Host "==> $Name"
	$Start = Get-Date

	try {
		& $Action
		$Elapsed = (Get-Date) - $Start
		Write-Host ("OK  {0} ({1:n1}s)" -f $Name, $Elapsed.TotalSeconds)
	}
	catch {
		Write-Host ""
		Write-Host ("FAILED  {0}" -f $Name) -ForegroundColor Red
		throw
	}
}

function Invoke-RepoScript {
	param(
		[Parameter(Mandatory = $true)]
		[string]$ScriptName,

		[object[]]$Arguments = @()
	)

	$ScriptPath = Join-Path $PSScriptRoot $ScriptName
	$PowerShellArguments = @("-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments
	Invoke-Native -Command "powershell" -Arguments $PowerShellArguments
}

function Invoke-GitDiffCheck {
	Push-Location $Root.Path
	try {
		Invoke-Native -Command "git" -Arguments @("diff", "--check")
	}
	finally {
		Pop-Location
	}
}

$CoreValidationScripts = @(
	"build_smoke.ps1",
	"test_api_docs_public_surface.ps1",
	"test_gfx_public_api_audit.ps1",
	"test_gfx_error_codes.ps1",
	"test_gfx_descriptor_contracts.ps1",
	"test_gfx_image_transfer_contracts.ps1",
	"test_gfx_state_descriptor_contracts.ps1",
	"test_gfx_range_helpers.ps1",
	"test_gfx_handle_lifecycle.ps1",
	"test_shaderc_modern_api_probe.ps1",
	"test_shaderc_register_free_samples.ps1",
	"test_shaderc_descriptor_table_slots.ps1",
	"test_shaderc_parameter_block_groups.ps1",
	"test_shaderc_resource_arrays.ps1",
	"test_shaderc_invalid_vertex_layout.ps1",
	"test_shaderc_storage_resource_metadata.ps1",
	"test_shader_hot_reload.ps1"
)

$StartedAt = Get-Date
Write-Host "Ape GFX core validation"
Write-Host "Root: $($Root.Path)"
Write-Host "D3D11 runtime tests: skipped"

if (-not $SkipShaderCompile) {
	Invoke-ValidationStep "compile sample shaders" {
		Invoke-RepoScript "compile_shaders.ps1" -Arguments @("-All")
	}
}

foreach ($ScriptName in $CoreValidationScripts) {
	Invoke-ValidationStep $ScriptName {
		Invoke-RepoScript $ScriptName
	}
}

if (-not $SkipGitDiffCheck) {
	Invoke-ValidationStep "git diff --check" {
		Invoke-GitDiffCheck
	}
}

$TotalElapsed = (Get-Date) - $StartedAt
Write-Host ""
Write-Host ("Ape GFX core validation passed ({0:n1}s)" -f $TotalElapsed.TotalSeconds)
