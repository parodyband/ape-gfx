param(
	[int]$AutoExitFrames = 5,
	[switch]$SkipShaderCompile,
	[switch]$SkipD3D11Builds,
	[switch]$SkipD3D11Runs,
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

$PublicValidationScripts = @(
	"build_smoke.ps1",
	"test_api_docs_public_surface.ps1",
	"test_gfx_public_api_audit.ps1",
	"test_gfx_error_codes.ps1",
	"test_gfx_descriptor_contracts.ps1",
	"test_gfx_image_transfer_contracts.ps1",
	"test_gfx_state_descriptor_contracts.ps1",
	"test_gfx_range_helpers.ps1",
	"test_gfx_handle_lifecycle.ps1",
	"test_d3d11_backend_limits.ps1",
	"test_d3d11_error_codes.ps1",
	"test_d3d11_buffer_transfers.ps1",
	"test_d3d11_compute_pass.ps1",
	"test_d3d11_invalid_pipeline_layout.ps1",
	"test_d3d11_invalid_uniform_size.ps1",
	"test_d3d11_invalid_view_kind.ps1",
	"test_d3d11_resource_hazards.ps1",
	"test_d3d11_storage_views.ps1",
	"test_shaderc_modern_api_probe.ps1",
	"test_shaderc_register_free_samples.ps1",
	"test_shaderc_descriptor_table_slots.ps1",
	"test_shaderc_parameter_block_groups.ps1",
	"test_shaderc_invalid_vertex_layout.ps1",
	"test_shaderc_storage_resource_metadata.ps1",
	"test_shader_hot_reload.ps1"
)

$D3D11BuildScripts = @(
	"build_d3d11_clear.ps1",
	"build_d3d11_cube.ps1",
	"build_d3d11_depth_render_to_texture.ps1",
	"build_d3d11_dynamic_texture.ps1",
	"build_d3d11_gfx_lab.ps1",
	"build_d3d11_improved_shadows.ps1",
	"build_d3d11_mrt.ps1",
	"build_d3d11_msaa.ps1",
	"build_d3d11_render_to_texture.ps1",
	"build_d3d11_textured_cube.ps1",
	"build_d3d11_textured_quad.ps1",
	"build_d3d11_triangle.ps1",
	"build_d3d11_triangle_minimal.ps1"
)

$D3D11RunScripts = @(
	"run_d3d11_clear.ps1",
	"run_d3d11_cube.ps1",
	"run_d3d11_depth_render_to_texture.ps1",
	"run_d3d11_dynamic_texture.ps1",
	"run_d3d11_gfx_lab.ps1",
	"run_d3d11_improved_shadows.ps1",
	"run_d3d11_mrt.ps1",
	"run_d3d11_msaa.ps1",
	"run_d3d11_render_to_texture.ps1",
	"run_d3d11_textured_cube.ps1",
	"run_d3d11_textured_quad.ps1",
	"run_d3d11_triangle.ps1",
	"run_d3d11_triangle_minimal.ps1"
)

$StartedAt = Get-Date
Write-Host "Ape GFX full validation"
Write-Host "Root: $($Root.Path)"
Write-Host "AutoExitFrames: $AutoExitFrames"

if (-not $SkipShaderCompile) {
	Invoke-ValidationStep "compile sample shaders" {
		Invoke-RepoScript "compile_shaders.ps1" -Arguments @("-All")
	}
}

foreach ($ScriptName in $PublicValidationScripts) {
	Invoke-ValidationStep $ScriptName {
		Invoke-RepoScript $ScriptName
	}
}

if (-not $SkipD3D11Builds) {
	foreach ($ScriptName in $D3D11BuildScripts) {
		Invoke-ValidationStep $ScriptName {
			Invoke-RepoScript $ScriptName
		}
	}
}

if (-not $SkipD3D11Runs) {
	foreach ($ScriptName in $D3D11RunScripts) {
		Invoke-ValidationStep "$ScriptName -AutoExitFrames $AutoExitFrames" {
			Invoke-RepoScript $ScriptName -Arguments @("-AutoExitFrames", $AutoExitFrames)
		}
	}
}

if (-not $SkipGitDiffCheck) {
	Invoke-ValidationStep "git diff --check" {
		Invoke-GitDiffCheck
	}
}

$ElapsedTotal = (Get-Date) - $StartedAt
Write-Host ""
Write-Host ("Ape GFX full validation passed ({0:n1}s)" -f $ElapsedTotal.TotalSeconds)
