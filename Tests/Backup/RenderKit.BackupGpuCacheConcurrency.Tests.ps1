BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $modulePath = Join-Path $repositoryRoot 'RenderKit.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
}

Describe 'RenderKit GPU capability cache concurrency' {
    It 'serializes concurrent cross-process cache writers' {
        $testRoot = Join-Path $TestDrive 'gpu-cache-concurrency'
        $cachePath = Join-Path $testRoot 'gpu-capabilities.json'
        $startPath = Join-Path $testRoot 'start.signal'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

        $jobScript = {
            param(
                [string]$ModulePath,
                [string]$CachePath,
                [string]$ReadyPath,
                [string]$StartPath,
                [int]$WriterId
            )

            Import-Module $ModulePath -Force
            try {
                New-Item -ItemType File -Path $ReadyPath -Force | Out-Null
                $deadline = [DateTime]::UtcNow.AddSeconds(30)
                while (-not (Test-Path -LiteralPath $StartPath)) {
                    if ([DateTime]::UtcNow -ge $deadline) {
                        throw 'Timed out waiting for the concurrent cache write signal.'
                    }
                    Start-Sleep -Milliseconds 20
                }

                $module = Get-Module RenderKit
                & $module {
                    param($TargetPath, $Id)

                    $now = [DateTime]::UtcNow
                    $report = [PSCustomObject]@{
                        schemaVersion = '1.1'
                        source = "Writer$Id"
                        detectedAtUtc = $now.ToString('o')
                        expiresAtUtc = $now.AddHours(1).ToString('o')
                        cache = [PSCustomObject]@{
                            enabled = $true
                            path = $TargetPath
                            ttlHours = 1
                            source = "Writer$Id"
                        }
                    }

                    Save-BackupGpuCapabilityCache `
                        -Report $report `
                        -Path $TargetPath |
                        Out-Null
                } $CachePath $WriterId
            }
            finally {
                Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
            }
        }

        $jobs = @(
            foreach ($writerId in 1..2) {
                $readyPath = Join-Path $testRoot "ready-$writerId.signal"
                Start-Job `
                    -ScriptBlock $jobScript `
                    -ArgumentList @(
                        $modulePath,
                        $cachePath,
                        $readyPath,
                        $startPath,
                        $writerId
                    )
            }
        )

        try {
            $readyDeadline = [DateTime]::UtcNow.AddSeconds(30)
            do {
                $readyCount = @(
                    Get-ChildItem `
                        -LiteralPath $testRoot `
                        -Filter 'ready-*.signal' `
                        -File `
                        -ErrorAction SilentlyContinue
                ).Count
                if ($readyCount -ge 2) {
                    break
                }
                if ([DateTime]::UtcNow -ge $readyDeadline) {
                    throw 'Timed out waiting for concurrent cache writers to become ready.'
                }
                Start-Sleep -Milliseconds 20
            } while ($true)

            New-Item -ItemType File -Path $startPath -Force | Out-Null
            $completed = @($jobs | Wait-Job -Timeout 30)
            $completed.Count | Should -Be 2

            foreach ($job in $jobs) {
                $job.State | Should -Be 'Completed'
                { Receive-Job -Job $job -ErrorAction Stop | Out-Null } |
                    Should -Not -Throw
            }
        }
        finally {
            $jobs |
                Remove-Job -Force -ErrorAction SilentlyContinue
        }

        $cached = InModuleScope RenderKit -Parameters @{
            CachePath = $cachePath
        } {
            Read-BackupGpuCapabilityCache `
                -Path $CachePath `
                -AllowExpired
        }

        $cached | Should -Not -BeNullOrEmpty
        $cached.schemaVersion | Should -Be '1.1'
        $cached.cache.source | Should -Be 'Cache'
    }
}
