param()

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

& (Join-Path $PSScriptRoot "generate_api_docs.ps1")

$GfxDocPath = Join-Path $Root.Path "docs\api\raw\gfx_api.txt"
if (-not (Test-Path -LiteralPath $GfxDocPath)) {
	throw "missing generated gfx API doc: $GfxDocPath"
}

$GfxDoc = Get-Content -LiteralPath $GfxDocPath -Raw
$GfxMarkdownPath = Join-Path $Root.Path "docs\api\markdown\gfx.md"
if (-not (Test-Path -LiteralPath $GfxMarkdownPath)) {
	throw "missing generated gfx Markdown API doc: $GfxMarkdownPath"
}

$GfxMarkdown = Get-Content -LiteralPath $GfxMarkdownPath -Raw

$RequiredPublicSymbols = @(
	"init :: proc(desc: Desc)",
	"create_buffer :: proc(ctx: ^Context, desc: Buffer_Desc)",
	"create_image :: proc(ctx: ^Context, desc: Image_Desc)",
	"create_view :: proc(ctx: ^Context, desc: View_Desc)",
	"create_render_target :: proc(ctx: ^Context, desc: Render_Target_Desc)",
	"create_binding_group_layout :: proc(ctx: ^Context, desc: Binding_Group_Layout_Desc)",
	"create_pipeline_layout :: proc(ctx: ^Context, desc: Pipeline_Layout_Desc)",
	"create_binding_group :: proc(ctx: ^Context, desc: Binding_Group_Desc)",
	"begin_pass :: proc(ctx: ^Context, desc: Pass_Desc)",
	"apply_pipeline :: proc(ctx: ^Context, pipeline: Pipeline)",
	"apply_bindings :: proc(ctx: ^Context, bindings: Bindings)",
	"apply_binding_group :: proc(ctx: ^Context, group: Binding_Group",
	"draw :: proc(ctx: ^Context, base_element: i32",
	"begin_compute_pass :: proc(ctx: ^Context",
	"dispatch :: proc(ctx: ^Context",
	"last_error_code :: proc(ctx: ^Context) -> Error_Code",
	"last_error_info :: proc(ctx: ^Context) -> Error_Info",
	"query_backend_limits :: proc(ctx: ^Context) -> Limits",
	"render_target_pass_desc :: proc(target: Render_Target, label: string, action: Pass_Action)",
	"destroy :: proc{destroy_buffer, destroy_image, destroy_view, destroy_sampler, destroy_shader, destroy_pipeline, destroy_compute_pipeline, destroy_binding_group_layout, destroy_pipeline_layout, destroy_binding_group, destroy_render_target}"
)

foreach ($Symbol in $RequiredPublicSymbols) {
	if (-not $GfxDoc.Contains($Symbol)) {
		throw "generated gfx API docs are missing expected public symbol: $Symbol"
	}

	if (-not $GfxMarkdown.Contains($Symbol)) {
		throw "generated gfx Markdown API docs are missing expected public symbol: $Symbol"
	}
}

$ForbiddenInternalPatterns = @(
	"backend_create_",
	"backend_destroy_",
	"backend_query_",
	"d3d11_create_",
	"d3d11_destroy_",
	"d3d11_query_",
	"null_create_",
	"null_destroy_",
	"vulkan_create_",
	"vulkan_destroy_",
	"D3D11_State",
	"D3D11_Buffer",
	"D3D11_Image",
	"D3D11_View",
	"D3D11_Shader",
	"D3D11_Pipeline",
	"Resource_Pool",
	"Resource_Handle_Status",
	"alloc_resource_id",
	"release_resource_id",
	"Swapchain_Invalid ::",
	"Swapchain :: distinct",
	"swapchain: Swapchain",
	"range_slice :: proc",
	"range_fixed_array :: proc"
)

foreach ($Pattern in $ForbiddenInternalPatterns) {
	if ($GfxDoc.Contains($Pattern)) {
		throw "generated gfx API docs expose internal symbol/pattern: $Pattern"
	}

	if ($GfxMarkdown.Contains($Pattern)) {
		throw "generated gfx Markdown API docs expose internal symbol/pattern: $Pattern"
	}
}

Write-Host "API docs public surface validation passed"
