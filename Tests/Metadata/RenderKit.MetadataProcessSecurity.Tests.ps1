Describe 'RenderKit metadata process security bounds' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $repositoryRoot 'RenderKit.psd1') -Force
        $processSecurityPath = Join-Path `
            $repositoryRoot `
            'src/Private/Metadata/RenderKit.MetadataProcessSecurityService.ps1'
        $script:ProcessSecuritySource = Get-Content -LiteralPath $processSecurityPath -Raw
        $script:ProcessIntegrationSource = Get-Content -LiteralPath (
            Join-Path $repositoryRoot 'src/Private/Metadata/RenderKit.ZMetadataProcessSecurityIntegration.ps1'
        ) -Raw
        # Exercise the isolated helper directly in this Pester scope. InModuleScope
        # can wrap private-function output differently across Pester/PowerShell
        # versions, which obscures the lifecycle result this regression checks.
        . $processSecurityPath
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'defines finite timeout and stdout/stderr limits for metadata subprocesses' {
        $script:ProcessSecuritySource | Should -Match 'TimeoutSeconds = 120'
        $script:ProcessSecuritySource | Should -Match 'MaximumStandardOutputBytes = 32MB'
        $script:ProcessSecuritySource | Should -Match 'MaximumStandardErrorBytes = 8MB'
        $script:ProcessSecuritySource | Should -Match 'WaitForExit\(50\)'
        $script:ProcessSecuritySource | Should -Match 'Kill\(\$true\)'
    }

    It 'drains redirected streams outside PowerShell event callbacks' {
        $script:ProcessSecuritySource | Should -Match 'StandardOutput\.BaseStream\.CopyToAsync'
        $script:ProcessSecuritySource | Should -Match 'StandardError\.BaseStream\.CopyToAsync'
        $script:ProcessSecuritySource | Should -Not -Match 'BeginOutputReadLine'
        $script:ProcessSecuritySource | Should -Not -Match 'OutputDataReceived'
    }

    It 'closes completed capture streams before reopening their files' {
        $hostPath = (Get-Process -Id $PID).Path
        $result = Invoke-RenderKitBoundedMetadataProcess `
            -FilePath $hostPath `
            -Arguments @(
                '-NoProfile',
                '-NonInteractive',
                '-Command',
                "[Console]::Out.Write('bounded-ok')"
            ) `
            -TimeoutSeconds 30

        $result.ExitCode | Should -Be 0
        $result.StandardOutput | Should -Be 'bounded-ok'
    }

    It 'routes all external metadata adapters through the bounded process runner' {
        $script:ProcessIntegrationSource | Should -Match 'function Invoke-RenderKitExifToolCandidate'
        $script:ProcessIntegrationSource | Should -Match 'function Invoke-RenderKitMediaInfoHostMetadataRead'
        $script:ProcessIntegrationSource | Should -Match 'function Invoke-RenderKitMediaInfoCliMetadataRead'
        $script:ProcessIntegrationSource | Should -Match 'function Invoke-RenderKitMkvToolNixApplication'
        ([regex]::Matches(
            $script:ProcessIntegrationSource,
            'Invoke-RenderKitBoundedMetadataProcess'
        )).Count | Should -BeGreaterOrEqual 4
    }

    It 'monitors extracted Matroska metadata files while mkvextract is running' {
        $script:ProcessIntegrationSource | Should -Match '-MonitoredPath @\(\$tagsPath\)'
        $script:ProcessIntegrationSource | Should -Match '-MonitoredPath @\(\$chaptersPath\)'
        $script:ProcessIntegrationSource | Should -Match 'MaximumMonitoredFileBytes 64MB'
    }

    It 'rejects oversized MKVToolNix XML before constructing an XML DOM' {
        $xmlPath = Join-Path $TestDrive 'large-tags.xml'
        $payload = '<Tags><Tag><Simple><Name>TITLE</Name><String>' +
            ('x' * 4096) +
            '</String></Simple></Tag></Tags>'
        [System.IO.File]::WriteAllText($xmlPath, $payload)

        {
            InModuleScope RenderKit -Parameters @{ XmlPath = $xmlPath } {
                Read-RenderKitMkvToolNixXmlDocument `
                    -Path $XmlPath `
                    -RootName Tags `
                    -MaximumBytes 1024
            }
        } | Should -Throw '*exceeds the 1024 byte limit*'
    }

    It 'keeps DTD resolution disabled and bounds XML document characters' {
        $script:ProcessIntegrationSource | Should -Match 'DtdProcessing = \[Xml\.DtdProcessing\]::Prohibit'
        $script:ProcessIntegrationSource | Should -Match 'XmlResolver = \$null'
        $script:ProcessIntegrationSource | Should -Match 'MaxCharactersInDocument = \$MaximumBytes'
        $script:ProcessIntegrationSource | Should -Match 'MaxCharactersFromEntities = 0'
    }
}