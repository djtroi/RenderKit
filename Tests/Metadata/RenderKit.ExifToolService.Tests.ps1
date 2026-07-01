Describe 'RenderKit ExifTool resolver and runtime' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:RepositoryRoot 'RenderKit.psd1') -Force
        $script:RenderKitModule = Get-Module RenderKit
    }

    AfterEach {
        Remove-Item Env:RENDERKIT_EXIFTOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:RENDERKIT_EXIFTOOL_HOST -ErrorAction SilentlyContinue
        Remove-Item Env:RENDERKIT_EXIFTOOL_PERL -ErrorAction SilentlyContinue
        InModuleScope -ModuleName RenderKit -ScriptBlock {
            $script:RenderKitExifToolBundleManifest = $null
            $script:RenderKitExifToolBundleManifestPath = $null
        }
    }

    It 'maps supported platforms and architectures to ExifTool bundle RIDs' {
        $rids = InModuleScope -ModuleName RenderKit -ScriptBlock {
            [PSCustomObject]@{
                WinX86 = ConvertTo-RenderKitExifToolRuntimeIdentifier `
                    -OperatingSystem 'Windows' `
                    -Architecture 'I386'
                WinX64 = ConvertTo-RenderKitExifToolRuntimeIdentifier `
                    -OperatingSystem 'Win32NT' `
                    -Architecture 'AMD64'
                WinArm64 = ConvertTo-RenderKitExifToolRuntimeIdentifier `
                    -OperatingSystem 'Windows' `
                    -Architecture 'Aarch64'
                MacX64 = ConvertTo-RenderKitExifToolRuntimeIdentifier `
                    -OperatingSystem 'Darwin' `
                    -Architecture 'x86_64'
                MacArm64 = ConvertTo-RenderKitExifToolRuntimeIdentifier `
                    -OperatingSystem 'macOS' `
                    -Architecture 'ARM64'
                LinuxX64 = ConvertTo-RenderKitExifToolRuntimeIdentifier `
                    -OperatingSystem 'Linux' `
                    -Architecture 'X64'
                LinuxArm64 = ConvertTo-RenderKitExifToolRuntimeIdentifier `
                    -OperatingSystem 'Unix' `
                    -Architecture 'Arm64'
            }
        }

        $rids.WinX86 | Should -Be 'win-x86'
        $rids.WinX64 | Should -Be 'win-x64'
        $rids.WinArm64 | Should -Be 'win-arm64'
        $rids.MacX64 | Should -Be 'osx-x64'
        $rids.MacArm64 | Should -Be 'osx-arm64'
        $rids.LinuxX64 | Should -Be 'linux-x64'
        $rids.LinuxArm64 | Should -Be 'linux-arm64'
    }

    It 'ships every declared ExifTool payload file with the recorded hash' {
        $bundleRoot = Join-Path `
            -Path $script:RepositoryRoot `
            -ChildPath 'src/Resources/ThirdParty/ExifTool'
        $manifest = Get-Content `
            -LiteralPath (Join-Path $bundleRoot 'manifest.json') `
            -Raw |
            ConvertFrom-Json

        $manifest.componentVersion | Should -Be '13.59'
        foreach ($runtime in @($manifest.runtimeIdentifiers)) {
            if (-not [bool]$runtime.bundled) {
                [string]$runtime.commandRelativePath | Should -BeNullOrEmpty
                continue
            }

            $commandPath = Join-Path `
                -Path $bundleRoot `
                -ChildPath ([string]$runtime.commandRelativePath)
            $commandPath | Should -Exist
            (Get-FileHash -LiteralPath $commandPath -Algorithm SHA256).Hash |
                Should -Be ([string]$runtime.commandSha256)
        }

        $hashLines = Get-Content -LiteralPath (Join-Path $bundleRoot 'files.sha256')
        $hashLines.Count | Should -BeGreaterThan 1200
        foreach ($line in $hashLines) {
            $match = [regex]::Match($line, '^([a-f0-9]{64})  (.+)$')
            $match.Success | Should -BeTrue
            $expectedHash = $match.Groups[1].Value
            $relativePath = $match.Groups[2].Value
            $payloadPath = Join-Path $bundleRoot $relativePath
            $payloadPath | Should -Exist
            (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash |
                Should -Be $expectedHash
        }

        (Join-Path $bundleRoot 'licenses/ExifTool-README.txt') | Should -Exist
        (Join-Path $bundleRoot 'licenses/Perl-Artistic.txt') | Should -Exist
        (Join-Path $bundleRoot 'licenses/Perl-Copying.txt') | Should -Exist
        (Join-Path $bundleRoot 'win-x64/exiftool_files/Licenses_Strawberry_Perl.zip') |
            Should -Exist
        (Join-Path $bundleRoot 'win-x86/exiftool_files/Licenses_Strawberry_Perl.zip') |
            Should -Exist
    }

    It 'prefers an explicitly configured ExifTool over the bundled runtime' {
        $configuredPath = Join-Path $TestDrive 'custom-exiftool'
        Set-Content -LiteralPath $configuredPath -Value 'fake executable' -Encoding ASCII
        $env:RENDERKIT_EXIFTOOL_PATH = $configuredPath

        $resolved = InModuleScope -ModuleName RenderKit -ScriptBlock {
            Resolve-RenderKitExifToolReader
        }

        $resolved.Available | Should -BeTrue
        $resolved.Mode | Should -Be 'Cli'
        $resolved.Source | Should -Be 'Environment'
        $resolved.CommandPath | Should -Be ([System.IO.Path]::GetFullPath($configuredPath))
    }

    It 'resolves the bundled runtime for the current supported RID' {
        $resolved = InModuleScope -ModuleName RenderKit -ScriptBlock {
            Resolve-RenderKitExifToolReader
        }
        $runtime = InModuleScope -ModuleName RenderKit -ScriptBlock {
            Get-RenderKitExifToolBundleRuntime
        }

        if (-not $runtime -or -not [bool]$runtime.bundled) {
            Set-ItResult -Skipped -Because 'The current RID intentionally has no bundled ExifTool runtime.'
            return
        }

        $bundleCandidate = @(
            $resolved.Candidates |
                Where-Object { [string]$_.Source -eq 'Bundled' } |
                Select-Object -First 1
        )
        $bundleCandidate | Should -Not -BeNullOrEmpty
        if ([string]$runtime.bundleKind -eq 'PerlScript' -and
            -not [bool]$bundleCandidate.Available) {
            $bundleCandidate.UnavailableReason | Should -Be 'PerlNotAvailable'
            return
        }

        $resolved.Available | Should -BeTrue
        $resolved.Source | Should -Be 'Bundled'
        $bundleCandidate.Available | Should -BeTrue
    }

    It 'fails over from bundled CLI to the configured metadata host' {
        InModuleScope -ModuleName RenderKit -ScriptBlock {
            Mock Invoke-RenderKitExifToolCandidate {
                param($Candidate)
                if ([string]$Candidate.Source -eq 'Bundled') {
                    throw 'bundled runtime failed'
                }
                return @('host output')
            }

            $reader = [PSCustomObject]@{
                Candidates = @(
                    [PSCustomObject]@{
                        Kind = 'Cli'
                        Source = 'Bundled'
                        Path = 'bundled-exiftool'
                        PrefixArguments = @()
                        PayloadPath = $null
                        Available = $true
                    },
                    [PSCustomObject]@{
                        Kind = 'Host'
                        Source = 'Environment'
                        Path = 'metadata-host'
                        PrefixArguments = @('exiftool', 'run', '--')
                        PayloadPath = $null
                        Available = $true
                    }
                )
            }

            $result = Invoke-RenderKitExifToolCommand `
                -Reader $reader `
                -Arguments @('-ver')

            $result.Backend | Should -Be 'Host'
            $result.Source | Should -Be 'Environment'
            $result.Output | Should -Contain 'host output'
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] |
                Should -Match 'cli/Bundled failed: bundled runtime failed'
        }
    }

    It 'reads and writes metadata through the resolved ExifTool runtime' {
        $resolved = InModuleScope -ModuleName RenderKit -ScriptBlock {
            Resolve-RenderKitExifToolReader
        }
        if (-not [bool]$resolved.Available) {
            Set-ItResult -Skipped -Because 'No ExifTool runtime is available on this test host.'
            return
        }

        $samplePath = Join-Path $TestDrive 'roundtrip.png'
        $pngBytes = [Convert]::FromBase64String(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
        )
        [System.IO.File]::WriteAllBytes($samplePath, $pngBytes)

        $write = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $samplePath } `
            -ScriptBlock {
                param($Path)
                Invoke-RenderKitEmbeddedMetadataWrite `
                    -Path $Path `
                    -Metadata ([ordered]@{ Rating = 4 })
            }
        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $samplePath } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path -IncludeRaw
            }

        $write.Status | Should -Be 'Written'
        $write.Backend | Should -BeIn @('Cli', 'Host')
        $read.Fields.Rating | Should -Be 4
        $read.Warnings | Should -BeNullOrEmpty
        $read.Raw.ExifToolBackend.Source | Should -Not -BeNullOrEmpty
        (Test-Path -LiteralPath "${samplePath}_original") | Should -BeFalse
    }
}
