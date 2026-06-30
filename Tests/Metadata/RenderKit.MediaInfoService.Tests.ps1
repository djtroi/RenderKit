Describe 'RenderKit MediaInfo resolver and normalization' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:RepositoryRoot 'RenderKit.psd1') -Force
        $script:RenderKitModule = Get-Module RenderKit
    }

    AfterEach {
        Remove-Item Env:RENDERKIT_MEDIAINFO_LIBRARY -ErrorAction SilentlyContinue
        Remove-Item Env:RENDERKIT_MEDIAINFO_HOST -ErrorAction SilentlyContinue
        Remove-Item Env:RENDERKIT_MEDIAINFO_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:RENDERKIT_MEDIAINFO_DISABLE_SYSTEM_NATIVE -ErrorAction SilentlyContinue
        InModuleScope -ModuleName RenderKit -Parameters @{ RepositoryRoot = $script:RepositoryRoot } -ScriptBlock {
            param($RepositoryRoot)
            $script:RenderKitModuleRoot = $RepositoryRoot
            $script:RenderKitMediaInfoBundleManifest = $null
            $script:RenderKitMediaInfoBundleManifestPath = $null
        }
    }

    It 'maps supported platforms and architectures to MediaInfo bundle RIDs' {
        $rids = InModuleScope -ModuleName RenderKit -ScriptBlock {
            [PSCustomObject]@{
                WinX64 = ConvertTo-RenderKitMediaInfoRuntimeIdentifier `
                    -OperatingSystem 'Windows' `
                    -Architecture 'X64'
                WinArm64 = ConvertTo-RenderKitMediaInfoRuntimeIdentifier `
                    -OperatingSystem 'Win32NT' `
                    -Architecture 'Arm64'
                MacX64 = ConvertTo-RenderKitMediaInfoRuntimeIdentifier `
                    -OperatingSystem 'Darwin' `
                    -Architecture 'x86_64'
                MacArm64 = ConvertTo-RenderKitMediaInfoRuntimeIdentifier `
                    -OperatingSystem 'macOS' `
                    -Architecture 'Aarch64'
                LinuxX64 = ConvertTo-RenderKitMediaInfoRuntimeIdentifier `
                    -OperatingSystem 'Linux' `
                    -Architecture 'AMD64'
                LinuxArm64 = ConvertTo-RenderKitMediaInfoRuntimeIdentifier `
                    -OperatingSystem 'Unix' `
                    -Architecture 'ARM64'
            }
        }

        $rids.WinX64 | Should -Be 'win-x64'
        $rids.WinArm64 | Should -Be 'win-arm64'
        $rids.MacX64 | Should -Be 'osx-x64'
        $rids.MacArm64 | Should -Be 'osx-arm64'
        $rids.LinuxX64 | Should -Be 'linux-x64'
        $rids.LinuxArm64 | Should -Be 'linux-arm64'
    }

    It 'resolves a bundled native MediaInfo library before system fallbacks' {
        $moduleRoot = Join-Path $TestDrive 'module'
        $bundleRoot = Join-Path $moduleRoot 'src/Resources/ThirdParty/MediaInfo'
        New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
        Copy-Item `
            -LiteralPath (Join-Path $script:RepositoryRoot 'src/Resources/ThirdParty/MediaInfo/manifest.json') `
            -Destination (Join-Path $bundleRoot 'manifest.json')

        $rid = InModuleScope -ModuleName RenderKit -ScriptBlock { Get-RenderKitMediaInfoRuntimeIdentifier }
        $manifest = Get-Content -LiteralPath (Join-Path $bundleRoot 'manifest.json') -Raw |
            ConvertFrom-Json
        $runtime = @($manifest.runtimeIdentifiers |
            Where-Object { [string]$_.rid -eq $rid } |
            Select-Object -First 1)
        $runtime | Should -Not -BeNullOrEmpty

        $nativePath = Join-Path `
            -Path $bundleRoot `
            -ChildPath ([string]$runtime.nativeLibraryRelativePath)
        New-Item -ItemType Directory -Path (Split-Path -Path $nativePath -Parent) -Force |
            Out-Null
        Set-Content -LiteralPath $nativePath -Value 'fake native binary' -Encoding ASCII

        $resolved = InModuleScope -ModuleName RenderKit -Parameters @{ ModuleRoot = $moduleRoot } -ScriptBlock {
            param($ModuleRoot)
            $script:RenderKitModuleRoot = $ModuleRoot
            $script:RenderKitMediaInfoBundleManifest = $null
            $script:RenderKitMediaInfoBundleManifestPath = $null
            Resolve-RenderKitMediaInfoReader
        }

        $resolved.Available | Should -BeTrue
        $resolved.Mode | Should -Be 'Native'
        $resolved.Source | Should -Be 'Bundled'
        $resolved.NativeLibraryPath | Should -Be ([System.IO.Path]::GetFullPath($nativePath))
    }

    It 'resolves the configured CLI fallback when native resolution is unavailable' {
        $moduleRoot = Join-Path $TestDrive 'module-cli'
        $bundleRoot = Join-Path $moduleRoot 'src/Resources/ThirdParty/MediaInfo'
        New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
        Copy-Item `
            -LiteralPath (Join-Path $script:RepositoryRoot 'src/Resources/ThirdParty/MediaInfo/manifest.json') `
            -Destination (Join-Path $bundleRoot 'manifest.json')

        $cliPath = Join-Path $TestDrive 'mediainfo'
        Set-Content -LiteralPath $cliPath -Value 'fake cli binary' -Encoding ASCII
        $env:RENDERKIT_MEDIAINFO_DISABLE_SYSTEM_NATIVE = '1'
        $env:RENDERKIT_MEDIAINFO_PATH = $cliPath

        $resolved = InModuleScope -ModuleName RenderKit -Parameters @{ ModuleRoot = $moduleRoot } -ScriptBlock {
            param($ModuleRoot)
            $script:RenderKitModuleRoot = $ModuleRoot
            $script:RenderKitMediaInfoBundleManifest = $null
            $script:RenderKitMediaInfoBundleManifestPath = $null
            Resolve-RenderKitMediaInfoReader
        }

        $resolved.Available | Should -BeTrue
        $resolved.Mode | Should -Be 'Cli'
        $resolved.Source | Should -Be 'Environment'
        $resolved.CommandPath | Should -Be ([System.IO.Path]::GetFullPath($cliPath))
    }

    It 'normalizes MediaInfo JSON into RenderKit metadata fields' {
        $raw = @{
            media = @{
                track = @(
                    @{
                        '@type' = 'General'
                        Duration = '12.5'
                        Format = 'MPEG-4'
                    },
                    @{
                        '@type' = 'Video'
                        Width = '1920'
                        Height = '1080'
                        FrameRate = '25.000'
                        FrameCount = '313'
                        DisplayAspectRatio_String = '16:9'
                    },
                    @{
                        '@type' = 'Audio'
                        Format = 'PCM'
                        Channels = '2'
                        SamplingRate = '48000'
                        BitDepth = '24'
                    }
                )
            }
        } | ConvertTo-Json -Depth 10 | ConvertFrom-Json

        $fields = InModuleScope -ModuleName RenderKit -Parameters @{ Raw = $raw } -ScriptBlock {
            param($Raw)
            ConvertFrom-RenderKitMediaInfoMetadata -Raw $Raw
        }

        $fields.Duration | Should -Be '00:12.500'
        $fields.DurationSeconds | Should -Be 12.5
        $fields.ContainerFormat | Should -Be 'MPEG-4'
        $fields.VideoWidth | Should -Be 1920
        $fields.VideoHeight | Should -Be 1080
        $fields.VideoFrameRate | Should -Be 25.0
        $fields.VideoFrameCount | Should -Be 313
        $fields.DisplayAspectRatio | Should -Be '16:9'
        $fields.AudioFormat | Should -Be 'PCM'
        $fields.AudioChannels | Should -Be 2
        $fields.AudioSampleRate | Should -Be 48000
        $fields.AudioBitDepth | Should -Be 24
    }
}
