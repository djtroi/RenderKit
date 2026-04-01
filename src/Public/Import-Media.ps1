<#
.SYNOPSIS
Scans, filters, classifies, and optionally transfers media into a RenderKit project.

.DESCRIPTION
Runs the RenderKit import workflow in interactive wizard mode or parameter-driven mode.
Without `-ScanAndFilter`, the command returns drive candidates or an interactive source selection.
With `-ScanAndFilter`, it executes scan/filter, optional classification, optional transaction-safe transfer, and final reporting.
Supports `-WhatIf` / `-Confirm` via `SupportsShouldProcess`.

.PARAMETER SelectSource
Uses interactive source selection instead of only listing drive candidates.

.PARAMETER IncludeFixed
Includes fixed disks in source candidate discovery.

.PARAMETER IncludeUnsupportedFileSystem
Includes drives with unsupported file systems in source candidate discovery.

.PARAMETER ScanAndFilter
Enables full import workflow (scan, filter, selection, optional classification/transfer).

.PARAMETER SourcePath
Explicit source folder path to scan (for example `E:\DCIM`).

.PARAMETER FolderFilter
Folder-name filters used during scan results filtering.

.PARAMETER FromDate
Start date for file timestamp filter.

.PARAMETER ToDate
End date for file timestamp filter. Must be equal to or later than `FromDate`.

.PARAMETER Wildcard
Wildcard patterns for file filtering (for example `*.mp4`, `*.wav`).

.PARAMETER InteractiveFilter
Prompts for additional filter criteria interactively.

.PARAMETER PreviewCount
Maximum number of rows shown in preview tables (1..500).

.PARAMETER AutoSelectAll
Automatically selects all matched files.

.PARAMETER AutoConfirm
Automatically confirms selected files for import.

.PARAMETER Classify
Enables classification into template/mapping destination folders.

.PARAMETER ProjectRoot
Target RenderKit project root for classification and transfer.

.PARAMETER TemplateName
Template name used for classification.

.PARAMETER UnassignedHandling
How files without mapping are handled: `Prompt`, `ToSort`, or `Skip`.

.PARAMETER UnassignedFolderName
Folder name used when unassigned files are routed to the "to sort" destination.

.PARAMETER Transfer
Enables phase 4 transaction-safe transfer after classification.

.PARAMETER TransferHashAlgorithm
Hash algorithm used for transfer integrity checks. Allowed values: `SHA256`, `SHA1`, `MD5`.

.EXAMPLE
Import-Media
Starts interactive wizard mode (no parameters).

.EXAMPLE
Import-Media -SelectSource
Shows interactive drive selection and returns selected source candidate.

.EXAMPLE
Import-Media -ScanAndFilter -SourcePath "E:\DCIM" -FolderFilter "100EOSR","101EOSR" -Wildcard "*.mp4","*.mov" -PreviewCount 50
Runs scan/filter with explicit path and preview settings.

.EXAMPLE
Import-Media -ScanAndFilter -SourcePath "E:\DCIM" -FromDate (Get-Date).AddDays(-2) -ToDate (Get-Date) -Classify -ProjectRoot "D:\Projects\ClientA_2026" -TemplateName "default"
Runs scan/filter and classification for the given project and template.

.EXAMPLE
Import-Media -ScanAndFilter -SourcePath "E:\DCIM" -Classify -Transfer -ProjectRoot "D:\Projects\ClientA_2026" -TemplateName "default" -TransferHashAlgorithm SHA256 -WhatIf
Simulates classified transfer with integrity hashing.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
System.Object
Returns either drive candidate data (discovery mode) or a detailed import summary object (scan/filter mode).

.LINK
Get-RenderKitDriveCandidate

.LINK
Select-RenderKitDriveCandidate

.LINK
Get-Help Import-Media -Detailed

.LINK
https://github.com/djtroi/RenderKit
#>
function Import-Media {
     [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
     Justification = '"Media" is already singular (Latin plural of medium, but treated as uncountable in English).')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$SelectSource,
        [switch]$IncludeFixed,
        [switch]$IncludeUnsupportedFileSystem,
        [switch]$ScanAndFilter,
        [string]$SourcePath,
        [string[]]$FolderFilter,
        [Nullable[datetime]]$FromDate,
        [Nullable[datetime]]$ToDate,
        [string[]]$Wildcard,
        [switch]$InteractiveFilter,
        [ValidateRange(1, 500)]
        [int]$PreviewCount = 30,
        [switch]$AutoSelectAll,
        [switch]$AutoConfirm,
        [switch]$Classify,
        [string]$ProjectRoot,
        [string]$TemplateName,
        [ValidateSet("Prompt", "ToSort", "Skip")]
        [string]$UnassignedHandling = "Prompt",
        [string]$UnassignedFolderName = "TO SORT",
        [switch]$Transfer,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$TransferHashAlgorithm = "SHA256"
    )

    $isWizardMode = ($PSBoundParameters.Count -eq 0)
    $wizardTransferSimulate = $false
    Write-RenderKitLog -Level Debug -Message "Import-Media started: WizardMode=$isWizardMode, ScanAndFilter=$($ScanAndFilter.IsPresent), SelectSource=$($SelectSource.IsPresent), Classify=$($Classify.IsPresent), Transfer=$($Transfer.IsPresent)."

    if ($isWizardMode) {
        $wizardConfig = Start-RenderKitImportInteractiveSetup `
            -UnassignedHandling $UnassignedHandling

        if (-not $wizardConfig) {
            return $null
        }

        $ScanAndFilter = [bool]$wizardConfig.ScanAndFilter
        $SelectSource = $false
        $IncludeFixed = [bool]$wizardConfig.IncludeFixed
        $IncludeUnsupportedFileSystem = [bool]$wizardConfig.IncludeUnsupportedFileSystem
        $SourcePath = [string]$wizardConfig.SourcePath
        $FolderFilter = @($wizardConfig.FolderFilter)
        $InteractiveFilter = [bool]$wizardConfig.InteractiveFilter
        $AutoSelectAll = [bool]$wizardConfig.AutoSelectAll
        $AutoConfirm = [bool]$wizardConfig.AutoConfirm
        $ProjectRoot = [string]$wizardConfig.ProjectRoot
        $Classify = [bool]$wizardConfig.Class
        $Transfer = [bool]$wizardConfig.Transfer
        $UnassignedHandling = [string]$wizardConfig.UnassignedHandling
    }

    if (-not $ScanAndFilter) {
        if ($SelectSource) {
            return Select-RenderKitDriveCandidate `
                -IncludeFixed:$IncludeFixed `
                -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem
        }

        return Get-RenderKitDriveCandidate `
            -IncludeFixed:$IncludeFixed `
            -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem
    }

    if ($null -ne $FromDate -and $null -ne $ToDate -and $FromDate -gt $ToDate) {
        Write-RenderKitLog -Level Error -Message "-FromDate must be earlier than or equal to -ToDate."
        throw "-FromDate must be earlier than or equal to -ToDate."
    }

    $importStartedAt = Get-Date

    $resolvedSourcePath = Resolve-RenderKitImportSourcePath `
        -SourcePath $SourcePath `
        -SelectSource:$SelectSource `
        -IncludeFixed:$IncludeFixed `
        -IncludeUnsupportedFileSystem:$IncludeUnsupportedFileSystem

    if ([string]::IsNullOrWhiteSpace($resolvedSourcePath)) {
        Write-RenderKitLog -Level Warning -Message "No source was selected for scanning."
        return $null
    }

    if ($isWizardMode) {
        Show-RenderKitImportWizardStatus `
            -Title "Import context before scan" `
            -Data ([ordered]@{
                ProjectRoot                 = $ProjectRoot
                SourcePath                  = $resolvedSourcePath
                IncludeFixed                = [bool]$IncludeFixed
                IncludeUnsupportedFileSystem = [bool]$IncludeUnsupportedFileSystem
                InteractiveFilter           = [bool]$InteractiveFilter
            })
    }

    Write-Information "Phase 2: scanning source '$resolvedSourcePath'..." -InformationAction Continue
    Write-RenderKitLog -Level Info -Message "Phase 2: scanning source '$resolvedSourcePath'..."
    $catalog = @(Get-RenderKitImportFileCatalog -SourcePath $resolvedSourcePath)

    $criteria = New-RenderKitImportCriterion `
        -FolderFilter $FolderFilter `
        -FromDate $FromDate `
        -ToDate $ToDate `
        -Wildcard $Wildcard

    if ($InteractiveFilter) {
        $additionalCriteria = Read-RenderKitImportAdditionalCriterion
        if ($additionalCriteria) {
            $criteria = Merge-RenderKitImportCriterion `
                -BaseCriteria $criteria `
                -AdditionalCriteria $additionalCriteria
        }
    }

    $matchedFiles = @(
        Get-RenderKitImportFilteredFile `
            -Files $catalog `
            -Criteria $criteria |
        Sort-Object LastWriteTime, RelativePath
    )

    if ($isWizardMode) {
        Show-RenderKitImportWizardStatus `
            -Title "Scan + filter result" `
            -Data ([ordered]@{
                ScannedFiles = $catalog.Count
                MatchedFiles = $matchedFiles.Count
                SourcePath   = $resolvedSourcePath
            })
    }

    Show-RenderKitImportPreviewTable `
        -Files $matchedFiles `
        -PreviewCount $PreviewCount `
        -Title "Phase 2 preview"

    $selectedFiles = @(
        Select-RenderKitImportFileSubset `
            -Files $matchedFiles `
            -AutoSelectAll:$AutoSelectAll
    )

    if ($selectedFiles.Count -eq 0) {
        Write-RenderKitLog -Level Info -Message "No files selected for import."
    }
    else {
        Show-RenderKitImportPreviewTable `
            -Files $selectedFiles `
            -PreviewCount $PreviewCount `
            -Title "Selected files"

        if ($isWizardMode) {
            while ($true) {
                Show-RenderKitImportWizardStatus `
                    -Title "Selection checkpoint" `
                    -Data ([ordered]@{
                        MatchedFiles  = $matchedFiles.Count
                        SelectedFiles = $selectedFiles.Count
                        SelectionMode = if ($AutoSelectAll) { "Auto-select all" } else { "Manual selection" }
                    })

                $selectionReviewAction = Read-RenderKitImportSelectionReviewAction
                if ($selectionReviewAction -eq "Continue") {
                    break
                }

                if ($selectionReviewAction -eq "Cancel") {
                    $selectedFiles = @()
                    Write-RenderKitLog -Level Info -Message "Import cancelled during selection review."
                    break
                }

                $selectedFiles = @(
                    Select-RenderKitImportFileSubset `
                        -Files $matchedFiles
                )

                if ($selectedFiles.Count -eq 0) {
                    Write-RenderKitLog -Level Info -Message "No files selected for import."
                    break
                }

                Show-RenderKitImportPreviewTable `
                    -Files $selectedFiles `
                    -PreviewCount $PreviewCount `
                    -Title "Selected files (updated)"
            }
        }
    }

    $matchedTotalBytes = Get-RenderKitImportTotalByte -Files $matchedFiles
    $selectedTotalBytes = Get-RenderKitImportTotalByte -Files $selectedFiles

    $confirmed = $false
    if ($selectedFiles.Count -gt 0) {
        $confirmed = Confirm-RenderKitImportSelection `
            -FileCount $selectedFiles.Count `
            -TotalBytes $selectedTotalBytes `
            -AutoConfirm:$AutoConfirm
    }

    if (-not $confirmed -and $selectedFiles.Count -gt 0) {
        Write-RenderKitLog -Level Info -Message "Import cancelled by user."
    }

    $shouldClassify = $Classify -or $Transfer
    if ($Transfer -and -not $Classify) {
        Write-RenderKitLog -Level Info -Message "Phase 4 requires classification. Phase 3 will run automatically."
    }

    $classificationResult = $null
    if ($shouldClassify -and $confirmed -and $selectedFiles.Count -gt 0) {
        Write-Information "Phase 3: classifying selected files..." -InformationAction Continue

        $effectiveUnassignedHandling = $UnassignedHandling

        $classificationResult = Get-RenderKitImportFileClassification `
            -Files $selectedFiles `
            -ProjectRoot $ProjectRoot `
            -TemplateName $TemplateName `
            -UnassignedHandling $effectiveUnassignedHandling `
            -UnassignedFolderName $UnassignedFolderName

        Show-RenderKitImportClassificationPreview `
            -Files $classificationResult.Files `
            -PreviewCount $PreviewCount `
            -Title "Phase 3 classification"
    }
    elseif ($shouldClassify -and $selectedFiles.Count -eq 0) {
        Write-RenderKitLog -Level Info -Message "Phase 3 skipped because no files were selected."
    }
    elseif ($shouldClassify -and -not $confirmed) {
        Write-RenderKitLog -Level Info -Message "Phase 3 skipped because import was not confirmed."
    }

    $classifiedFiles = @()
    if ($classificationResult) {
        $classifiedFiles = @($classificationResult.Files)
    }

    if ($isWizardMode -and $confirmed -and $selectedFiles.Count -gt 0) {
        $transferMode = Read-RenderKitImportTransferModeInteractive
        switch ($transferMode) {
            "Real" {
                $Transfer = $true
                $wizardTransferSimulate = $false
            }
            "Simulate" {
                $Transfer = $true
                $wizardTransferSimulate = $true
            }
            default {
                $Transfer = $false
                $wizardTransferSimulate = $false
            }
        }

        Show-RenderKitImportWizardStatus `
            -Title "Transfer decision" `
            -Data ([ordered]@{
                TransferRequested = [bool]$Transfer
                TransferMode      = if ($Transfer) { if ($wizardTransferSimulate) { "Simulation" } else { "Real" } } else { "No transfer" }
                ClassifiedFiles   = if ($classificationResult) { $classificationResult.FileCount } else { 0 }
            })
    }

    $transferResult = $null
    if ($Transfer -and $confirmed -and $selectedFiles.Count -gt 0) {
        if (-not $classificationResult) {
            Write-RenderKitLog -Level Error -Message "Phase 4 requires a Phase 3 classification result."
            throw "Phase 4 requires a Phase 3 classification result."
        }

        $simulateTransfer = [bool]$WhatIfPreference -or $wizardTransferSimulate
        $executeTransfer = $true

        if ($simulateTransfer) {
            Write-Information "Phase 4: transaction-safe transfer simulation." -InformationAction Continue
        }
        else {
            $executeTransfer = $PSCmdlet.ShouldProcess(
                $classificationResult.ProjectRoot,
                "Phase 4 transfer of $($classificationResult.Files.Count) classified file(s)"
            )
        }

        if ($simulateTransfer -or $executeTransfer) {
            Write-Information "Phase 4: transaction-safe transfer..." -InformationAction Continue
            $transferResult = Invoke-RenderKitImportTransactionSafeTransfer `
                -ClassifiedFiles $classificationResult.Files `
                -ProjectRoot $classificationResult.ProjectRoot `
                -HashAlgorithm $TransferHashAlgorithm `
                -Simulate:$simulateTransfer

            if ($simulateTransfer -and $isWizardMode -and -not [bool]$WhatIfPreference) {
                $runRealTransfer = Read-RenderKitImportYesNo `
                    -Prompt "Simulation completed. Execute real transfer now?" `
                    -Default $false

                if ($runRealTransfer) {
                    $executeRealTransfer = $PSCmdlet.ShouldProcess(
                        $classificationResult.ProjectRoot,
                        "Phase 4 REAL transfer of $($classificationResult.Files.Count) classified file(s)"
                    )

                    if ($executeRealTransfer) {
                        Write-Information "Phase 4: transaction-safe REAL transfer..." -InformationAction Continue
                        $transferResult = Invoke-RenderKitImportTransactionSafeTransfer `
                            -ClassifiedFiles $classificationResult.Files `
                            -ProjectRoot $classificationResult.ProjectRoot `
                            -HashAlgorithm $TransferHashAlgorithm
                        $wizardTransferSimulate = $false
                    }
                    else {
                        Write-RenderKitLog -Level Info -Message "Real transfer skipped by ShouldProcess."
                    }
                }
                else {
                    Write-RenderKitLog -Level Info -Message "Real transfer cancelled. Keeping simulation result only."
                }
            }
        }
        else {
            Write-RenderKitLog -Level Info -Message "Phase 4 skipped by ShouldProcess."
        }
    }
    elseif ($Transfer -and $selectedFiles.Count -eq 0) {
        Write-RenderKitLog -Level Info -Message "Phase 4 skipped because no files were selected."
    }
    elseif ($Transfer -and -not $confirmed) {
        Write-RenderKitLog -Level Info -Message "Phase 4 skipped because import was not confirmed."
    }

    $importEndedAt = Get-Date
    $finalReport = New-RenderKitImportFinalReport `
        -ImportStartedAt $importStartedAt `
        -ImportEndedAt $importEndedAt `
        -SourcePath $resolvedSourcePath `
        -ScanFileCount $catalog.Count `
        -MatchedFileCount $matchedFiles.Count `
        -SelectedFileCount $selectedFiles.Count `
        -SelectedTotalBytes $selectedTotalBytes `
        -Classification $classificationResult `
        -Transfer $transferResult

    Show-RenderKitImportFinalReport -Report $finalReport

    $revisionLogPath = $null
    $effectiveProjectRoot = $null
    if ($transferResult -and -not [string]::IsNullOrWhiteSpace([string]$transferResult.ProjectRoot)) {
        $effectiveProjectRoot = [string]$transferResult.ProjectRoot
    }
    elseif ($classificationResult -and -not [string]::IsNullOrWhiteSpace([string]$classificationResult.ProjectRoot)) {
        $effectiveProjectRoot = [string]$classificationResult.ProjectRoot
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        try {
            $effectiveProjectRoot = Resolve-RenderKitImportProjectRoot -ProjectRoot $ProjectRoot
        }
        catch {
            Write-RenderKitLog -Level Warning -Message "Phase 5 skipped: invalid project root '$ProjectRoot'."
        }
    }

    if ($confirmed -and [bool]$WhatIfPreference) {
        Write-RenderKitLog -Level Info -Message "Phase 5 skipped in WhatIf mode (simulation)."
    }
    elseif ($confirmed -and -not [string]::IsNullOrWhiteSpace($effectiveProjectRoot)) {
        try {
            $revisionLogPath = Write-RenderKitImportRevisionLog `
                -ProjectRoot $effectiveProjectRoot `
                -ImportStartedAt $importStartedAt `
                -ImportEndedAt $importEndedAt `
                -SourcePath $resolvedSourcePath `
                -ScanFileCount $catalog.Count `
                -MatchedFileCount $matchedFiles.Count `
                -SelectedFileCount $selectedFiles.Count `
                -SelectedTotalBytes $selectedTotalBytes `
                -Filters $criteria `
                -Classification $classificationResult `
                -Transfer $transferResult `
                -FinalReport $finalReport
        }
        catch {
            Write-RenderKitLog -Level Warning -Message "Phase 5 revision log could not be written: $($_.Exception.Message)"
        }
    }
    elseif ($confirmed) {
        Write-RenderKitLog -Level Warning -Message "Phase 5 skipped: no project root context was available."
    }

    return [PSCustomObject]@{
        SourcePath         = $resolvedSourcePath
        ImportStartedAt    = $importStartedAt
        ImportEndedAt      = $importEndedAt
        ScanFileCount      = $catalog.Count
        MatchedFileCount   = $matchedFiles.Count
        SelectedFileCount  = $selectedFiles.Count
        MatchedTotalBytes  = $matchedTotalBytes
        SelectedTotalBytes = $selectedTotalBytes
        MatchedTotalGB     = [Math]::Round(([double]$matchedTotalBytes / 1GB), 3)
        SelectedTotalGB    = [Math]::Round(([double]$selectedTotalBytes / 1GB), 3)
        Filters            = $criteria
        Confirmed          = $confirmed
        Classification     = $classificationResult
        ClassifiedFileCount = if ($classificationResult) { $classificationResult.FileCount } else { 0 }
        AssignedFileCount  = if ($classificationResult) { $classificationResult.AssignedCount } else { 0 }
        ToSortFileCount    = if ($classificationResult) { $classificationResult.ToSortCount } else { 0 }
        SkippedFileCount   = if ($classificationResult) { $classificationResult.SkippedCount } else { 0 }
        UnassignedFileCount = if ($classificationResult) { $classificationResult.UnassignedCount } else { 0 }
        Transfer           = $transferResult
        ImportedFileCount  = if ($transferResult) { $transferResult.ImportedFileCount } else { 0 }
        SimulatedFileCount = if ($transferResult) { $transferResult.SimulatedFileCount } else { 0 }
        FailedTransferFileCount = if ($transferResult) { $transferResult.FailedFileCount } else { 0 }
        TransferDurationSeconds = if ($transferResult) { $transferResult.DurationSeconds } else { 0 }
        TransferAverageSpeedMBps = if ($transferResult) { $transferResult.AverageSpeedMBps } else { 0 }
        FinalReport        = $finalReport
        RevisionLogPath    = $revisionLogPath
        Files              = $selectedFiles
        ClassifiedFiles    = $classifiedFiles
    }
}
