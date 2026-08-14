Describe 'RenderKit backup lock cross-platform ownership' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -Force
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'builds the lock path from portable path segments' {
        $projectRoot = Join-Path $TestDrive 'portable-path-project'
        $result = InModuleScope RenderKit -Parameters @{
            ProjectRoot = $projectRoot
        } {
            [PSCustomObject]@{
                actual = Get-BackupLockPath -ProjectRoot $ProjectRoot
                expected = Join-Path `
                    -Path (Join-Path -Path $ProjectRoot -ChildPath '.renderkit') `
                    -ChildPath 'backup.lock'
                definition = (Get-Command Get-BackupLockPath).Definition
            }
        }

        $result.actual | Should -Be $result.expected
        $result.definition | Should -Not -Match '\.renderkit\\backup\.lock'
    }

    It 'writes a portable machine and user identity into new locks' {
        $projectRoot = Join-Path $TestDrive 'portable-lock-project'
        New-Item `
            -ItemType Directory `
            -Path (Join-Path $projectRoot '.renderkit') `
            -Force |
            Out-Null

        $result = InModuleScope RenderKit -Parameters @{
            ProjectRoot = $projectRoot
        } {
            $handle = Get-BackupLock -ProjectRoot $ProjectRoot
            try {
                Get-Content -LiteralPath $handle.LockPath -Raw |
                    ConvertFrom-Json
            }
            finally {
                Remove-Item `
                    -LiteralPath $handle.LockPath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }

        $result.machine | Should -Be ([System.Environment]::MachineName)
        $result.user | Should -Be ([System.Environment]::UserName)
    }

    It 'does not use a foreign PID to expire a fresh legacy lock without machine identity' {
        $projectRoot = Join-Path $TestDrive 'legacy-shared-lock-project'
        New-Item `
            -ItemType Directory `
            -Path (Join-Path $projectRoot '.renderkit') `
            -Force |
            Out-Null

        $result = InModuleScope RenderKit -Parameters @{
            ProjectRoot = $projectRoot
        } {
            $lockPath = Get-BackupLockPath -ProjectRoot $ProjectRoot
            [PSCustomObject]@{
                lockType  = 'backup'
                lockedAt  = (Get-Date).ToUniversalTime().ToString('o')
                processId = 2147483647
                machine   = $null
            } |
                ConvertTo-Json |
                Set-Content -LiteralPath $lockPath -Encoding UTF8

            Test-BackupLock `
                -ProjectRoot $ProjectRoot `
                -StaleThreshold (New-TimeSpan -Hours 24)
        }

        $result.Exists | Should -BeTrue
        $result.IsLocked | Should -BeTrue
        $result.IsStale | Should -BeFalse
    }

    It 'still expires a local lock whose owning process no longer exists' {
        $projectRoot = Join-Path $TestDrive 'local-stale-lock-project'
        New-Item `
            -ItemType Directory `
            -Path (Join-Path $projectRoot '.renderkit') `
            -Force |
            Out-Null

        $result = InModuleScope RenderKit -Parameters @{
            ProjectRoot = $projectRoot
        } {
            $lockPath = Get-BackupLockPath -ProjectRoot $ProjectRoot
            [PSCustomObject]@{
                lockType  = 'backup'
                lockedAt  = (Get-Date).ToUniversalTime().ToString('o')
                processId = 2147483647
                machine   = [System.Environment]::MachineName
            } |
                ConvertTo-Json |
                Set-Content -LiteralPath $lockPath -Encoding UTF8

            Test-BackupLock -ProjectRoot $ProjectRoot
        }

        $result.IsLocked | Should -BeFalse
        $result.IsStale | Should -BeTrue
    }

    It 'takes over the same observed stale lock without a remove-create window' {
        $projectRoot = Join-Path $TestDrive 'stale-takeover-project'
        New-Item `
            -ItemType Directory `
            -Path (Join-Path $projectRoot '.renderkit') `
            -Force |
            Out-Null

        $result = InModuleScope RenderKit -Parameters @{
            ProjectRoot = $projectRoot
        } {
            $lockPath = Get-BackupLockPath -ProjectRoot $ProjectRoot
            $previousToken = [guid]::NewGuid().ToString()
            [PSCustomObject]@{
                lockType   = 'backup'
                lockedAt   = (Get-Date).ToUniversalTime().AddHours(-1).ToString('o')
                ownerToken = $previousToken
                processId  = 2147483647
                machine    = [System.Environment]::MachineName
            } |
                ConvertTo-Json |
                Set-Content -LiteralPath $lockPath -Encoding UTF8

            $handle = Get-BackupLock -ProjectRoot $ProjectRoot
            try {
                $current = Get-Content -LiteralPath $lockPath -Raw |
                    ConvertFrom-Json
                [PSCustomObject]@{
                    previousToken = $previousToken
                    handleToken = $handle.OwnerToken
                    persistedToken = [string]$current.ownerToken
                    definition = (Get-Command Get-BackupLock).Definition
                }
            }
            finally {
                Unlock-BackupLock `
                    -ProjectRoot $ProjectRoot `
                    -OwnerToken $handle.OwnerToken |
                    Out-Null
            }
        }

        $result.persistedToken | Should -Be $result.handleToken
        $result.persistedToken | Should -Not -Be $result.previousToken
        $result.definition | Should -Match 'same handle'
        $result.definition | Should -Not -Match 'Remove-Item\s+-Path\s+\$lockPath'
    }
}
