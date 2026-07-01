BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    function Write-RenderKitLog {
        param(
            [string]$Level,
            [string]$Message,
            [switch]$NoConsole
        )
    }

    . (Join-Path $repositoryRoot 'src/Private/Import/RenderKit.ImportService.ps1')
    $script:originalGetRenderKitImportFileHashValue = (Get-Command Get-RenderKitImportFileHashValue).ScriptBlock
}

Describe 'RenderKit import transfer performance slice 1' {
    BeforeEach {
        Mock Write-RenderKitLog
        Mock Write-Progress
    }

    It 'calculates the source hash while copying the source stream' {
        $sourcePath = Join-Path $TestDrive 'source.bin'
        $destinationPath = Join-Path $TestDrive 'destination.bin'
        $bytes = New-Object byte[] (2MB + 137)
        [System.Random]::new(42).NextBytes($bytes)
        [System.IO.File]::WriteAllBytes($sourcePath, $bytes)

        $result = Copy-RenderKitImportFileToPath `
            -SourcePath $sourcePath `
            -DestinationPath $destinationPath `
            -HashAlgorithm SHA256

        $expectedHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash

        $result.BytesCopied | Should -Be $bytes.Length
        $result.SourceHash | Should -Be $expectedHash
        $result.HashAlgorithm | Should -Be 'SHA256'
        $result.DurationSeconds | Should -BeGreaterOrEqual 0
        $destinationHash | Should -Be $expectedHash
    }

    It 'reads only staging for the independent read-back hash and reports separate metrics' {
        $sourceRoot = Join-Path $TestDrive 'source'
        $projectRoot = Join-Path $TestDrive 'project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null

        $sourcePath = Join-Path $sourceRoot 'clip.bin'
        $bytes = New-Object byte[] (3MB + 257)
        [System.Random]::new(84).NextBytes($bytes)
        [System.IO.File]::WriteAllBytes($sourcePath, $bytes)

        Mock Get-RenderKitImportFileHashValue {
            param(
                [string]$Path,
                [string]$Algorithm,
                [scriptblock]$ProgressCallback
            )

            & $script:originalGetRenderKitImportFileHashValue `
                -Path $Path `
                -Algorithm $Algorithm `
                -ProgressCallback $ProgressCallback
        }

        $classifiedFile = [PSCustomObject]@{
            Name                    = 'clip.bin'
            FullName                = $sourcePath
            Length                  = [int64]$bytes.Length
            Classification          = 'Assigned'
            MappingId               = 'video'
            TypeName                = 'clip'
            DestinationRelativePath = 'MEDIA'
            DestinationPath         = $destinationDirectory
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles @($classifiedFile) `
            -ProjectRoot $projectRoot `
            -HashAlgorithm SHA256

        $transaction = $result.Transactions[0]
        $finalPath = Join-Path $destinationDirectory 'clip.bin'

        $result.ImportedFileCount | Should -Be 1
        $result.FailedFileCount | Should -Be 0
        $result.CopiedBytes | Should -Be $bytes.Length
        $result.VerifiedBytes | Should -Be $bytes.Length
        $result.ProcessedBytes | Should -Be $bytes.Length
        $result.CopyDurationSeconds | Should -BeGreaterOrEqual 0
        $result.VerificationDurationSeconds | Should -BeGreaterOrEqual 0
        $result.CopyAverageSpeedMBps | Should -BeGreaterThan 0
        $result.VerificationAverageSpeedMBps | Should -BeGreaterThan 0
        $result.EndToEndAverageSpeedMBps | Should -BeGreaterThan 0
        $result.AverageSpeedMBps | Should -Be $result.EndToEndAverageSpeedMBps

        $transaction.SourceHash | Should -Be $transaction.StagingHash
        $transaction.CopiedBytes | Should -Be $bytes.Length
        $transaction.VerifiedBytes | Should -Be $bytes.Length
        $transaction.CopySpeedMBps | Should -BeGreaterThan 0
        $transaction.VerificationSpeedMBps | Should -BeGreaterThan 0
        (Get-FileHash -LiteralPath $finalPath -Algorithm SHA256).Hash | Should -Be $transaction.SourceHash

        Should -Invoke Get-RenderKitImportFileHashValue -Times 1 -Exactly
        Should -Invoke Get-RenderKitImportFileHashValue -Times 0 -Exactly -ParameterFilter {
            $Path -eq $sourcePath
        }
    }

    It 'does not commit a file when the independent staging hash differs' {
        $sourceRoot = Join-Path $TestDrive 'mismatch-source'
        $projectRoot = Join-Path $TestDrive 'mismatch-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null

        $sourcePath = Join-Path $sourceRoot 'damaged.bin'
        $bytes = New-Object byte[] (1MB + 19)
        [System.Random]::new(126).NextBytes($bytes)
        [System.IO.File]::WriteAllBytes($sourcePath, $bytes)

        Mock Get-RenderKitImportFileHashValue { return 'INTENTIONAL-MISMATCH' }

        $classifiedFile = [PSCustomObject]@{
            Name                    = 'damaged.bin'
            FullName                = $sourcePath
            Length                  = [int64]$bytes.Length
            Classification          = 'Assigned'
            MappingId               = 'video'
            TypeName                = 'clip'
            DestinationRelativePath = 'MEDIA'
            DestinationPath         = $destinationDirectory
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles @($classifiedFile) `
            -ProjectRoot $projectRoot `
            -HashAlgorithm SHA256

        $transaction = $result.Transactions[0]
        $finalPath = Join-Path $destinationDirectory 'damaged.bin'

        $result.ImportedFileCount | Should -Be 0
        $result.FailedFileCount | Should -Be 1
        $result.CopiedBytes | Should -Be $bytes.Length
        $result.VerifiedBytes | Should -Be $bytes.Length
        $result.ProcessedBytes | Should -Be 0
        $transaction.Status | Should -Be 'Failed'
        $transaction.SourceHash | Should -Not -BeNullOrEmpty
        $transaction.StagingHash | Should -Be 'INTENTIONAL-MISMATCH'
        Test-Path -LiteralPath $sourcePath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $finalPath -PathType Leaf | Should -BeFalse
    }
}

Describe 'RenderKit import small and large file scheduler slice 2' {
    BeforeEach {
        Mock Write-RenderKitLog
        Mock Write-Progress
    }

    It 'uses bounded parallel workers for small files by default' {
        $sourceRoot = Join-Path $TestDrive 'parallel-source'
        $projectRoot = Join-Path $TestDrive 'parallel-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null

        $classifiedFiles = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt 6; $i++) {
            $name = "small-{0:D2}.bin" -f $i
            $sourcePath = Join-Path $sourceRoot $name
            $bytes = New-Object byte[] (2MB + $i)
            [System.Random]::new(200 + $i).NextBytes($bytes)
            [System.IO.File]::WriteAllBytes($sourcePath, $bytes)

            $classifiedFiles.Add([PSCustomObject]@{
                    Name                    = $name
                    FullName                = $sourcePath
                    Length                  = [int64]$bytes.Length
                    Classification          = 'Assigned'
                    MappingId               = 'image'
                    TypeName                = 'small'
                    DestinationRelativePath = 'MEDIA'
                    DestinationPath         = $destinationDirectory
                })
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles $classifiedFiles.ToArray() `
            -ProjectRoot $projectRoot `
            -HashAlgorithm SHA256

        $result.TransferProfile | Should -Be 'Maximum'
        $result.SmallFileThresholdMB | Should -Be 64
        $result.SmallFileConcurrency | Should -BeGreaterThan 1
        $result.LargeFileConcurrency | Should -Be 1
        $result.SmallFileCount | Should -Be 6
        $result.LargeFileCount | Should -Be 0
        $result.ParallelizedFileCount | Should -Be 6
        $result.PeakConcurrency | Should -BeGreaterThan 1
        $result.PeakCopyConcurrency | Should -BeLessOrEqual $result.SmallFileConcurrency
        $result.PeakVerifyConcurrency | Should -BeLessOrEqual $result.VerifyConcurrency
        $result.PeakConcurrency | Should -BeLessOrEqual ($result.SmallFileConcurrency + $result.VerifyConcurrency)
        $result.AdaptiveConcurrencyEnabled | Should -BeTrue
        $result.ConcurrencyAdjustments | Should -BeGreaterThan 0
        $result.PeakInFlightBytes | Should -BeLessOrEqual (512MB)
        $result.ImportedFileCount | Should -Be 6
        $result.FailedFileCount | Should -Be 0
        @($result.Transactions | Where-Object SchedulerClass -eq 'Small').Count | Should -Be 6

        foreach ($transaction in $result.Transactions) {
            $transaction.SourceHash | Should -Be $transaction.StagingHash
            Test-Path -LiteralPath $transaction.DestinationPath -PathType Leaf | Should -BeTrue
        }
    }

    It 'uses the in-flight byte budget to serialize otherwise parallel small files' {
        $sourceRoot = Join-Path $TestDrive 'budget-source'
        $projectRoot = Join-Path $TestDrive 'budget-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null

        $classifiedFiles = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt 3; $i++) {
            $name = "budget-{0:D2}.bin" -f $i
            $sourcePath = Join-Path $sourceRoot $name
            $bytes = New-Object byte[] 2MB
            [System.Random]::new(300 + $i).NextBytes($bytes)
            [System.IO.File]::WriteAllBytes($sourcePath, $bytes)

            $classifiedFiles.Add([PSCustomObject]@{
                    Name                    = $name
                    FullName                = $sourcePath
                    Length                  = [int64]$bytes.Length
                    Classification          = 'Assigned'
                    MappingId               = 'audio'
                    TypeName                = 'small'
                    DestinationRelativePath = 'MEDIA'
                    DestinationPath         = $destinationDirectory
                })
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles $classifiedFiles.ToArray() `
            -ProjectRoot $projectRoot `
            -SmallFileThresholdMB 8 `
            -SmallFileConcurrency 4 `
            -MaxInFlightMB 3

        $result.SmallFileCount | Should -Be 3
        $result.PeakConcurrency | Should -Be 1
        $result.ParallelizedFileCount | Should -Be 0
        $result.PeakInFlightBytes | Should -Be 2MB
        $result.ImportedFileCount | Should -Be 3
        $result.FailedFileCount | Should -Be 0
    }

    It 'overlaps large-file verification with the next single-worker copy' {
        $sourceRoot = Join-Path $TestDrive 'large-source'
        $projectRoot = Join-Path $TestDrive 'large-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null

        $classifiedFiles = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt 2; $i++) {
            $name = "large-{0:D2}.bin" -f $i
            $sourcePath = Join-Path $sourceRoot $name
            $bytes = New-Object byte[] (2MB + $i)
            [System.Random]::new(400 + $i).NextBytes($bytes)
            [System.IO.File]::WriteAllBytes($sourcePath, $bytes)

            $classifiedFiles.Add([PSCustomObject]@{
                    Name                    = $name
                    FullName                = $sourcePath
                    Length                  = [int64]$bytes.Length
                    Classification          = 'Assigned'
                    MappingId               = 'video'
                    TypeName                = 'large'
                    DestinationRelativePath = 'MEDIA'
                    DestinationPath         = $destinationDirectory
                })
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles $classifiedFiles.ToArray() `
            -ProjectRoot $projectRoot `
            -SmallFileThresholdMB 1

        $result.SmallFileCount | Should -Be 0
        $result.LargeFileCount | Should -Be 2
        $result.LargeFileConcurrency | Should -Be 1
        $result.ParallelizedFileCount | Should -Be 2
        $result.PeakCopyConcurrency | Should -Be 1
        $result.PeakVerifyConcurrency | Should -Be 1
        $result.PeakConcurrency | Should -Be 2
        $result.ImportedFileCount | Should -Be 2
        @($result.Transactions | Where-Object SchedulerClass -eq 'Large').Count | Should -Be 2
    }

    It 'reserves collision-safe destination paths in source order before parallel work starts' {
        $sourceRoot = Join-Path $TestDrive 'ordered-source'
        $projectRoot = Join-Path $TestDrive 'ordered-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        $largeSourceDirectory = Join-Path $sourceRoot 'large'
        $smallSourceDirectory = Join-Path $sourceRoot 'small'
        $secondSmallSourceDirectory = Join-Path $sourceRoot 'small-2'
        New-Item `
            -ItemType Directory `
            -Path $largeSourceDirectory, $smallSourceDirectory, $secondSmallSourceDirectory, $projectRoot `
            -Force |
            Out-Null

        $largeSourcePath = Join-Path $largeSourceDirectory 'shared.bin'
        $smallSourcePath = Join-Path $smallSourceDirectory 'shared.bin'
        $secondSmallSourcePath = Join-Path $secondSmallSourceDirectory 'shared.bin'
        [System.IO.File]::WriteAllBytes($largeSourcePath, (New-Object byte[] 2MB))
        [System.IO.File]::WriteAllBytes($smallSourcePath, (New-Object byte[] 512KB))
        [System.IO.File]::WriteAllBytes($secondSmallSourcePath, (New-Object byte[] 512KB))

        $classifiedFiles = @(
            [PSCustomObject]@{
                Name                    = 'shared.bin'
                FullName                = $largeSourcePath
                Length                  = [int64]2MB
                Classification          = 'Assigned'
                MappingId               = 'video'
                TypeName                = 'large'
                DestinationRelativePath = 'MEDIA'
                DestinationPath         = $destinationDirectory
            }
            [PSCustomObject]@{
                Name                    = 'shared.bin'
                FullName                = $smallSourcePath
                Length                  = [int64]512KB
                Classification          = 'Assigned'
                MappingId               = 'image'
                TypeName                = 'small'
                DestinationRelativePath = 'MEDIA'
                DestinationPath         = $destinationDirectory
            }
            [PSCustomObject]@{
                Name                    = 'shared.bin'
                FullName                = $secondSmallSourcePath
                Length                  = [int64]512KB
                Classification          = 'Assigned'
                MappingId               = 'image'
                TypeName                = 'small'
                DestinationRelativePath = 'MEDIA'
                DestinationPath         = $destinationDirectory
            }
        )

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles $classifiedFiles `
            -ProjectRoot $projectRoot `
            -SmallFileThresholdMB 1

        $result.ImportedFileCount | Should -Be 3
        $result.ParallelizedFileCount | Should -Be 2
        @($result.Transactions).Count | Should -Be 3
        $result.Transactions[0].Index | Should -Be 0
        $result.Transactions[1].Index | Should -Be 1
        $result.Transactions[2].Index | Should -Be 2
        [System.IO.Path]::GetFileName($result.Transactions[0].DestinationPath) | Should -Be 'shared.bin'
        [System.IO.Path]::GetFileName($result.Transactions[1].DestinationPath) | Should -Be 'shared_001.bin'
        [System.IO.Path]::GetFileName($result.Transactions[2].DestinationPath) | Should -Be 'shared_002.bin'
    }

    It 'falls back to serial transfer when the runspace scheduler is unavailable' {
        $sourceRoot = Join-Path $TestDrive 'fallback-source'
        $projectRoot = Join-Path $TestDrive 'fallback-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null

        $classifiedFiles = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt 2; $i++) {
            $name = "fallback-{0:D2}.bin" -f $i
            $sourcePath = Join-Path $sourceRoot $name
            [System.IO.File]::WriteAllBytes($sourcePath, (New-Object byte[] 64KB))
            $classifiedFiles.Add([PSCustomObject]@{
                    Name                    = $name
                    FullName                = $sourcePath
                    Length                  = [int64]64KB
                    Classification          = 'Assigned'
                    MappingId               = 'image'
                    TypeName                = 'small'
                    DestinationRelativePath = 'MEDIA'
                    DestinationPath         = $destinationDirectory
                })
        }

        Mock Invoke-RenderKitImportParallelTransferWorkItem {
            throw 'Runspace initialization unavailable'
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles $classifiedFiles.ToArray() `
            -ProjectRoot $projectRoot

        $result.ImportedFileCount | Should -Be 2
        $result.FailedFileCount | Should -Be 0
        $result.ParallelizedFileCount | Should -Be 0
        $result.PeakConcurrency | Should -Be 1
        Should -Invoke Write-RenderKitLog -ParameterFilter {
            $Level -eq 'Warning' -and
            $Message -like 'Small-file parallel scheduler unavailable*'
        }
    }
}

Describe 'RenderKit copy verify pipeline and same-volume move slices 3 and 4' {
    BeforeEach {
        Mock Write-RenderKitLog
        Mock Write-Progress
    }

    It 'keeps copied files in the byte budget until verification completes' {
        $sourceRoot = Join-Path $TestDrive 'pipeline-budget-source'
        $projectRoot = Join-Path $TestDrive 'pipeline-budget-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null

        $classifiedFiles = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt 3; $i++) {
            $name = "pipeline-budget-{0:D2}.bin" -f $i
            $sourcePath = Join-Path $sourceRoot $name
            [IO.File]::WriteAllBytes($sourcePath, (New-Object byte[] 2MB))
            $classifiedFiles.Add([PSCustomObject]@{
                    Name                    = $name
                    FullName                = $sourcePath
                    Length                  = [int64]2MB
                    Classification          = 'Assigned'
                    MappingId               = 'audio'
                    TypeName                = 'small'
                    DestinationRelativePath = 'MEDIA'
                    DestinationPath         = $destinationDirectory
                })
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles $classifiedFiles.ToArray() `
            -ProjectRoot $projectRoot `
            -SmallFileThresholdMB 8 `
            -SmallFileConcurrency 4 `
            -VerifyConcurrency 4 `
            -MaxInFlightMB 3

        $result.PeakInFlightBytes | Should -Be 2MB
        $result.PeakCopyConcurrency | Should -Be 1
        $result.PeakVerifyConcurrency | Should -Be 1
        $result.PeakConcurrency | Should -Be 1
        $result.ImportedFileCount | Should -Be 3
    }

    It 'moves files by same-volume rename without content hashing' -Skip:($env:OS -ne 'Windows_NT') {
        $sourceRoot = Join-Path $TestDrive 'move-source'
        $projectRoot = Join-Path $TestDrive 'move-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null
        $sourcePath = Join-Path $sourceRoot 'move.bin'
        [IO.File]::WriteAllBytes($sourcePath, (New-Object byte[] 128KB))

        Mock Get-RenderKitImportFileHashValue {
            throw 'Hashing must not run for same-volume moves.'
        }

        $classifiedFile = [PSCustomObject]@{
            Name                    = 'move.bin'
            FullName                = $sourcePath
            Length                  = [int64]128KB
            Classification          = 'Assigned'
            MappingId               = 'video'
            TypeName                = 'move'
            DestinationRelativePath = 'MEDIA'
            DestinationPath         = $destinationDirectory
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles @($classifiedFile) `
            -ProjectRoot $projectRoot `
            -SourceDisposition Move

        $transaction = $result.Transactions[0]
        $result.ImportedFileCount | Should -Be 1
        $result.SourceDisposition | Should -Be 'Move'
        $result.SameVolumeMoveFileCount | Should -Be 1
        $result.CopiedBytes | Should -Be 0
        $result.VerifiedBytes | Should -Be 0
        $result.ProcessedBytes | Should -Be 128KB
        $transaction.TransferMethod | Should -Be 'SameVolumeMove'
        $transaction.VerificationMode | Should -Be 'RenameIdentity'
        $transaction.HashAlgorithm | Should -BeNullOrEmpty
        $transaction.RollbackStatus | Should -Be 'NotRequired'
        Test-Path -LiteralPath $sourcePath -PathType Leaf | Should -BeFalse
        Test-Path -LiteralPath $transaction.DestinationPath -PathType Leaf | Should -BeTrue
        Should -Invoke Get-RenderKitImportFileHashValue -Times 0 -Exactly
    }

    It 'rolls a staged same-volume move back when final commit fails' -Skip:($env:OS -ne 'Windows_NT') {
        $sourceRoot = Join-Path $TestDrive 'rollback-source'
        $projectRoot = Join-Path $TestDrive 'rollback-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null
        $sourcePath = Join-Path $sourceRoot 'rollback.bin'
        [IO.File]::WriteAllBytes($sourcePath, (New-Object byte[] 64KB))

        Mock Move-Item {
            param(
                [string]$LiteralPath,
                [string]$Destination,
                $ErrorAction
            )

            if ($Destination -like (Join-Path $destinationDirectory '*')) {
                throw 'Intentional commit failure'
            }
            [IO.File]::Move($LiteralPath, $Destination)
        }

        $classifiedFile = [PSCustomObject]@{
            Name                    = 'rollback.bin'
            FullName                = $sourcePath
            Length                  = [int64]64KB
            Classification          = 'Assigned'
            MappingId               = 'video'
            TypeName                = 'move'
            DestinationRelativePath = 'MEDIA'
            DestinationPath         = $destinationDirectory
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles @($classifiedFile) `
            -ProjectRoot $projectRoot `
            -SourceDisposition Move

        $transaction = $result.Transactions[0]
        $result.ImportedFileCount | Should -Be 0
        $result.FailedFileCount | Should -Be 1
        $result.RolledBackFileCount | Should -Be 1
        $result.RollbackFailedFileCount | Should -Be 0
        $transaction.RollbackStatus | Should -Be 'Succeeded'
        $transaction.Error | Should -BeLike '*Intentional commit failure*'
        Test-Path -LiteralPath $sourcePath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $transaction.DestinationPath -PathType Leaf | Should -BeFalse
    }

    It 'preserves staging when commit and rollback both fail' -Skip:($env:OS -ne 'Windows_NT') {
        $sourceRoot = Join-Path $TestDrive 'rollback-failed-source'
        $projectRoot = Join-Path $TestDrive 'rollback-failed-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null
        $sourcePath = Join-Path $sourceRoot 'stranded.bin'
        [IO.File]::WriteAllBytes($sourcePath, (New-Object byte[] 64KB))

        Mock Move-Item {
            param(
                [string]$LiteralPath,
                [string]$Destination,
                $ErrorAction
            )

            if ($Destination -like (Join-Path $destinationDirectory '*')) {
                throw 'Intentional commit failure'
            }
            if ($Destination -eq $sourcePath -and $LiteralPath -like '*import-temp*') {
                throw 'Intentional rollback failure'
            }
            [IO.File]::Move($LiteralPath, $Destination)
        }

        $classifiedFile = [PSCustomObject]@{
            Name                    = 'stranded.bin'
            FullName                = $sourcePath
            Length                  = [int64]64KB
            Classification          = 'Assigned'
            MappingId               = 'video'
            TypeName                = 'move'
            DestinationRelativePath = 'MEDIA'
            DestinationPath         = $destinationDirectory
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles @($classifiedFile) `
            -ProjectRoot $projectRoot `
            -SourceDisposition Move

        $transaction = $result.Transactions[0]
        $result.RollbackFailedFileCount | Should -Be 1
        $transaction.RollbackStatus | Should -Be 'Failed'
        $transaction.RollbackError | Should -BeLike '*Intentional rollback failure*'
        Test-Path -LiteralPath $sourcePath -PathType Leaf | Should -BeFalse
        Test-Path -LiteralPath $transaction.StagingPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $result.TempRunRoot -PathType Container | Should -BeTrue
    }

    It 'rejects an explicit move when source and destination are not on one Windows volume' {
        $sourceRoot = Join-Path $TestDrive 'cross-volume-source'
        $projectRoot = Join-Path $TestDrive 'cross-volume-project'
        $destinationDirectory = Join-Path $projectRoot 'MEDIA'
        New-Item -ItemType Directory -Path $sourceRoot, $projectRoot -Force | Out-Null
        $sourcePath = Join-Path $sourceRoot 'cross-volume.bin'
        [IO.File]::WriteAllBytes($sourcePath, (New-Object byte[] 1KB))

        Mock Test-RenderKitImportSameVolume { return $false }

        $classifiedFile = [PSCustomObject]@{
            Name                    = 'cross-volume.bin'
            FullName                = $sourcePath
            Length                  = [int64]1KB
            Classification          = 'Assigned'
            MappingId               = 'image'
            TypeName                = 'move'
            DestinationRelativePath = 'MEDIA'
            DestinationPath         = $destinationDirectory
        }

        $result = Invoke-RenderKitImportTransactionSafeTransfer `
            -ClassifiedFiles @($classifiedFile) `
            -ProjectRoot $projectRoot `
            -SourceDisposition Move `
            -Simulate

        $result.ImportedFileCount | Should -Be 0
        $result.FailedFileCount | Should -Be 1
        $result.Transactions[0].Error | Should -BeLike '*requires source and destination on the same Windows volume*'
        Test-Path -LiteralPath $sourcePath -PathType Leaf | Should -BeTrue
    }
}
