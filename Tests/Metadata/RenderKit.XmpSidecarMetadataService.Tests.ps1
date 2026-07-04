Describe 'RenderKit XMP sidecar metadata integration' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot
        )
        $script:PreviousHome = $env:RENDERKIT_HOME
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (
            Join-Path $script:RepositoryRoot 'RenderKit.psd1'
        ) -Force
        $script:ExifToolAvailable = [bool](
            InModuleScope -ModuleName RenderKit -ScriptBlock {
                (Resolve-RenderKitExifToolReader).Available
            }
        )
        $script:PngBytes = [Convert]::FromBase64String(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
        )
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        $env:RENDERKIT_HOME = $script:PreviousHome
    }

    It 'creates a verified sidecar and exposes only safe descriptors' {
        if (-not $script:ExifToolAvailable) {
            Set-ItResult -Skipped -Because 'No ExifTool runtime is available.'
            return
        }
        $path = Join-Path $TestDrive 'sidecar.png'
        [IO.File]::WriteAllBytes($path, $script:PngBytes)

        $write = Add-Metadata `
            -Path $path `
            -Field Title `
            -Value 'Sidecar title' `
            -XmpSidecar
        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path -IncludeRaw
            }

        $write.Embedded[0].Adapter | Should -Be 'ExifToolXmpSidecar'
        $write.Embedded[0].Verified | Should -BeTrue
        Test-Path -LiteralPath ([IO.Path]::ChangeExtension($path, '.xmp')) |
            Should -BeTrue
        $read.Fields.Title | Should -Be 'Sidecar title'
        $read.XmpState | Should -Be 'Sidecar'
        @($read.XmpSidecars).Count | Should -Be 1
        $read.XmpSidecars[0].Convention | Should -Be 'Stem'
        $read.XmpSidecars[0].PSObject.Properties.Name |
            Should -Not -Contain 'Path'
        $read.Raw.XmpSidecar[0].PSObject.Properties.Name |
            Should -Not -Contain 'Path'
        $read.FieldProvenance.Title.EffectiveSource |
            Should -Be 'SidecarXmp'
    }

    It 'keeps using an existing sidecar without requiring the switch again' {
        if (-not $script:ExifToolAvailable) {
            Set-ItResult -Skipped -Because 'No ExifTool runtime is available.'
            return
        }
        $path = Join-Path $TestDrive 'existing.png'
        [IO.File]::WriteAllBytes($path, $script:PngBytes)
        Add-Metadata `
            -Path $path `
            -Field Title `
            -Value 'Initial title' `
            -XmpSidecar |
            Out-Null

        $write = Add-Metadata `
            -Path $path `
            -Field Rating `
            -Value 5
        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path
            }

        $write.Embedded[0].Adapter | Should -Be 'ExifToolXmpSidecar'
        $write.Embedded[0].Created | Should -BeFalse
        $read.Fields.Title | Should -Be 'Initial title'
        $read.Fields.Rating | Should -Be 5
        $read.XmpState | Should -Be 'Sidecar'
    }

    It 'makes sidecar XMP win explicitly when embedded XMP differs' {
        if (-not $script:ExifToolAvailable) {
            Set-ItResult -Skipped -Because 'No ExifTool runtime is available.'
            return
        }
        $path = Join-Path $TestDrive 'conflict.png'
        [IO.File]::WriteAllBytes($path, $script:PngBytes)
        Add-Metadata `
            -Path $path `
            -Field Title `
            -Value 'Embedded title' |
            Out-Null
        InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Invoke-RenderKitXmpSidecarMetadataWrite `
                    -Path $Path `
                    -Metadata ([ordered]@{
                        Title = 'Sidecar title'
                    }) |
                    Out-Null
            }

        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path
            }

        $read.Fields.Title | Should -Be 'Sidecar title'
        $read.XmpState | Should -Be 'Conflicting'
        $read.IptcState | Should -Not -Be 'Conflicting'
        @(
            $read.Conflicts |
                Where-Object {
                    $_.Field -eq 'Title' -and
                    $_.Kind -eq 'EmbeddedVsXmpSidecar'
                }
        ).Count | Should -Be 1
        $read.FieldProvenance.Title.EffectiveSource |
            Should -Be 'SidecarXmp'
        $read.FieldProvenance.Title.Conflict | Should -BeTrue
    }

    It 'does not report legacy IPTC-only values as embedded XMP' {
        if (-not $script:ExifToolAvailable) {
            Set-ItResult -Skipped -Because 'No ExifTool runtime is available.'
            return
        }
        $path = Join-Path $TestDrive 'legacy-iptc.jpg'
        [IO.File]::WriteAllBytes(
            $path,
            [Convert]::FromBase64String(
                '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q=='
            )
        )
        InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Invoke-RenderKitExifToolCommand `
                    -Arguments @(
                        '-overwrite_original',
                        '-IPTC:ObjectName=Legacy IPTC title',
                        $Path
                    ) |
                    Out-Null
            }

        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path
            }

        $read.Fields.Title | Should -Be 'Legacy IPTC title'
        $read.IptcState | Should -Be 'Embedded'
        $read.XmpState | Should -Be 'Absent'
    }
}
