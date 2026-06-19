function Get-RenderKitProjectStatusPolicy {
    [CmdletBinding()]
    param()

    return @{
        InitialStatus = 'Draft'
        UnknownStatus = 'Unknown'
        Statuses = @('Unknown', 'Draft', 'Active', 'Delivered', 'Archived', 'Cancelled')
        Transitions = @{
            Unknown   = @('Draft', 'Active', 'Delivered', 'Archived', 'Cancelled')
            Draft     = @('Active', 'Archived', 'Cancelled')
            Active    = @('Draft', 'Delivered', 'Archived', 'Cancelled')
            Delivered = @('Draft', 'Active', 'Archived', 'Cancelled')
            Archived  = @()
            Cancelled = @()
        }
    }
}

function Get-RenderKitProjectStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Metadata
    )

    if ($Metadata.lifecycle -is [System.Collections.IDictionary] -and
        $Metadata.lifecycle.Contains('status') -and
        -not [string]::IsNullOrWhiteSpace([string]$Metadata.lifecycle['status'])) {
        return [string]$Metadata.lifecycle['status']
    }

    if ($Metadata.lifecycle -and
        $Metadata.lifecycle.PSObject.Properties.Name -contains 'status' -and
        -not [string]::IsNullOrWhiteSpace([string]$Metadata.lifecycle.status)) {
        return [string]$Metadata.lifecycle.status
    }

    return (Get-RenderKitProjectStatusPolicy).UnknownStatus
}

function Test-RenderKitProjectStatusTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FromStatus,
        [Parameter(Mandatory)]
        [string]$ToStatus
    )

    $policy = Get-RenderKitProjectStatusPolicy
    if ($policy.Statuses -notcontains $FromStatus) {
        throw "Unknown RenderKit project status '$FromStatus'."
    }
    if ($policy.Statuses -notcontains $ToStatus) {
        throw "Unknown RenderKit project status '$ToStatus'."
    }
    if ($FromStatus -eq $ToStatus) {
        return [PSCustomObject]@{
            Allowed = $true
            NoOp    = $true
            Reason  = 'SameStatus'
        }
    }

    $allowedTargets = @($policy.Transitions[$FromStatus])
    return [PSCustomObject]@{
        Allowed = [bool]($allowedTargets -contains $ToStatus)
        NoOp    = $false
        Reason  = if ($allowedTargets -contains $ToStatus) {
            'Allowed'
        }
        else {
            'TransitionNotAllowed'
        }
    }
}

function Ensure-RenderKitProjectLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Metadata
    )

    if (-not $Metadata.lifecycle) {
        $Metadata | Add-Member -NotePropertyName lifecycle `
            -NotePropertyValue ([PSCustomObject]@{}) `
            -Force
    }
    elseif ($Metadata.lifecycle -is [System.Collections.IDictionary]) {
        $Metadata.lifecycle = [PSCustomObject]$Metadata.lifecycle
    }
    if (-not ($Metadata.lifecycle.PSObject.Properties.Name -contains 'history') -or
        $null -eq $Metadata.lifecycle.history) {
        $Metadata.lifecycle | Add-Member -NotePropertyName history `
            -NotePropertyValue @() `
            -Force
    }

    return $Metadata
}

function Set-RenderKitProjectMetadataStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Metadata,
        [Parameter(Mandatory)]
        [string]$Status,
        [string]$Reason,
        [string]$Source = 'System',
        [switch]$Force
    )

    $Metadata = Ensure-RenderKitProjectLifecycle -Metadata $Metadata
    $fromStatus = Get-RenderKitProjectStatus -Metadata $Metadata
    $transition = Test-RenderKitProjectStatusTransition `
        -FromStatus $fromStatus `
        -ToStatus $Status

    if (-not $transition.Allowed -and -not $Force) {
        throw "Project status transition '$fromStatus' -> '$Status' is not allowed."
    }
    if ($transition.NoOp) {
        return $Metadata
    }

    $changedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $entry = [PSCustomObject]@{
        fromStatus   = $fromStatus
        toStatus     = $Status
        changedAtUtc = $changedAtUtc
        reason       = $Reason
        source       = $Source
    }

    $Metadata.lifecycle | Add-Member -NotePropertyName status `
        -NotePropertyValue $Status `
        -Force
    $Metadata.lifecycle | Add-Member -NotePropertyName statusUpdatedAtUtc `
        -NotePropertyValue $changedAtUtc `
        -Force
    $Metadata.lifecycle | Add-Member -NotePropertyName statusReason `
        -NotePropertyValue $Reason `
        -Force
    $Metadata.lifecycle.history = @($Metadata.lifecycle.history) + @($entry)

    return $Metadata
}

function Set-RenderKitProjectStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter(Mandatory)]
        [string]$Status,
        [string]$Reason,
        [string]$Source = 'System',
        [switch]$Force
    )

    $metadataPath = Get-RenderKitProjectMetadataPath -ProjectRoot $ProjectRoot
    $metadata = Read-RenderKitJsonFile -Path $metadataPath
    $fromStatus = Get-RenderKitProjectStatus -Metadata $metadata
    $metadata = Set-RenderKitProjectMetadataStatus `
        -Metadata $metadata `
        -Status $Status `
        -Reason $Reason `
        -Source $Source `
        -Force:$Force

    Write-RenderKitProjectMetadata `
        -ProjectRoot $ProjectRoot `
        -Metadata $metadata

    Set-RenderKitProjectRegistryEntry `
        -ProjectId ([string]$metadata.project.id) `
        -ProjectName ([string]$metadata.project.name) `
        -ProjectRoot $ProjectRoot `
        -Metadata $metadata |
        Out-Null

    Write-RenderKitProjectLifecycleEvent `
        -Metadata $metadata `
        -ProjectRoot $ProjectRoot `
        -FromStatus $fromStatus `
        -ToStatus $Status `
        -Reason $Reason `
        -Source $Source |
        Out-Null

    return $metadata
}