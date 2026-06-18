BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot `
        'src/Private/Storage/RenderKit.StorageService.ps1')
    . (Join-Path $repositoryRoot `
        'src/Private/Storage/RenderKit.PersistenceService.ps1')
}

Describe 'RenderKit JSON persistence service' {
    BeforeEach {
        $script:testRoot = Join-Path $TestDrive 'persistence'
        New-Item -ItemType Directory -Path $script:testRoot -Force |
            Out-Null
        $script:jsonPath = Join-Path $script:testRoot 'state.json'
    }

    It 'writes UTF-8 JSON and reads it back' {
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Name = 'RenderKit'; Version = 1 }) `
            -Path $script:jsonPath |
            Out-Null

        $value = Read-RenderKitJsonFile -Path $script:jsonPath
        $value.Name | Should -Be 'RenderKit'
        $value.Version | Should -Be 1
        $bytes = [System.IO.File]::ReadAllBytes($script:jsonPath)
        $bytes[0] | Should -Be 0x7B
    }

    It 'preserves the previous valid file as a backup' {
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Version = 1 }) `
            -Path $script:jsonPath |
            Out-Null
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Version = 2 }) `
            -Path $script:jsonPath |
            Out-Null

        (Read-RenderKitJsonFile -Path $script:jsonPath).Version |
            Should -Be 2
        (Read-RenderKitJsonFile -Path "$script:jsonPath.bak").Version |
            Should -Be 1
    }

    It 'does not replace the current file when validation fails' {
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Version = 1 }) `
            -Path $script:jsonPath |
            Out-Null

        {
            Write-RenderKitJsonFileAtomic `
                -Value ([PSCustomObject]@{ Version = 2 }) `
                -Path $script:jsonPath `
                -Validator {
                    param($value)
                    return $value.Version -lt 2
                }
        } | Should -Throw

        (Read-RenderKitJsonFile -Path $script:jsonPath).Version |
            Should -Be 1
        @(Get-ChildItem -LiteralPath $script:testRoot -Filter '*.tmp.*') |
            Should -HaveCount 0
    }

    It 'times out while another handle owns the file lock' {
        $firstLock = Enter-RenderKitFileLock -Path $script:jsonPath
        try {
            {
                Enter-RenderKitFileLock `
                    -Path $script:jsonPath `
                    -TimeoutMilliseconds 100 `
                    -RetryMilliseconds 20
            } | Should -Throw '*Timed out*'
        }
        finally {
            Exit-RenderKitFileLock -LockHandle $firstLock
        }
    }

    It 'updates the latest value inside one locked transaction' {
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Counter = 1 }) `
            -Path $script:jsonPath |
            Out-Null

        $updated = Invoke-RenderKitJsonFileTransaction `
            -Path $script:jsonPath `
            -DefaultValue ([PSCustomObject]@{ Counter = 0 }) `
            -Update {
                param($current)
                $current.Counter++
                return $current
            }

        $updated.Counter | Should -Be 2
        (Read-RenderKitJsonFile -Path $script:jsonPath).Counter |
            Should -Be 2
    }

    It 'creates a missing file from the transaction default value' {
        $updated = Invoke-RenderKitJsonFileTransaction `
            -Path $script:jsonPath `
            -DefaultValue ([PSCustomObject]@{ Counter = 0 }) `
            -Update {
                param($current)
                $current.Counter = 1
                return $current
            }

        $updated.Counter | Should -Be 1
        Test-Path -LiteralPath $script:jsonPath -PathType Leaf |
            Should -BeTrue
    }

    It 'restores the last backup without replacing the backup' {
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Version = 1 }) `
            -Path $script:jsonPath |
            Out-Null
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Version = 2 }) `
            -Path $script:jsonPath |
            Out-Null

        Restore-RenderKitJsonFileBackup -Path $script:jsonPath |
            Out-Null

        (Read-RenderKitJsonFile -Path $script:jsonPath).Version |
            Should -Be 1
        (Read-RenderKitJsonFile -Path "$script:jsonPath.bak").Version |
            Should -Be 1
    }

    It 'does not replace a valid backup with a corrupt current file' {
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Version = 1 }) `
            -Path $script:jsonPath |
            Out-Null
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Version = 2 }) `
            -Path $script:jsonPath |
            Out-Null
        Set-Content -LiteralPath $script:jsonPath -Value '{invalid'

        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Version = 3 }) `
            -Path $script:jsonPath |
            Out-Null

        (Read-RenderKitJsonFile -Path $script:jsonPath).Version |
            Should -Be 3
        (Read-RenderKitJsonFile -Path "$script:jsonPath.bak").Version |
            Should -Be 1
    }

    It 'rejects files larger than the configured read limit' {
        Set-Content -LiteralPath $script:jsonPath -Value '{"value":12345}'

        {
            Read-RenderKitJsonFile `
                -Path $script:jsonPath `
                -MaximumBytes 4
        } | Should -Throw '*exceeds*'
    }

    It 'returns null for an allowed missing file' {
        Read-RenderKitJsonFile `
            -Path $script:jsonPath `
            -AllowMissing |
            Should -BeNullOrEmpty
    }
}
