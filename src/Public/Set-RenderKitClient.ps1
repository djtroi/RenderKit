Register-RenderKitFunction 'Set-RenderKitClient'
function Set-RenderKitClient {
    <#
.SYNOPSIS
Updates an existing RenderKit client with optimistic concurrency.

.DESCRIPTION
Applies only explicitly supplied fields. ExpectedRevision must match the
persisted revision so another host cannot be overwritten silently. Set Status
to Archived for reversible removal.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ExpectedRevision,
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,
        [AllowEmptyString()]
        [string]$LegalName,
        [ValidateSet('Active', 'Inactive', 'Archived')]
        [string]$Status,
        [string[]]$Tag,
        [AllowEmptyString()]
        [string]$Notes,
        [object[]]$Contact,
        [object[]]$Address,
        [AllowNull()]
        [object]$Consent,
        [AllowNull()]
        [object]$Retention
    )

    $mapping = @{
        DisplayName = 'DisplayName'
        LegalName = 'LegalName'
        Status = 'Status'
        Tag = 'Tags'
        Notes = 'Notes'
        Contact = 'Contacts'
        Address = 'Addresses'
        Consent = 'Consent'
        Retention = 'Retention'
    }
    $changes = @{}
    foreach ($parameterName in $mapping.Keys) {
        if ($PSBoundParameters.ContainsKey($parameterName)) {
            $changes[$mapping[$parameterName]] =
                $PSBoundParameters[$parameterName]
        }
    }
    if ($changes.Count -eq 0) {
        throw [System.ArgumentException]::new(
            'At least one client field must be supplied.')
    }

    if (-not $PSCmdlet.ShouldProcess($Id, 'Update RenderKit client')) {
        return
    }
    return Update-RenderKitClientRecord `
        -Id $Id `
        -ExpectedRevision $ExpectedRevision `
        -Changes $changes
}
