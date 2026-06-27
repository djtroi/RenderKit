function ConvertTo-BackupWorkerStorageTierInput {
    [CmdletBinding()]
    param(
        [object[]]$StorageTiers = @()
    )

    return @(
        foreach ($tier in @($StorageTiers)) {
            if (-not $tier) {
                continue
            }

            $targetValue = if ($tier.target) {
                [string]$tier.target.value
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$tier.path)) {
                [string]$tier.path
            }
            else {
                [string]$tier.uri
            }
            $input = @{
                Id                = [string]$tier.id
                Name              = [string]$tier.name
                Profile           = [string]$tier.profile
                Kind              = [string]$tier.kind
                Adapter           = [string]$tier.adapterId
                Role              = [string]$tier.role
                Order             = [int]$tier.order
                Required          = [bool]$tier.required
                Verify            = [bool]$tier.verify.enabled
                VerifyAlgorithm   = [string]$tier.verify.algorithm
                VerifyMode        = [string]$tier.verify.mode
                VerifierAdapter   = [string]$tier.verify.adapterId
                FallbackEnabled   = [bool]$tier.fallback.enabled
                FallbackTo        = [string]$tier.fallback.toTierId
                FallbackAction    = [string]$tier.fallback.action
                MaxRetries        = [int]$tier.copy.maxRetries
                RetryDelaySeconds = [int]$tier.copy.retryDelaySeconds
                ContinueOnFailure = [bool]$tier.copy.continueOnFailure
                Source            = 'BackgroundWorkerPlan'
            }
            if ([string]$tier.target.kind -eq 'Uri') {
                $input.Uri = $targetValue
            }
            else {
                $input.Path = $targetValue
            }
            $input
        }
    )
}

function New-BackupWorkerStagingProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [object]$Payload,
        [Parameter(Mandatory)]
        [object]$EncodingPlan
    )

    $jobStateRoot = [System.IO.Path]::GetFullPath(
        (Get-BackupJobStateRoot -JobId ([string]$Job.id)))
    $stagingParent = Join-Path -Path $jobStateRoot -ChildPath 'finalization'
    $stagingProject = Join-Path `
        -Path $stagingParent `
        -ChildPath ([string]$Payload.project.name)
    $stagingProject = [System.IO.Path]::GetFullPath($stagingProject)
    $jobStatePrefix = $jobStateRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $stagingProject.StartsWith(
            $jobStatePrefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to create backup staging project outside '$jobStateRoot'."
    }

    if (Test-Path -LiteralPath $stagingParent -PathType Container) {
        Remove-Item -LiteralPath $stagingParent -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stagingParent -Force | Out-Null
    Copy-Item `
        -LiteralPath ([string]$Payload.project.rootPath) `
        -Destination $stagingProject `
        -Recurse `
        -Force `
        -ErrorAction Stop

    $replacementCommands = if (
        [string]$Payload.archive.mode -eq 'ProxyOnly'
    ) {
        @($EncodingPlan.proxyCommands)
    }
    else {
        @($EncodingPlan.merges)
    }
    foreach ($replacement in $replacementCommands) {
        $relativePath = [string]$replacement.relativePath
        $outputPath = [string]$replacement.outputPath
        if ([string]::IsNullOrWhiteSpace($relativePath) -or
            [string]::IsNullOrWhiteSpace($outputPath)) {
            continue
        }
        if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
            throw "Encoded backup media '$outputPath' was not found."
        }

        $originalTarget = [System.IO.Path]::GetFullPath(
            (Join-Path -Path $stagingProject -ChildPath $relativePath))
        $stagingPrefix = $stagingProject.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $originalTarget.StartsWith(
                $stagingPrefix,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Encoded media path '$relativePath' escapes the staging project."
        }
        if (Test-Path -LiteralPath $originalTarget -PathType Leaf) {
            Remove-Item -LiteralPath $originalTarget -Force
        }

        $replacementExtension = [System.IO.Path]::GetExtension($outputPath)
        $replacementTarget = if (
            [string]::IsNullOrWhiteSpace($replacementExtension)
        ) {
            $originalTarget
        }
        else {
            [System.IO.Path]::ChangeExtension(
                $originalTarget,
                $replacementExtension)
        }
        $replacementDirectory = Split-Path -Path $replacementTarget -Parent
        New-Item `
            -ItemType Directory `
            -Path $replacementDirectory `
            -Force |
            Out-Null
        Copy-Item `
            -LiteralPath $outputPath `
            -Destination $replacementTarget `
            -Force `
            -ErrorAction Stop
    }

    return [PSCustomObject]@{
        parentPath  = $stagingParent
        projectPath = $stagingProject
        replacedMediaCount = @($replacementCommands).Count
    }
}

function Invoke-BackupWorkerFinalization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Job,
        [Parameter(Mandatory)]
        [object]$Payload,
        [Parameter(Mandatory)]
        [object]$EncodingPlan,
        [Parameter(Mandatory)]
        [object]$EncodingResult
    )

    if ([string]$Payload.archive.format -ne 'Zip') {
        throw (
            "Background archive finalization for format " +
            "'$($Payload.archive.format)' is not available. " +
            "Installable 7z and tar.zst archive adapters are required."
        )
    }
    if ([string]$Payload.source.deletePolicy.mode -eq
        'RemoveSourceAfterVerified') {
        throw (
            'Background source removal is not available until the staged ' +
            'archive report can attest the original source path. The source ' +
            'project was kept.'
        )
    }

    Update-BackupJobProgressSnapshot `
        -Job $Job `
        -StageName 'PreparingArchive' `
        -StageDisplayName 'Preparing archive' `
        -Message 'Building verified staging project.' `
        -Current 0 `
        -Total 3 `
        -Percent 90 |
        Out-Null

    $staging = New-BackupWorkerStagingProject `
        -Job $Job `
        -Payload $Payload `
        -EncodingPlan $EncodingPlan
    try {
        Update-BackupJobProgressSnapshot `
            -Job $Job `
            -StageName 'CreatingArchive' `
            -StageDisplayName 'Creating archive' `
            -Message 'Creating and verifying backup archive.' `
            -Current 1 `
            -Total 3 `
            -Percent 94 |
            Out-Null

        $parameters = @{
            ProjectName       = [string]$Payload.project.name
            Path              = [string]$staging.parentPath
            Preset            = @($Payload.source.cleanup.presets)
            DestinationRoot   = [string]$Payload.archive.destinationRoot
            ConfigProfile     = 'no-transcode'
            ArchiveFormat     = 'Zip'
            CompressionMode   = 'ArchiveOnly'
            CompressionPreset = [string]$Payload.archive.compressionPreset
            KeepEmptyFolders  = [bool]$Payload.source.cleanup.keepEmptyFolders
            KeepSourceProject = $true
            ReportFormat      = @($Payload.reports.formats)
            ReportRoot        = [string]$Payload.reports.destinationRoot
            VerifierAdapter   = [string]$Payload.adapters.verifier.id
            Confirm           = $false
        }
        $storageTierInput = @(
            ConvertTo-BackupWorkerStorageTierInput `
                -StorageTiers @($Payload.storageTiers)
        )
        if ($storageTierInput.Count -gt 0) {
            $parameters.StorageTier = $storageTierInput
        }

        $result = Backup-Project @parameters
        if (-not $result -or
            [string]::IsNullOrWhiteSpace([string]$result.BackupPath) -or
            -not (Test-Path -LiteralPath ([string]$result.BackupPath))) {
            throw 'Background backup finalization returned no verified archive.'
        }

        $result.ProjectName = [string]$Payload.project.name
        $result.ProjectId = [string]$Payload.project.id
        $result.RootPath = [string]$Payload.project.rootPath
        $result.SourceRemoved = $false
        $result.KeepSourceProject = $true
        $result |
            Add-Member `
                -NotePropertyName BackgroundJobId `
                -NotePropertyValue ([string]$Job.id) `
                -Force
        $result |
            Add-Member `
                -NotePropertyName Processing `
                -NotePropertyValue ([PSCustomObject]@{
                    encodedChunkCount = [int]$EncodingResult.encodedChunkCount
                    mergedAssetCount = [int]$EncodingResult.mergedAssetCount
                    qualityValidation = $EncodingResult.qualityValidation
                    scheduler = $EncodingResult.scheduler
                    stagingReplacedMediaCount = [int]$staging.replacedMediaCount
                }) `
                -Force

        Update-BackupJobProgressSnapshot `
            -Job $Job `
            -StageName 'BackupComplete' `
            -StageDisplayName 'Backup complete' `
            -Message ([string]$result.BackupPath) `
            -Current 3 `
            -Total 3 `
            -Percent 100 |
            Out-Null
        return $result
    }
    finally {
        $script:RenderKitLoggingInitialized = $false
        $script:RenderKitLogFile = $null
        $script:RenderKitDebugLogFile = $null
        if (Test-Path -LiteralPath $staging.parentPath -PathType Container) {
            Remove-Item `
                -LiteralPath $staging.parentPath `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}
