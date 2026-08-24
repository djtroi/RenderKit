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
        if (Test-Path -LiteralPath $script:testRoot) {
            Remove-Item -LiteralPath $script:testRoot -Recurse -Force
        }
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

    It 'reads valid JSON without PowerShell provider Force access' {
        Set-Content `
            -LiteralPath $script:jsonPath `
            -Value '{"Name":"PackagedResource","Version":1}' `
            -Encoding UTF8

        Mock Get-Item {
            throw [System.UnauthorizedAccessException]::new(
                'Provider access should not be required.')
        }
        Mock Get-Content {
            throw [System.UnauthorizedAccessException]::new(
                'Provider access should not be required.')
        }

        $value = Read-RenderKitJsonFile -Path $script:jsonPath

        $value.Name | Should -Be 'PackagedResource'
        $value.Version | Should -Be 1
    }

    It 'keeps filesystem access failures distinct from invalid JSON' {
        [System.IO.File]::WriteAllText($script:jsonPath, '{"Version":1}')
        $originalTextReader = (Get-Item Function:\Read-RenderKitTextFile).ScriptBlock
        try {
            Set-Item `
                -Path Function:\Read-RenderKitTextFile `
                -Value {
                    param(
                        [string]$Path,
                        [long]$MaximumBytes
                    )
                    throw [System.UnauthorizedAccessException]::new(
                        'Access denied.')
                }

            {
                Read-RenderKitJsonFile `
                    -Path $script:jsonPath `
                    -ReadRetryCount 0
            } | Should -Throw '*Unable to read JSON file*Access denied*'
        }
        finally {
            Set-Item `
                -Path Function:\Read-RenderKitTextFile `
                -Value $originalTextReader
        }
    }

    It 'reports malformed content as invalid JSON' {
        Set-Content `
            -LiteralPath $script:jsonPath `
            -Value '{invalid' `
            -Encoding UTF8

        {
            Read-RenderKitJsonFile -Path $script:jsonPath
        } | Should -Throw '*Invalid JSON*'
    }

    It 'validates atomic JSON through a hidden sibling path' {
        $hiddenPath = Join-Path $script:testRoot '.metadata.json'
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Kind = 'Hidden' }) `
            -Path $hiddenPath |
            Out-Null

        $value = Read-RenderKitJsonFile -Path $hiddenPath
        $value.Kind | Should -Be 'Hidden'
    }

    It 'retries transient filesystem read failures before succeeding' {
        [System.IO.File]::WriteAllText($script:jsonPath, '{"Version":2}')
        $originalTextReader = (Get-Item Function:\Read-RenderKitTextFile).ScriptBlock
        $script:readAttempts = 0
        try {
            Set-Item `
                -Path Function:\Read-RenderKitTextFile `
                -Value {
                    param(
                        [string]$Path,
                        [long]$MaximumBytes
                    )
                    $script:readAttempts++
                    if ($script:readAttempts -lt 3) {
                        throw [System.IO.IOException]::new(
                            'Temporary replacement window.')
                    }
                    return '{"Version":2}'
                }

            $value = Read-RenderKitJsonFile `
                -Path $script:jsonPath `
                -ReadRetryCount 2 `
                -ReadRetryMilliseconds 1

            $value.Version | Should -Be 2
            $script:readAttempts | Should -Be 3
        }
        finally {
            Set-Item `
                -Path Function:\Read-RenderKitTextFile `
                -Value $originalTextReader
        }
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

        $backupPath = "$($script:jsonPath).bak"
        Test-Path -LiteralPath $backupPath | Should -BeTrue
        (Read-RenderKitJsonFile -Path $backupPath).Version | Should -Be 1
        (Read-RenderKitJsonFile -Path $script:jsonPath).Version | Should -Be 2
    }

    It 'does not replace the current file when validation fails' {
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Version = 1 }) `
            -Path $script:jsonPath |
            Out-Null
        $validator = {
            param($value)
            [int]$value.Version -lt 2
        }

        {
            Write-RenderKitJsonFileAtomic `
                -Value ([PSCustomObject]@{ Version = 2 }) `
                -Path $script:jsonPath `
                -Validator $validator |
                Out-Null
        } | Should -Throw '*validation failed*'

        (Read-RenderKitJsonFile -Path $script:jsonPath).Version |
            Should -Be 1
    }

    It 'times out while another handle owns the file lock' {
        Set-Content `
            -LiteralPath $script:jsonPath `
            -Value '{"Version":1}' `
            -Encoding UTF8
        $lockPath = "$($script:jsonPath).lock"
        $otherHandle = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        try {
            {
                Write-RenderKitJsonFileAtomic `
                    -Value ([PSCustomObject]@{ Version = 2 }) `
                    -Path $script:jsonPath `
                    -LockTimeoutMilliseconds 100 |
                    Out-Null
            } | Should -Throw '*Timed out*file lock*'
        }
        finally {
            $otherHandle.Dispose()
        }
    }

    It 'updates the latest value inside one locked transaction' {
        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Count = 1 }) `
            -Path $script:jsonPath |
            Out-Null

        $updated = Invoke-RenderKitJsonFileTransaction `
            -Path $script:jsonPath `
            -DefaultValue ([PSCustomObject]@{ Count = 0 }) `
            -Update {
                param($value)
                $value.Count = [int]$value.Count + 1
                return $value
            }

        $updated.Count | Should -Be 2
        (Read-RenderKitJsonFile -Path $script:jsonPath).Count |
            Should -Be 2
    }

    It 'creates a missing file from the transaction default value' {
        $updated = Invoke-RenderKitJsonFileTransaction `
            -Path $script:jsonPath `
            -DefaultValue ([PSCustomObject]@{ Count = 0 }) `
            -Update {
                param($value)
                $value.Count = [int]$value.Count + 1
                return $value
            }

        $updated.Count | Should -Be 1
        Test-Path -LiteralPath $script:jsonPath | Should -BeTrue
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
        (Read-RenderKitJsonFile -Path "$($script:jsonPath).bak").Version |
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
        Set-Content `
            -LiteralPath $script:jsonPath `
            -Value '{invalid' `
            -Encoding UTF8

        Write-RenderKitJsonFileAtomic `
            -Value ([PSCustomObject]@{ Version = 3 }) `
            -Path $script:jsonPath |
            Out-Null

        (Read-RenderKitJsonFile -Path "$($script:jsonPath).bak").Version |
            Should -Be 1
        (Read-RenderKitJsonFile -Path $script:jsonPath).Version |
            Should -Be 3
    }

    It 'rejects files larger than the configured read limit' {
        $content = '{"Payload":"' + ('x' * 2048) + '"}'
        [System.IO.File]::WriteAllText($script:jsonPath, $content)

        {
            Read-RenderKitJsonFile `
                -Path $script:jsonPath `
                -MaximumBytes 128 `
                -ReadRetryCount 0
        } | Should -Throw '*exceeds the 128 byte limit*'
    }

    It 'returns null for an allowed missing file' {
        Read-RenderKitJsonFile `
            -Path $script:jsonPath `
            -AllowMissing |
            Should -BeNullOrEmpty
    }
}
