function Find-RenderKitProjectCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [bool]$Recursive = $true,

        [ValidateRange(0, 64)]
        [int]$MaxDepth = 8,

        [ValidateRange(1, 1000000)]
        [int]$MaxDirectories = 10000
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($RootPath)
    $results = New-Object System.Collections.Generic.List[string]
    $visited = New-Object 'System.Collections.Generic.HashSet[string]'
    $queue = New-Object System.Collections.Queue
    $directoriesVisited = 0

    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        return @()
    }

    $queue.Enqueue([PSCustomObject]@{
        Path = $resolvedRoot
        Depth = 0
    })

    while ($queue.Count -gt 0 -and $directoriesVisited -lt $MaxDirectories) {
        $current = $queue.Dequeue()
        $currentPath = [string]$current.Path
        $currentDepth = [int]$current.Depth
        $currentKey = ConvertTo-RenderKitProjectSearchIndexPathKey -Path $currentPath
        if (-not $visited.Add($currentKey)) {
            continue
        }

        $directoriesVisited++
        $markerPath = Join-Path -Path $currentPath -ChildPath '.renderkit'
        if (Test-Path -LiteralPath $markerPath -PathType Container) {
            $results.Add($currentPath) | Out-Null
            continue
        }

        if (-not $Recursive -or $currentDepth -ge $MaxDepth) {
            continue
        }

        $children = @()
        try {
            $children = @(Get-ChildItem `
                -LiteralPath $currentPath `
                -Directory `
                -Force `
                -ErrorAction Stop)
        }
        catch {
            continue
        }

        foreach ($child in $children) {
            if ($child.Name -eq '.renderkit') {
                continue
            }
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }
            $queue.Enqueue([PSCustomObject]@{
                Path = $child.FullName
                Depth = $currentDepth + 1
            })
        }
    }

    return @($results | Sort-Object -Unique)
}

function Test-RenderKitProjectDiscoveryCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $fullRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $metadataPath = Get-RenderKitProjectMetadataPath -ProjectRoot $fullRoot
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        return [PSCustomObject]@{
            IsValid = $false
            ProjectRoot = $fullRoot
            MetadataPath = $metadataPath
            Error = 'MissingMetadata'
            Metadata = $null
        }
    }

    $metadata = $null
    try {
        $metadata = Read-RenderKitJsonFile -Path $metadataPath
    }
    catch {
        return [PSCustomObject]@{
            IsValid = $false
            ProjectRoot = $fullRoot
            MetadataPath = $metadataPath
            Error = 'InvalidMetadataJson'
            Metadata = $null
        }
    }

    if ($metadata.tool -ne 'RenderKit' -or
        -not $metadata.project -or
        [string]::IsNullOrWhiteSpace([string]$metadata.project.id) -or
        [string]::IsNullOrWhiteSpace([string]$metadata.project.name)) {
        return [PSCustomObject]@{
            IsValid = $false
            ProjectRoot = $fullRoot
            MetadataPath = $metadataPath
            Error = 'InvalidMetadataSchema'
            Metadata = $metadata
        }
    }

    $version = $null
    if ($metadata.PSObject.Properties.Name -contains 'projectVersion') {
        $version = [string]$metadata.projectVersion
    }

    return [PSCustomObject]@{
        IsValid = $true
        ProjectId = [string]$metadata.project.id
        ProjectName = [string]$metadata.project.name
        ProjectRoot = $fullRoot
        MetadataPath = $metadataPath
        Version = $version
        Error = $null
        Metadata = $metadata
    }
}

function Invoke-RenderKitProjectDiscovery {
    [CmdletBinding()]
    param(
        [ValidateRange(0, 64)]
        [int]$MaxDepth = 8,

        [ValidateRange(1, 1000000)]
        [int]$MaxDirectoriesPerRoot = 10000
    )

    $startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $index = Read-RenderKitProjectSearchIndex
    $entries = @($index.entries | Where-Object {
        -not ($_.PSObject.Properties.Name -contains 'enabled') -or [bool]$_.enabled
    } | Sort-Object -Property @{ Expression = 'priority'; Descending = $true }, path)

    $validCandidates = @()
    $validationFailures = @()
    $rootsScanned = 0
    $rootsMissing = 0

    foreach ($entry in $entries) {
        $rootPath = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($rootPath)) {
            continue
        }

        if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
            $rootsMissing++
            Set-RenderKitProjectSearchIndexScanResult `
                -Path $rootPath `
                -Status 'Missing' `
                -ErrorMessage 'Path does not exist.' |
                Out-Null
            continue
        }

        $rootsScanned++
        $recursive = if ($entry.PSObject.Properties.Name -contains 'recursive') {
            [bool]$entry.recursive
        }
        else {
            $true
        }
        $candidates = @(Find-RenderKitProjectCandidate `
            -RootPath $rootPath `
            -Recursive $recursive `
            -MaxDepth $MaxDepth `
            -MaxDirectories $MaxDirectoriesPerRoot)
        $seenCandidateRoots = @{}

        foreach ($candidateRoot in $candidates) {
            $candidateKey = ConvertTo-RenderKitProjectSearchIndexPathKey -Path $candidateRoot
            if ($seenCandidateRoots.ContainsKey($candidateKey)) {
                continue
            }
            $seenCandidateRoots[$candidateKey] = $true
            $validation = Test-RenderKitProjectDiscoveryCandidate `
                -ProjectRoot $candidateRoot
            if ($validation.IsValid) {
                $validCandidates += $validation
            }
            else {
                $validationFailures += $validation
            }
        }

        Set-RenderKitProjectSearchIndexScanResult `
            -Path $rootPath `
            -Status 'Succeeded' `
            -HitCountIncrement @($candidates).Count |
            Out-Null
    }

    $uniqueCandidates = @{}
    foreach ($candidate in $validCandidates) {
        $key = '{0}|{1}' -f $candidate.ProjectId, (
            ConvertTo-RenderKitProjectSearchIndexPathKey -Path $candidate.ProjectRoot
        )
        $uniqueCandidates[$key] = $candidate
    }
    $validCandidates = @($uniqueCandidates.Values)

    $duplicateIds = @{}
    foreach ($group in ($validCandidates | Group-Object -Property ProjectId)) {
        $rootCount = @($group.Group | ForEach-Object {
            ConvertTo-RenderKitProjectSearchIndexPathKey -Path $_.ProjectRoot
        } | Sort-Object -Unique).Count
        if ($rootCount -gt 1) {
            $duplicateIds[[string]$group.Name] = $true
        }
    }

    foreach ($candidate in $validCandidates) {
        $conflictStatus = if ($duplicateIds.ContainsKey([string]$candidate.ProjectId)) {
            'DuplicateProjectId'
        }
        else {
            'None'
        }

        Set-RenderKitDiscoveredProjectEntry `
            -ProjectId ([string]$candidate.ProjectId) `
            -ProjectName ([string]$candidate.ProjectName) `
            -ProjectRoot ([string]$candidate.ProjectRoot) `
            -Version ([string]$candidate.Version) `
            -MetadataPath ([string]$candidate.MetadataPath) `
            -Source 'Discovery' `
            -ValidationStatus 'Valid' `
            -ConflictStatus $conflictStatus |
            Out-Null
    }

    Update-RenderKitDiscoveredProjectConflicts | Out-Null

    $candidateCount = @($validCandidates).Count + @($validationFailures).Count

    return [PSCustomObject]@{
        startedAtUtc = $startedAtUtc
        completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        rootsScanned = $rootsScanned
        rootsMissing = $rootsMissing
        candidatesFound = $candidateCount
        projectsDiscovered = @($validCandidates).Count
        validationFailures = @($validationFailures).Count
        duplicateProjectIds = @($duplicateIds.Keys).Count
    }
}