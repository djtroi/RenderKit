Describe 'RenderKit backup process output bounds' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $securityPath = Join-Path `
            $repositoryRoot `
            'src/Private/Backup/ZZ-RenderKit.BackupProcessOutputSecurity.ps1'
        $script:SecuritySource = Get-Content -LiteralPath $securityPath -Raw
        . $securityPath
    }

    It 'uses bounded stdout stderr and progress storage without an encode timeout' {
        $script:SecuritySource | Should -Match 'maximumOutputLines = 2048'
        $script:SecuritySource | Should -Match 'maximumOutputCharacters = 1048576'
        $script:SecuritySource | Should -Match 'maximumErrorLines = 1024'
        $script:SecuritySource | Should -Match 'maximumErrorCharacters = 524288'
        $script:SecuritySource | Should -Match 'maximumProgressLogBytes = 1048576'
        $script:SecuritySource | Should -Match 'ReadLineAsync\(\)'
        $script:SecuritySource | Should -Not -Match 'ReadToEndAsync\(\)'
        $script:SecuritySource | Should -Not -Match 'TimeoutSeconds'
    }

    It 'returns only bounded diagnostic tails from a chatty process' {
        $hostPath = (Get-Process -Id $PID).Path
        $progressRoot = Join-Path $TestDrive 'chatty-progress'
        [void][System.IO.Directory]::CreateDirectory($progressRoot)
        $progressPath = Join-Path $progressRoot 'progress.log'
        $pidPath = Join-Path $progressRoot 'process.pid'
        $scriptText = @'
for ($i = 0; $i -lt 2200; $i++) {
    [Console]::Out.WriteLine(('out-{0}' -f $i))
}
for ($i = 0; $i -lt 1100; $i++) {
    [Console]::Error.WriteLine(('err-{0}' -f $i))
}
'@
        $command = [PSCustomObject]@{
            id = 'bounded-output-test'
            executable = $hostPath
            arguments = @(
                '-NoProfile',
                '-NonInteractive',
                '-Command',
                $scriptText
            )
            progress = [PSCustomObject]@{
                logPath = $progressPath
                pidPath = $pidPath
            }
        }

        $job = Start-BackupScheduledThreadJob -Command $command
        try {
            $result = @(Receive-Job -Job $job -Wait -ErrorAction Stop) |
                Select-Object -Last 1
        }
        finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }

        $result.exitCode | Should -Be 0
        @($result.output).Count | Should -BeLessOrEqual 2048
        @($result.error).Count | Should -BeLessOrEqual 1024
        $result.outputTruncated | Should -BeTrue
        $result.errorTruncated | Should -BeTrue
        $result.totalOutputLines | Should -Be 2200
        $result.totalErrorLines | Should -Be 1100
        (Get-Item -LiteralPath $progressPath).Length |
            Should -BeLessOrEqual 1048576
    }

    It 'caps a single hostile output line before retaining or logging it' {
        $script:SecuritySource | Should -Match 'maximumCapturedLineCharacters = 16384'
        $script:SecuritySource | Should -Match '\[line truncated\]'
    }
}
