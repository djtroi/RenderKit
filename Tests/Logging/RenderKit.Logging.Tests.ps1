Describe 'RenderKit logging' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repositoryRoot 'src/Private/Logging/Write-RenderKitLog.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Logging/Initialize-RenderKitLogging.ps1')
        . (Join-Path $repositoryRoot 'src/Private/Logging/Clear-RenderKitLoggingState.ps1')

        function Invoke-RenderKitLogRetention {
        }
    }

    BeforeEach {
        $script:RenderKitLoggingInitialized = $false
        $script:RenderKitBootstrapLog = $null
        $script:RenderKitLogFile = $null
        $script:RenderKitDebugLogFile = $null
        $script:RenderKitDebugMode = $false
    }

    AfterEach {
        Clear-RenderKitLoggingState
        $script:RenderKitBootstrapLog = $null
    }

    It 'recreates a missing project log file before writing' {
        $projectRoot = Join-Path $TestDrive 'ProjectA'
        $renderKitRoot = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $renderKitRoot -Force | Out-Null
        Initialize-RenderKitLogging -ProjectRoot $projectRoot
        Remove-Item -LiteralPath (Join-Path $renderKitRoot 'renderkit.log') -Force

        { Write-RenderKitLog -Level Info -Message 'Removing project.' -NoConsole } |
            Should -Not -Throw

        $logPath = Join-Path $renderKitRoot 'renderkit.log'
        Test-Path -LiteralPath $logPath -PathType Leaf | Should -BeTrue
        Get-Content -LiteralPath $logPath | Should -Match 'Removing project.'
    }
}