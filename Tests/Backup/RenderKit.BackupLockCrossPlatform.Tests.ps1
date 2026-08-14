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
}
