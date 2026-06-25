function New-RenderKitProjectSearchIndex {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        tool          = 'RenderKit'
        schemaVersion = '1.0'
        updatedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        entries       = @()
    }
}

function Test-RenderKitProjectSearchIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Index
    )

    if ($Index.tool -ne 'RenderKit') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Index.schemaVersion)) {
        return $false
    }

    $compatibility = Test-RenderKitArtifactCompatibility `
        -ArtifactType ProjectSearchIndex `
        -Version ([string]$Index.schemaVersion)

    return [bool]($compatibility.CanRead -and $compatibility.CanWrite)
}

function Read-RenderKitProjectSearchIndex {
    [CmdletBinding()]
    param()

    $path = Get-RenderKitProjectSearchIndexPath
    $index = Read-RenderKitJsonFile `
        -Path $path `
        -AllowMissing `
        -Validator { param($value) Test-RenderKitProjectSearchIndex $value }

    if (-not $index) {
        return New-RenderKitProjectSearchIndex
    }

    if (-not ($index.PSObject.Properties.Name -contains 'entries') -or
        $null -eq $index.entries) {
        $index | Add-Member -NotePropertyName entries `
            -NotePropertyValue @() `
            -Force
    }

    return $index
}

function Write-RenderKitProjectSearchIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Index
    )

    $Index.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $path = Get-RenderKitProjectSearchIndexPath
    Write-RenderKitJsonFileAtomic `
        -Path $path `
        -Value $Index `
        -Depth 8 `
        -Validator { param($value) Test-RenderKitProjectSearchIndex $value } |
        Out-Null

    return $Index
}

function ConvertTo-RenderKitProjectSearchIndexPathKey {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Search index path must not be empty.'
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    $trimmed = $fullPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.Length -lt $root.Length) {
        $trimmed = $root.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            $trimmed = $root
        }
    }

    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        return $trimmed.ToUpperInvariant()
    }

    return $trimmed
}

function New-RenderKitProjectSearchIndexEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Kind = 'CustomPath',

        [string]$Source = 'Unknown',

        [ValidateRange(0, 1000)]
        [int]$Priority = 50,

        [bool]$Recursive = $true,

        [bool]$Enabled = $true
    )

    $normalizedPath = ConvertTo-RenderKitProjectSearchIndexPathKey -Path $Path
    $now = (Get-Date).ToUniversalTime().ToString('o')

    return [PSCustomObject]@{
        path             = $normalizedPath
        kind             = $Kind
        sources          = @($Source)
        priority         = $Priority
        recursive        = $Recursive
        enabled          = $Enabled
        createdAtUtc     = $now
        lastSeenAtUtc    = $now
        lastScannedAtUtc = $null
        lastScanStatus   = 'NeverScanned'
        lastError        = $null
        hitCount         = 0
    }
}

function Set-RenderKitProjectSearchIndexEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Kind = 'CustomPath',

        [string]$Source = 'Unknown',

        [ValidateRange(0, 1000)]
        [int]$Priority = 50,

        [bool]$Recursive = $true,

        [bool]$Enabled = $true,

        [switch]$ReplacePriority
    )

    $entry = New-RenderKitProjectSearchIndexEntry `
        -Path $Path `
        -Kind $Kind `
        -Source $Source `
        -Priority $Priority `
        -Recursive $Recursive `
        -Enabled $Enabled
    $pathKey = [string]$entry.path
    $indexPath = Get-RenderKitProjectSearchIndexPath

    Invoke-RenderKitJsonFileTransaction `
        -Path $indexPath `
        -DefaultValue (New-RenderKitProjectSearchIndex) `
        -Depth 8 `
        -Validator { param($value) Test-RenderKitProjectSearchIndex $value } `
        -Update {
            param($currentIndex)

            if (-not ($currentIndex.PSObject.Properties.Name -contains 'entries') -or
                $null -eq $currentIndex.entries) {
                $currentIndex | Add-Member -NotePropertyName entries `
                    -NotePropertyValue @() `
                    -Force
            }

            $now = (Get-Date).ToUniversalTime().ToString('o')
            $existing = @($currentIndex.entries | Where-Object {
                [string]$_.path -eq $pathKey
            }) | Select-Object -First 1

            if ($existing) {
                $existing.kind = $Kind
                $existing.priority = if ($ReplacePriority) {
                    $Priority
                }
                else {
                    [math]::Max([int]$existing.priority, $Priority)
                }
                $existing.recursive = [bool]$Recursive
                $existing.enabled = [bool]$Enabled
                $existing.lastSeenAtUtc = $now
                if (-not ($existing.PSObject.Properties.Name -contains 'sources') -or
                    $null -eq $existing.sources) {
                    $existing | Add-Member -NotePropertyName sources `
                        -NotePropertyValue @() `
                        -Force
                }
                $existing.sources = @(@($existing.sources) + $Source |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                    Sort-Object -Unique)
            }
            else {
                $currentIndex.entries = @($currentIndex.entries + $entry)
            }

            $currentIndex.entries = @($currentIndex.entries |
                Sort-Object -Property @{ Expression = 'priority'; Descending = $true }, path)
            $currentIndex.updatedAtUtc = $now
            return $currentIndex
        } |
        Out-Null

    return (@(Read-RenderKitProjectSearchIndex).entries | Where-Object {
        [string]$_.path -eq $pathKey
    } | Select-Object -First 1)
}

function Set-RenderKitProjectSearchIndexScanResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Status,

        [string]$ErrorMessage,

        [ValidateRange(0, 2147483647)]
        [int]$HitCountIncrement = 0
    )

    $pathKey = ConvertTo-RenderKitProjectSearchIndexPathKey -Path $Path
    $indexPath = Get-RenderKitProjectSearchIndexPath

    Invoke-RenderKitJsonFileTransaction `
        -Path $indexPath `
        -DefaultValue (New-RenderKitProjectSearchIndex) `
        -Depth 8 `
        -Validator { param($value) Test-RenderKitProjectSearchIndex $value } `
        -Update {
            param($currentIndex)

            $now = (Get-Date).ToUniversalTime().ToString('o')
            $entry = @($currentIndex.entries | Where-Object {
                [string]$_.path -eq $pathKey
            }) | Select-Object -First 1
            if (-not $entry) {
                $entry = New-RenderKitProjectSearchIndexEntry `
                    -Path $pathKey `
                    -Kind 'CustomPath' `
                    -Source 'ScanResult'
                $currentIndex.entries = @($currentIndex.entries + $entry)
            }

            $entry.lastScannedAtUtc = $now
            $entry.lastScanStatus = $Status
            $entry.lastError = $ErrorMessage
            $entry.hitCount = [int]$entry.hitCount + $HitCountIncrement
            $currentIndex.updatedAtUtc = $now
            return $currentIndex
        } |
        Out-Null

    return (@(Read-RenderKitProjectSearchIndex).entries | Where-Object {
        [string]$_.path -eq $pathKey
    } | Select-Object -First 1)
}