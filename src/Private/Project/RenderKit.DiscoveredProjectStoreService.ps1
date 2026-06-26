function New-RenderKitDiscoveredProjectStore {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        tool          = 'RenderKit'
        schemaVersion = '1.0'
        updatedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        projects      = @()
    }
}

function Test-RenderKitDiscoveredProjectStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Store
    )

    if ($Store.tool -ne 'RenderKit') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Store.schemaVersion)) {
        return $false
    }

    $compatibility = Test-RenderKitArtifactCompatibility `
        -ArtifactType DiscoveredProjects `
        -Version ([string]$Store.schemaVersion)

    return [bool]($compatibility.CanRead -and $compatibility.CanWrite)
}

function Read-RenderKitDiscoveredProjectStore {
    [CmdletBinding()]
    param()

    $path = Get-RenderKitDiscoveredProjectsPath
    $store = Read-RenderKitJsonFile `
        -Path $path `
        -AllowMissing `
        -Validator { param($value) Test-RenderKitDiscoveredProjectStore $value }

    if (-not $store) {
        return New-RenderKitDiscoveredProjectStore
    }

    if (-not ($store.PSObject.Properties.Name -contains 'projects') -or
        $null -eq $store.projects) {
        $store | Add-Member -NotePropertyName projects `
            -NotePropertyValue @() `
            -Force
    }

    return $store
}

function Write-RenderKitDiscoveredProjectStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Store
    )

    $Store.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $path = Get-RenderKitDiscoveredProjectsPath
    Write-RenderKitJsonFileAtomic `
        -Path $path `
        -Value $Store `
        -Depth 10 `
        -Validator { param($value) Test-RenderKitDiscoveredProjectStore $value } |
        Out-Null

    return $Store
}

function Test-RenderKitPathIsUnderRoot {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$RootPath
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        return $false
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    $fullPath = $fullPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if ([string]::IsNullOrWhiteSpace($fullPath)) {
        $fullPath = $pathRoot
    }

    $fullRoot = [System.IO.Path]::GetFullPath($RootPath)
    $rootRoot = [System.IO.Path]::GetPathRoot($fullRoot)
    $fullRoot = $fullRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if ([string]::IsNullOrWhiteSpace($fullRoot)) {
        $fullRoot = $rootRoot
    }

    $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    if ([string]::Equals($fullPath, $fullRoot, $comparison)) {
        return $true
    }

    $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($rootPrefix, $comparison)
}

function Get-RenderKitConfiguredProjectRootPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $config = Get-RenderKitConfig
    if ($config -and
        ($config.PSObject.Properties.Name -contains 'DefaultProjectPath') -and
        -not [string]::IsNullOrWhiteSpace([string]$config.DefaultProjectPath)) {
        return [System.IO.Path]::GetFullPath([string]$config.DefaultProjectPath)
    }

    return $null
}

function New-RenderKitDiscoveredProjectEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectId,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [string]$Version,

        [string]$MetadataPath,

        [string]$ConfiguredProjectRoot,

        [string]$Source = 'Discovery',

        [string]$ValidationStatus = 'Valid',

        [string]$ConflictStatus = 'None',

        [object]$ConflictDetails
    )

    $fullRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    if ([string]::IsNullOrWhiteSpace($MetadataPath)) {
        $MetadataPath = Get-RenderKitProjectMetadataPath -ProjectRoot $fullRoot
    }
    else {
        $MetadataPath = [System.IO.Path]::GetFullPath($MetadataPath)
    }

    if ([string]::IsNullOrWhiteSpace($ConfiguredProjectRoot)) {
        $ConfiguredProjectRoot = Get-RenderKitConfiguredProjectRootPath
    }

    $isInsideConfiguredRoot = Test-RenderKitPathIsUnderRoot `
        -Path $fullRoot `
        -RootPath $ConfiguredProjectRoot
    $locationType = if ($isInsideConfiguredRoot) {
        'ProjectRoot'
    }
    else {
        'CustomPath'
    }
    $now = (Get-Date).ToUniversalTime().ToString('o')

    return [PSCustomObject]@{
        id                            = $ProjectId
        name                          = $ProjectName
        rootPath                      = $fullRoot
        metadataPath                  = $MetadataPath
        version                       = $Version
        available                     = [bool](Test-Path -LiteralPath $fullRoot -PathType Container)
        configuredProjectRoot         = $ConfiguredProjectRoot
        isInsideConfiguredProjectRoot = [bool]$isInsideConfiguredRoot
        locationType                  = $locationType
        validationStatus              = $ValidationStatus
        conflictStatus                = $ConflictStatus
        conflictDetails               = $ConflictDetails
        sources                       = @($Source)
        createdAtUtc                  = $now
        lastSeenAtUtc                 = $now
        updatedAtUtc                  = $now
    }
}

function Set-RenderKitDiscoveredProjectEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectId,

        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [string]$Version,

        [string]$MetadataPath,

        [string]$ConfiguredProjectRoot,

        [string]$Source = 'Discovery',

        [string]$ValidationStatus = 'Valid',

        [string]$ConflictStatus = 'None',

        [object]$ConflictDetails
    )

    $entry = New-RenderKitDiscoveredProjectEntry `
        -ProjectId $ProjectId `
        -ProjectName $ProjectName `
        -ProjectRoot $ProjectRoot `
        -Version $Version `
        -MetadataPath $MetadataPath `
        -ConfiguredProjectRoot $ConfiguredProjectRoot `
        -Source $Source `
        -ValidationStatus $ValidationStatus `
        -ConflictStatus $ConflictStatus `
        -ConflictDetails $ConflictDetails
    $entryId = [string]$entry.id
    $entryRootPath = [string]$entry.rootPath
    $storePath = Get-RenderKitDiscoveredProjectsPath

    Invoke-RenderKitJsonFileTransaction `
        -Path $storePath `
        -DefaultValue (New-RenderKitDiscoveredProjectStore) `
        -Depth 10 `
        -Validator { param($value) Test-RenderKitDiscoveredProjectStore $value } `
        -Update {
            param($currentStore)

            if (-not ($currentStore.PSObject.Properties.Name -contains 'projects') -or
                $null -eq $currentStore.projects) {
                $currentStore | Add-Member -NotePropertyName projects `
                    -NotePropertyValue @() `
                    -Force
            }

            $now = (Get-Date).ToUniversalTime().ToString('o')
            $existing = @($currentStore.projects | Where-Object {
                [string]$_.id -eq $entryId -and
                [string]$_.rootPath -eq $entryRootPath
            }) | Select-Object -First 1

            if ($existing) {
                $createdAtUtc = [string]$existing.createdAtUtc
                if ([string]::IsNullOrWhiteSpace($createdAtUtc)) {
                    $createdAtUtc = $now
                }

                $existing.name = $entry.name
                $existing.metadataPath = $entry.metadataPath
                $existing.version = $entry.version
                $existing.available = $entry.available
                $existing.configuredProjectRoot = $entry.configuredProjectRoot
                $existing.isInsideConfiguredProjectRoot = $entry.isInsideConfiguredProjectRoot
                $existing.locationType = $entry.locationType
                $existing.validationStatus = $entry.validationStatus
                $existing.conflictStatus = $entry.conflictStatus
                if (-not ($existing.PSObject.Properties.Name -contains 'conflictDetails')) {
                    $existing | Add-Member `
                        -NotePropertyName conflictDetails `
                        -NotePropertyValue $entry.conflictDetails `
                        -Force
                }
                else {
                    $existing.conflictDetails = $entry.conflictDetails
                }
                $existing.createdAtUtc = $createdAtUtc
                $existing.lastSeenAtUtc = $now
                $existing.updatedAtUtc = $now
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
                $currentStore.projects = @($currentStore.projects + $entry)
            }

            $currentStore.projects = @($currentStore.projects |
                Sort-Object -Property name, rootPath)
            $currentStore.updatedAtUtc = $now
            return $currentStore
        } |
        Out-Null

    return (@(Read-RenderKitDiscoveredProjectStore).projects | Where-Object {
        [string]$_.id -eq $entryId -and
        [string]$_.rootPath -eq $entryRootPath
    } | Select-Object -First 1)
}

function Update-RenderKitDiscoveredProjectAvailability {
    [CmdletBinding()]
    param()

    $storePath = Get-RenderKitDiscoveredProjectsPath
    Invoke-RenderKitJsonFileTransaction `
        -Path $storePath `
        -DefaultValue (New-RenderKitDiscoveredProjectStore) `
        -Depth 10 `
        -Validator { param($value) Test-RenderKitDiscoveredProjectStore $value } `
        -Update {
            param($currentStore)

            if (-not ($currentStore.PSObject.Properties.Name -contains 'projects') -or
                $null -eq $currentStore.projects) {
                $currentStore | Add-Member -NotePropertyName projects `
                    -NotePropertyValue @() `
                    -Force
            }

            $now = (Get-Date).ToUniversalTime().ToString('o')
            foreach ($project in @($currentStore.projects)) {
                $rootPath = [string]$project.rootPath
                $available = -not [string]::IsNullOrWhiteSpace($rootPath) -and
                    (Test-Path -LiteralPath $rootPath -PathType Container)

                if (-not ($project.PSObject.Properties.Name -contains 'available')) {
                    $project | Add-Member `
                        -NotePropertyName available `
                        -NotePropertyValue ([bool]$available) `
                        -Force
                    $project.updatedAtUtc = $now
                    continue
                }

                if ([bool]$project.available -ne [bool]$available) {
                    $project.available = [bool]$available
                    $project.updatedAtUtc = $now
                }
            }

            $currentStore.updatedAtUtc = $now
            return $currentStore
        } |
        Out-Null

    return Read-RenderKitDiscoveredProjectStore
}

function Update-RenderKitDiscoveredProjectConflicts {
    [CmdletBinding()]
    param()

    $storePath = Get-RenderKitDiscoveredProjectsPath
    Invoke-RenderKitJsonFileTransaction `
        -Path $storePath `
        -DefaultValue (New-RenderKitDiscoveredProjectStore) `
        -Depth 12 `
        -Validator { param($value) Test-RenderKitDiscoveredProjectStore $value } `
        -Update {
            param($currentStore)

            if (-not ($currentStore.PSObject.Properties.Name -contains 'projects') -or
                $null -eq $currentStore.projects) {
                $currentStore | Add-Member -NotePropertyName projects `
                    -NotePropertyValue @() `
                    -Force
            }

            $now = (Get-Date).ToUniversalTime().ToString('o')
            $duplicateProjectIds = @{}
            foreach ($group in (@($currentStore.projects) | Group-Object -Property id)) {
                if ([string]::IsNullOrWhiteSpace([string]$group.Name)) {
                    continue
                }
                $rootPaths = @($group.Group | ForEach-Object {
                    ConvertTo-RenderKitProjectSearchIndexPathKey -Path ([string]$_.rootPath)
                } | Sort-Object -Unique)
                if ($rootPaths.Count -gt 1) {
                    $duplicateProjectIds[[string]$group.Name] = $rootPaths
                }
            }

            foreach ($project in @($currentStore.projects)) {
                if (-not ($project.PSObject.Properties.Name -contains 'conflictDetails')) {
                    $project | Add-Member `
                        -NotePropertyName conflictDetails `
                        -NotePropertyValue $null `
                        -Force
                }

                $projectId = [string]$project.id
                if ($duplicateProjectIds.ContainsKey($projectId)) {
                    $project.conflictStatus = 'DuplicateProjectId'
                    $project.conflictDetails = [PSCustomObject]@{
                        type = 'DuplicateProjectId'
                        projectId = $projectId
                        rootPaths = @($duplicateProjectIds[$projectId])
                        detectedAtUtc = $now
                    }
                    $project.updatedAtUtc = $now
                }
                elseif ([string]$project.conflictStatus -eq 'DuplicateProjectId') {
                    $project.conflictStatus = 'None'
                    $project.conflictDetails = $null
                    $project.updatedAtUtc = $now
                }
            }

            $currentStore.updatedAtUtc = $now
            return $currentStore
        } |
        Out-Null

    return Read-RenderKitDiscoveredProjectStore
}