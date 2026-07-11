Register-RenderKitFunction 'New-RenderKitClient'
function New-RenderKitClient {
    <#
.SYNOPSIS
Creates a client in the global RenderKit client registry.

.DESCRIPTION
Validates and atomically persists a new client record. The generated client ID
is stable and can be used by the canonical ClientId metadata field.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,
        [AllowEmptyString()]
        [string]$LegalName,
        [ValidateSet('Active', 'Inactive', 'Archived')]
        [string]$Status = 'Active',
        [string[]]$Tag = @(),
        [AllowEmptyString()]
        [string]$Notes,
        [object[]]$Contact = @(),
        [object[]]$Address = @(),
        [object]$Consent,
        [object]$Retention
    )

    $client = New-RenderKitClientRecord `
        -DisplayName $DisplayName `
        -LegalName $LegalName `
        -Status $Status `
        -Tags $Tag `
        -Notes $Notes `
        -Contacts $Contact `
        -Addresses $Address `
        -Consent $Consent `
        -Retention $Retention

    if (-not $PSCmdlet.ShouldProcess(
        [string]$client.displayName,
        'Create RenderKit client'
    )) {
        return
    }
    return Add-RenderKitClientRecord -Client $client
}
