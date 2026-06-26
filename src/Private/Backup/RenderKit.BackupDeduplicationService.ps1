function Get-BackupDeduplicationObjectValue {
    [CmdletBinding()]
    param(
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        return $DefaultValue
    }
    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }

    return $DefaultValue
}

function New-BackupDeduplicationPolicy {
    [CmdletBinding()]
    param(
        [bool]$Enabled = $true,
        [ValidateSet('SHA256', 'SHA1', 'MD5')]
        [string]$Algorithm = 'SHA256'
    )

    return [PSCustomObject]@{
        schemaVersion = '1.0'
        enabled       = [bool]$Enabled
        state         = 'Planned'
        mode          = 'ContentHashCanonicalManifest'
        algorithm     = $Algorithm
        match         = [PSCustomObject]@{
            strategy          = 'HashAndLength'
            includeHiddenFiles = $true
            includeSystemFiles = $true
        }
        archive       = [PSCustomObject]@{
            storeCanonicalFileOnly = $true
            duplicateReferenceMode = 'ManifestReference'
            restoreAction          = 'RehydrateDuplicatePathsFromCanonical'
        }
        report        = [PSCustomObject]@{
            includeGroups = $true
            includeSavings = $true
        }
    }
}

function New-BackupDeduplicationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SourceIndex,
        [object]$Policy
    )

    if (-not $Policy) {
        $Policy = New-BackupDeduplicationPolicy
    }

    $enabled = [bool](Get-BackupDeduplicationObjectValue -InputObject $Policy -Name 'enabled' -DefaultValue $true)
    $algorithm = [string](Get-BackupDeduplicationObjectValue -InputObject $Policy -Name 'algorithm' -DefaultValue 'SHA256')
    $files = @(
        $SourceIndex.Values |
            Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.RelativePath) } |
            Sort-Object RelativePath
    )

    $groups = New-Object System.Collections.Generic.List[object]
    $excludedPaths = New-Object System.Collections.Generic.List[string]
    $savedBytes = [int64]0
    if ($enabled) {
        foreach ($group in @($files | Group-Object { "{0}|{1}" -f [string]$_.Hash, [int64]$_.Length })) {
            $items = @($group.Group | Sort-Object RelativePath)
            if ($items.Count -lt 2) {
                continue
            }

            $canonical = $items[0]
            $duplicates = @($items | Select-Object -Skip 1)
            foreach ($duplicate in $duplicates) {
                $excludedPaths.Add([string]$duplicate.RelativePath)
                $savedBytes += [int64]$duplicate.Length
            }

            $groups.Add([PSCustomObject]@{
                    id                    = "dedup-{0}" -f ([string]$canonical.Hash).Substring(0, [Math]::Min(12, ([string]$canonical.Hash).Length)).ToLowerInvariant()
                    hash                  = [string]$canonical.Hash
                    algorithm             = [string]$canonical.Algorithm
                    lengthBytes           = [int64]$canonical.Length
                    canonicalRelativePath = [string]$canonical.RelativePath
                    duplicateRelativePaths = @($duplicates | ForEach-Object { [string]$_.RelativePath })
                    duplicateCount        = $duplicates.Count
                    savedBytes            = [int64]([int64]$canonical.Length * [int64]$duplicates.Count)
                })
        }
    }

    $excludedArray = @($excludedPaths.ToArray() | Sort-Object -Unique)
    return [PSCustomObject]@{
        schemaVersion = '1.0'
        enabled       = [bool]$enabled
        state         = if ($enabled) { 'Planned' } else { 'Disabled' }
        mode          = 'ContentHashCanonicalManifest'
        algorithm     = $algorithm
        policy        = $Policy
        groups        = @($groups.ToArray())
        archive       = [PSCustomObject]@{
            storeCanonicalFileOnly = [bool]$enabled
            excludedRelativePaths  = @($excludedArray)
            referenceMode          = 'ManifestReference'
        }
        summary       = [PSCustomObject]@{
            sourceFileCount      = $files.Count
            uniqueFileCount      = [int]($files.Count - $excludedArray.Count)
            duplicateFileCount   = $excludedArray.Count
            duplicateGroupCount  = $groups.Count
            estimatedSavedBytes  = [int64]$savedBytes
        }
    }
}

function Get-BackupDeduplicationExcludedPathSet {
    [CmdletBinding()]
    param(
        [object]$DeduplicationPlan
    )

    $set = @{}
    if (-not $DeduplicationPlan -or -not [bool](Get-BackupDeduplicationObjectValue -InputObject $DeduplicationPlan -Name 'enabled' -DefaultValue $false)) {
        return $set
    }

    $archive = Get-BackupDeduplicationObjectValue -InputObject $DeduplicationPlan -Name 'archive'
    foreach ($path in @(Get-BackupDeduplicationObjectValue -InputObject $archive -Name 'excludedRelativePaths' -DefaultValue @())) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
            $set[[string]$path] = $true
        }
    }

    return $set
}

function Get-BackupDeduplicationDuplicateMap {
    [CmdletBinding()]
    param(
        [object]$DeduplicationPlan
    )

    $map = @{}
    if (-not $DeduplicationPlan -or -not [bool](Get-BackupDeduplicationObjectValue -InputObject $DeduplicationPlan -Name 'enabled' -DefaultValue $false)) {
        return $map
    }

    foreach ($group in @(Get-BackupDeduplicationObjectValue -InputObject $DeduplicationPlan -Name 'groups' -DefaultValue @())) {
        $canonical = [string](Get-BackupDeduplicationObjectValue -InputObject $group -Name 'canonicalRelativePath')
        foreach ($path in @(Get-BackupDeduplicationObjectValue -InputObject $group -Name 'duplicateRelativePaths' -DefaultValue @())) {
            if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
                $map[[string]$path] = [PSCustomObject]@{
                    canonicalRelativePath = $canonical
                    hash                  = [string](Get-BackupDeduplicationObjectValue -InputObject $group -Name 'hash')
                    lengthBytes           = [int64](Get-BackupDeduplicationObjectValue -InputObject $group -Name 'lengthBytes' -DefaultValue 0)
                }
            }
        }
    }

    return $map
}
