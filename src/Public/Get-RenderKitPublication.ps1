Register-RenderKitFunction 'Get-RenderKitPublication'
function Get-RenderKitPublication {
    <#
.SYNOPSIS
Reads publication planning records from the global RenderKit schedule.
#>
    [CmdletBinding(DefaultParameterSetName = 'Range')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Id')]
        [string]$Id,
        [Parameter(Mandatory, ParameterSetName = 'Range')]
        [string]$FromUtc,
        [Parameter(Mandatory, ParameterSetName = 'Range')]
        [string]$ToUtc,
        [Parameter(ParameterSetName = 'Range')]
        [string]$Search,
        [Parameter(ParameterSetName = 'Range')]
        [ValidateSet(
            'Draft',
            'Scheduled',
            'Publishing',
            'Published',
            'Failed',
            'Cancelled'
        )]
        [string]$Status,
        [Parameter(ParameterSetName = 'Range')]
        [string]$ProjectId,
        [Parameter(ParameterSetName = 'Range')]
        [string]$ClientId,
        [Parameter(ParameterSetName = 'Range')]
        [string]$ChannelProvider
    )

    if ($PSCmdlet.ParameterSetName -eq 'Id') {
        return Get-RenderKitPublicationRecord -Id $Id
    }
    $parameters = @{
        FromUtc = $FromUtc
        ToUtc = $ToUtc
    }
    foreach ($name in @(
        'Search',
        'Status',
        'ProjectId',
        'ClientId',
        'ChannelProvider'
    )) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $parameters[$name] = $PSBoundParameters[$name]
        }
    }
    return @(Get-RenderKitPublicationRecordList @parameters)
}
