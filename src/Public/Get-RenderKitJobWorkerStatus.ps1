function Get-RenderKitJobWorkerStatus {
    [CmdletBinding()]
    param(
        [string]$WorkerId,
        [switch]$IncludeLogs,
        [ValidateRange(1, 1000)]
        [int]$Tail = 50
    )

    $states = if (-not [string]::IsNullOrWhiteSpace($WorkerId)) {
        $state = Read-RenderKitWorkerState -WorkerId $WorkerId
        if (-not $state) {
            throw "RenderKit worker '$WorkerId' was not found."
        }
        @($state)
    }
    else {
        @(Get-RenderKitWorkerStateList)
    }

    return @($states | ForEach-Object {
            Get-RenderKitWorkerStatusSnapshot `
                -State $_ `
                -IncludeLogs:$IncludeLogs `
                -Tail $Tail
        })
}

Register-RenderKitFunction -Name 'Get-RenderKitJobWorkerStatus'
