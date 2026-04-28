function Invoke-Native {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Command,

		[object[]]$Arguments = @()
	)

	& $Command @Arguments
	if ($LASTEXITCODE -ne 0) {
		throw "$Command failed with exit code $LASTEXITCODE"
	}
}
