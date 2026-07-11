Register-RenderKitFunction 'New-RenderKitPublication'
function New-RenderKitPublication {
    <#
.SYNOPSIS
Creates a non-recurring publication planning record.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Description,
        [ValidateSet('Draft', 'Scheduled')]
        [string]$Status = 'Draft',
        [Parameter(Mandatory)][string]$StartUtc,
        [string]$EndUtc,
        [Parameter(Mandatory)][string]$TimeZone,
        [string]$ProjectId,
        [string]$ProjectNameSnapshot,
        [string]$ClientId,
        [string]$ClientNameSnapshot,
        [string]$ChannelProvider,
        [string]$ChannelId,
        [string]$ChannelNameSnapshot,
        [string]$OwnerId,
        [string]$OwnerNameSnapshot,
        [object[]]$Media = @()
    )

    $parameters = @{
        Title = $Title
        Status = $Status
        StartUtc = $StartUtc
        TimeZone = $TimeZone
        Media = $Media
    }
    foreach ($name in @(
        'Description',
        'EndUtc',
        'ProjectId',
        'ProjectNameSnapshot',
        'ClientId',
        'ClientNameSnapshot',
        'ChannelProvider',
        'ChannelId',
        'ChannelNameSnapshot',
        'OwnerId',
        'OwnerNameSnapshot'
    )) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $parameters[$name] = $PSBoundParameters[$name]
        }
    }
    $publication = New-RenderKitPublicationRecord @parameters
    if (-not $PSCmdlet.ShouldProcess(
        [string]$publication.title,
        'Create RenderKit publication'
    )) {
        return
    }
    return Add-RenderKitPublicationRecord -Publication $publication
}
