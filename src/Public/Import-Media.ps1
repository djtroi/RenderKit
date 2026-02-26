<#
RoadMap Architecture:

    1. Expand Template-Achitecture Logic
        - Add into template .json  Folder Mappings - done
        - Each Folder Needs: a global Type from the TypeList 
        - Each Type Accepts defined File Extensions only (With Override functions) - done
        - There can be more Mapping rules. - done
        - The Connection between Mappings and Template are n to n - done
        - We to define a path for each type. 
        - Final: Get it production ready 

    2. Create a Drive Detection Engine
        - Function to automatically detect removable drives like Cameras, SD Cards, Thumb Drives etc
        for convenience --> Generate a List for User in CLI and let him confirm it 
        - Check for Volume Name (TypeList with common camera names etc. --> Extra Function to 
        manage this whitelist) Appdata -> RenderKit -> detectlist.json or .txt --> 
        - Check for Format System of the Drive (TypeList for common Format System for SD cards, cameras etc)
        I need to Do some research about this topic
        - Create a Function to expand the WhiteList with SerialNumber = Once Mapped -> Its saved in AppData config
        You never need to map your drive again
        - WhiteLists are always in AppData (Appdata -> RenderKit -> Devices.json)

    3. ACTUALLY Build an Import-Engine in 6 Phases: 
        Phase 1 - Detect Source 
            - Show all the potencial Drives, that we detected in Step 2. 
            - Get the Confirmation / Correction from User in a sexy CLI UX
            - If it shows broken things, let the user give the actual absolute path
        Phase 2 - Scan & Filter
            - First things first -> We scan the whole Drive with [System.IO.DirectoryInfo]
            - We Filter --> Folder --> Time Range --> Wildcard --> Combination all of it 
            - We Return the Results and let the user decide what he wants to import
            - The User has still the option do define his own filters 
            - If the Criteria are defined --> List a sexy UI Table with the contents that are 
            goint to be imported 
            - We let the User confirm the import 
        Phase 3 - Classification
            - Now we know what to import, and where to import
            but we don't know that type where to import
            - We Iterate through every file and check the file extension
            - We search for the Template-Mapping for that file extension (We read the template information for the mappings, where we wan to copy the files)
            - Now we search for the Folder type that includes the extension 
            and read out the folder name as a path
            - If we don't find a mapping for an extension we classify it as "unassigned"
            - After the Iteration we ask the user how to Handle unassigned File Types 
            With a List of destination folders from the Project Folder (sexy UI ofc.)
            with the option to skip it after the import (It creates a temporary "TO SORT" folder or similar)
        Phase 4 - Transaction-Safe Transfer
            - This is the most critical step, since we don't want to fk up raw Footage from the User.
            - We Copy to a .renderkit\import-temp 
            - We calculate a hash 
            - We compare the hash 
            - If hash == hash we move from temp to final location
            - If we have an error, we delete the rollback temp
            - We log every transaktion with timestamp, we build a loading bar, we log the duration, speed, etc.
            - Whatif option for simulation
        Phase 5 - Logging & Revision
            - Create ".renderkit/import-2026-02-12.log"
            With these Information: StartTime, SourceDrive, FileCount, Hash, Destination,
            User, Template, Template Version, RenderKitVersion, json Schema version, 
            and maybe some other fancy stuff that is relevant for revision
        Phase 6 - Final Report
            - Finally we create an import summary with: 
                - Count.Files Imported
                - Total Size in GB
                - Duration
                - Average Copy Speed 
                - Sum of unassigned files (handled / unhandled)
                - Implement a Progressbar (PS Native)
                    - Sum of Bytes 
                    - Already copied bytes
                    - avg. speed

    4. Potential nice to have Features after the implementations of all above
        - SHA256 Manifest
        - Duplicate Detection
        - Pause / Resume Import 
        - Device Registry
        - Camera Profiles (Folder Structure / Import efficiency)

#>
function Import-Media {
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
        $InteractiveFilter = [bool]$wizardConfig.InteractiveFilter
        $AutoSelectAll = [bool]$wizardConfig.AutoSelectAll
        $AutoConfirm = [bool]$wizardConfig.AutoConfirm
        $ProjectRoot = [string]$wizardConfig.ProjectRoot
        $Classify = [bool]$wizardConfig.Classify
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
    $catalog = @(Get-RenderKitImportFileCatalog -SourcePath $resolvedSourcePath)

    $criteria = New-RenderKitImportCriteria `
        -FolderFilter $FolderFilter `
        -FromDate $FromDate `
        -ToDate $ToDate `
        -Wildcard $Wildcard

    if ($InteractiveFilter) {
        $additionalCriteria = Read-RenderKitImportAdditionalCriteria
        if ($additionalCriteria) {
            $criteria = Merge-RenderKitImportCriteria `
                -BaseCriteria $criteria `
                -AdditionalCriteria $additionalCriteria
        }
    }

    $matchedFiles = @(
        Get-RenderKitImportFilteredFiles `
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

    $matchedTotalBytes = Get-RenderKitImportTotalBytes -Files $matchedFiles
    $selectedTotalBytes = Get-RenderKitImportTotalBytes -Files $selectedFiles

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
