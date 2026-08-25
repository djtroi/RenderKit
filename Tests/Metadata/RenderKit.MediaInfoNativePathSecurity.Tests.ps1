Describe 'RenderKit MediaInfo native library trust boundary' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $repositoryRoot 'RenderKit.psd1') -Force
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'does not select a native MediaInfo library found only in executable PATH' {
        $pathDirectory = Join-Path $TestDrive 'path-native'
        New-Item -ItemType Directory -Path $pathDirectory -Force | Out-Null

        $nativeName = InModuleScope RenderKit {
            @(Get-RenderKitMediaInfoSystemNativeName)[0]
        }
        $fakeLibrary = Join-Path $pathDirectory $nativeName
        Set-Content -LiteralPath $fakeLibrary -Value 'not-a-native-library' -Encoding UTF8

        $previousPath = $env:PATH
        try {
            $env:PATH = $pathDirectory
            $resolved = InModuleScope RenderKit {
                Find-RenderKitMediaInfoSystemNativeLibrary
            }
        }
        finally {
            $env:PATH = $previousPath
        }

        if ($resolved) {
            [System.IO.Path]::GetFullPath([string]$resolved) |
                Should -Not -Be ([System.IO.Path]::GetFullPath($fakeLibrary))
        }
    }

    It 'still accepts an explicitly configured native MediaInfo library candidate' {
        $explicitLibrary = Join-Path $TestDrive 'explicit-mediainfo-native.bin'
        Set-Content -LiteralPath $explicitLibrary -Value 'fixture' -Encoding UTF8

        $previousLibrary = $env:RENDERKIT_MEDIAINFO_LIBRARY
        $previousDisableSystem = $env:RENDERKIT_MEDIAINFO_DISABLE_SYSTEM_NATIVE
        try {
            $env:RENDERKIT_MEDIAINFO_LIBRARY = $explicitLibrary
            $env:RENDERKIT_MEDIAINFO_DISABLE_SYSTEM_NATIVE = '1'
            $reader = InModuleScope RenderKit {
                Resolve-RenderKitMediaInfoReader
            }
        }
        finally {
            $env:RENDERKIT_MEDIAINFO_LIBRARY = $previousLibrary
            $env:RENDERKIT_MEDIAINFO_DISABLE_SYSTEM_NATIVE = $previousDisableSystem
        }

        $environmentCandidate = @(
            $reader.NativeCandidates |
                Where-Object { [string]$_.Source -eq 'Environment' } |
                Select-Object -First 1
        )
        $environmentCandidate.Count | Should -Be 1
        $environmentCandidate[0].Available | Should -BeTrue
        [System.IO.Path]::GetFullPath([string]$environmentCandidate[0].Path) |
            Should -Be ([System.IO.Path]::GetFullPath($explicitLibrary))
    }

    It 'loads the hardened native finder after the base MediaInfo service' {
        $definition = InModuleScope RenderKit {
            (Get-Command Find-RenderKitMediaInfoSystemNativeLibrary).Definition
        }

        $definition | Should -Not -Match '\$env:PATH'
        $definition | Should -Match 'ProgramFiles'
    }
}
