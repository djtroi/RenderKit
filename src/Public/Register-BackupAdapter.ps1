Register-RenderKitFunction "Register-BackupAdapter"
function Register-BackupAdapter {
    <#
.SYNOPSIS
Registers a backup Storage, Encoder, Verifier, or Notifier adapter.

.DESCRIPTION
Operations may be ScriptBlocks for process-local adapters or exported command
names from ModuleName for adapters that must work in detached workers.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^(storage|encoder|verifier|notifier)\.[a-z0-9][a-z0-9.-]*$')]
        [string]$Id,
        [Parameter(Mandatory)]
        [ValidateSet('Storage', 'Encoder', 'Verifier', 'Notifier')]
        [string]$Type,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Version,
        [string[]]$Alias = @(),
        [string[]]$Capability = @(),
        [Parameter(Mandatory)]
        [hashtable]$Operations,
        [string]$ModuleName,
        [int]$Priority = 0,
        [object]$Metadata,
        [switch]$Force
    )

    $adapter = Register-BackupAdapterDefinition `
        -Id $Id `
        -Type $Type `
        -Name $Name `
        -Version $Version `
        -Aliases $Alias `
        -Capabilities $Capability `
        -Operations $Operations `
        -ModuleName $ModuleName `
        -Priority $Priority `
        -Metadata $Metadata `
        -Force:$Force
    return ConvertTo-BackupAdapterPublicView -Adapter $adapter
}
