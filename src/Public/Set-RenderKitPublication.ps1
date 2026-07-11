Register-RenderKitFunction 'Set-RenderKitPublication'
function Set-RenderKitPublication {
    <#
.SYNOPSIS
Updates a publication planning record with optimistic concurrency.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ExpectedRevision,
        [string]$Title,
        [AllowEmptyString()][string]$Description,
        [ValidateSet(
            'Draft',
            'Scheduled',
            'Publishing',
            'Published',
            'Failed',
            'Cancelled'
        )]
        [string]$Status,
        [string]$StartUtc,
        [AllowEmptyString()][string]$EndUtc,
        [string]$TimeZone,
        [AllowEmptyString()][string]$ProjectId,
        [AllowEmptyString()][string]$ProjectNameSnapshot,
        [AllowEmptyString()][string]$ClientId,
        [AllowEmptyString()][string]$ClientNameSnapshot,
        [AllowEmptyString()][string]$ChannelProvider,
        [AllowEmptyString()][string]$ChannelId,
        [AllowEmptyString()][string]$ChannelNameSnapshot,
        [AllowEmptyString()][string]$OwnerId,
        [AllowEmptyString()][string]$OwnerNameSnapshot,
        [object[]]$Media,
        [AllowEmptyString()][string]$ExternalUrl,
        [AllowEmptyString()][string]$PublishedAtUtc
    )

    $changes = @{}
    foreach ($name in @(
        'Title',
        'Description',
        'Status',
        'StartUtc',
        'EndUtc',
        'TimeZone',
        'ProjectId',
        'ProjectNameSnapshot',
        'ClientId',
        'ClientNameSnapshot',
        'ChannelProvider',
        'ChannelId',
        'ChannelNameSnapshot',
        'OwnerId',
        'OwnerNameSnapshot',
        'Media',
        'ExternalUrl',
        'PublishedAtUtc'
    )) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $changes[$name] = $PSBoundParameters[$name]
        }
    }
    if ($changes.Count -eq 0) {
        throw [System.ArgumentException]::new(
            'At least one publication field must be supplied.')
    }
    if (-not $PSCmdlet.ShouldProcess($Id, 'Update RenderKit publication')) {
        return
    }
    return Update-RenderKitPublicationRecord `
        -Id $Id `
        -ExpectedRevision $ExpectedRevision `
        -Changes $changes
}
