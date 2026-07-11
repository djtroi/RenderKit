Register-RenderKitFunction "Add-MetadataTemplate"
function Add-MetadataTemplate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'File')]
        [Alias('FullName')]
        [string]$Path,

        [Parameter(ParameterSetName = 'File')]
        [Parameter(Mandatory, ParameterSetName = 'ProjectRoot')]
        [string]$ProjectRoot,

        [Parameter(Mandatory, ParameterSetName = 'ProjectName')]
        [string]$ProjectName,

        [switch]$Override,

        [switch]$NoEmbedded,

        [switch]$IncludeUnsupported
    )

    begin {
        $templateContext = Read-RenderKitMetadataTemplate -Name $Name
        $template = $templateContext.Template
        $metadata = ConvertTo-RenderKitMetadataDictionary -Value $template.fields
        if ($metadata.Count -eq 0) {
            throw "Metadata template '$Name' has no fields."
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ProjectName') {
            $project = @(Get-Project -AvailableOnly |
                Where-Object { [string]$_.Name -ieq $ProjectName })
            if ($project.Count -eq 0) {
                throw "RenderKit project '$ProjectName' was not found or is not available."
            }
            if ($project.Count -gt 1) {
                throw "RenderKit project name '$ProjectName' is ambiguous. Use -ProjectRoot."
            }
            $ProjectRoot = [string]$project[0].RootPath
        }

        if ($PSCmdlet.ParameterSetName -in @('ProjectRoot', 'ProjectName')) {
            $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).ProviderPath
            if (-not $PSCmdlet.ShouldProcess($resolvedProjectRoot, "Apply metadata template '$Name' to project")) {
                return
            }

            $startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            $entries = New-Object System.Collections.Generic.List[object]
            $files = @(
                Get-ChildItem -LiteralPath $resolvedProjectRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object {
                        $relative = ConvertTo-RenderKitProjectRelativePath `
                            -BasePath $resolvedProjectRoot `
                            -Path $_.FullName
                        -not ($relative -like '.renderkit/*')
                    }
            )

            foreach ($file in $files) {
                $relativePath = ConvertTo-RenderKitProjectRelativePath `
                    -BasePath $resolvedProjectRoot `
                    -Path $file.FullName
                $route = Resolve-RenderKitMetadataAdapterRoute -Path $file.FullName
                if (-not $IncludeUnsupported -and -not [bool]$route.IsSupported) {
                    $entries.Add([PSCustomObject]@{
                        path = $file.FullName
                        relativePath = $relativePath
                        status = 'Skipped'
                        reason = 'UnsupportedMediaType'
                        beforeVersion = 0
                        afterVersion = 0
                        changes = @()
                        skipped = @()
                    })
                    continue
                }

                try {
                    $before = Read-RenderKitFileMetadataRecord `
                        -Path $file.FullName `
                        -ProjectRoot $resolvedProjectRoot
                    $beforeVersion = if ($before) { [int]$before.version } else { 0 }
                    $storeResult = Set-RenderKitFileMetadataRecordField `
                        -Path $file.FullName `
                        -ProjectRoot $resolvedProjectRoot `
                        -Metadata $metadata `
                        -Override:$Override

                    $changedMetadata = [ordered]@{}
                    foreach ($change in @($storeResult.Changes)) {
                        Set-RenderKitMetadataFieldValue `
                            -Fields $changedMetadata `
                            -Name ([string]$change.Field) `
                            -Value $change.NewValue
                    }
                    $embeddedResults = @()
                    if (-not $NoEmbedded -and $changedMetadata.Count -gt 0) {
                        $embeddedResults = @(Invoke-RenderKitEmbeddedMetadataWrite `
                            -Path $file.FullName `
                            -Metadata $changedMetadata)
                    }

                    $status = if (@($storeResult.Changes).Count -gt 0) { 'Succeeded' } else { 'Skipped' }
                    $reason = if ($status -eq 'Skipped') { 'NoChanges' } else { $null }
                    $entries.Add([PSCustomObject]@{
                        path = $file.FullName
                        relativePath = $relativePath
                        status = $status
                        reason = $reason
                        beforeVersion = $beforeVersion
                        afterVersion = [int]$storeResult.Version
                        recordPath = [string]$storeResult.RecordPath
                        changes = @($storeResult.Changes)
                        skipped = @($storeResult.Skipped)
                        embedded = @($embeddedResults)
                    })
                }
                catch {
                    $entries.Add([PSCustomObject]@{
                        path = $file.FullName
                        relativePath = $relativePath
                        status = 'Failed'
                        reason = $_.Exception.Message
                        beforeVersion = 0
                        afterVersion = 0
                        changes = @()
                        skipped = @()
                    })
                }
            }

            $batch = New-RenderKitMetadataBatchRecord `
                -ProjectRoot $resolvedProjectRoot `
                -TemplateName ([string]$template.name) `
                -TemplateGeneration ([int]$template.revision.generation) `
                -StartedAtUtc $startedAtUtc `
                -Entries @($entries.ToArray()) `
                -Override:$Override
            $batchContext = Write-RenderKitMetadataBatchRecord `
                -ProjectRoot $resolvedProjectRoot `
                -Batch $batch

            return [PSCustomObject]@{
                BatchId = [string]$batch.batchId
                BatchPath = [string]$batchContext.Path
                ProjectRoot = $resolvedProjectRoot
                TemplateName = [string]$template.name
                TemplateGeneration = [int]$template.revision.generation
                Total = [int]$batch.summary.total
                Succeeded = [int]$batch.summary.succeeded
                Failed = [int]$batch.summary.failed
                Skipped = [int]$batch.summary.skipped
                Entries = @($batch.entries)
            }
        }

        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
        if (-not $PSCmdlet.ShouldProcess($resolvedPath, "Apply metadata template '$Name'")) {
            return
        }
        $storeResult = Set-RenderKitFileMetadataRecordField `
            -Path $resolvedPath `
            -ProjectRoot $ProjectRoot `
            -Metadata $metadata `
            -Override:$Override

        $changedMetadata = [ordered]@{}
        foreach ($change in @($storeResult.Changes)) {
            Set-RenderKitMetadataFieldValue `
                -Fields $changedMetadata `
                -Name ([string]$change.Field) `
                -Value $change.NewValue
        }

        $embeddedResults = @()
        if (-not $NoEmbedded -and $changedMetadata.Count -gt 0) {
            $embeddedResults = @(Invoke-RenderKitEmbeddedMetadataWrite `
                -Path $resolvedPath `
                -Metadata $changedMetadata)
        }

        return [PSCustomObject]@{
            Path = $resolvedPath
            TemplateName = [string]$template.name
            TemplateGeneration = [int]$template.revision.generation
            ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $null } else { [System.IO.Path]::GetFullPath($ProjectRoot) }
            Override = [bool]$Override
            StorePath = [string]$storeResult.RecordPath
            StorageMode = [string]$storeResult.StorageMode
            MetadataVersion = [int]$storeResult.Version
            StoreWritten = [bool]$storeResult.Written
            Changes = @($storeResult.Changes)
            Skipped = @($storeResult.Skipped)
            Embedded = @($embeddedResults)
        }
    }
}
