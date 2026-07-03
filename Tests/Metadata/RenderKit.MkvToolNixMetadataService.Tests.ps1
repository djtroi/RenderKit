Describe 'RenderKit MKVToolNix Matroska metadata integration' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot
        )
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (
            Join-Path $script:RepositoryRoot 'RenderKit.psd1'
        ) -Force

        function New-TestMatroska {
            param(
                [Parameter(Mandatory)]
                [string]$Path
            )

            $base64 = @'
GkXfo6NChoEBQveBAULygQRC84EIQoKIbWF0cm9za2FCh4EEQoWBAhhTgGcBAAAAAAAFchFNm3TAv4RPLzZoTbuLU6uEFUmpZlOsgaFNu4tTq4QWVK5rU6yB7027jFOrhBJUw2dTrIIB2E27jFOrhBxTu2tTrIIFVuwBAAAAAAAAUwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFUmpZsm/hFAinPIq17GDD0JATYCMTGF2ZjYxLjcuMTAwV0GMTGF2ZjYxLjcuMTAwc6SQDGBFNFZRUp4Vfkc+CS7CrESJiEBvAAAAAAAAFlSua0Djv4QQImDhrgEAAAAAAACA14EBc8WIRPMhSK5H8EGcgQAitZyDdW5kiIEAho9WX01QRUc0L0lTTy9BVkODgQEj44OEBfXhAOCQsIEQuoEQmoECVbCEVbmBAVXugQDsAQAAAAAAAAIAAGOipQFCwAr/4QAVZ0LACtp7ARAAAAMAEAAAAwFI8SJqAQAFaM4BlyCuAQAAAAAAAEvXgQJzxYihYexMedzWtJyBACK1nIN1bmSIgQCGhUFfQUFDVqqEB6EgAIOBAuGRn4EBtYhAv0AAAAAAAGJkgSBV7oEAY6KFFYhW5QASVMNnQNi/hGjJB3Rzc59jwIBnyJlFo4dFTkNPREVSRIeMTGF2ZjYxLjcuMTAwc3PXY8CLY8WIRPMhSK5H8EFnyKJFo4dFTkNPREVSRIeVTGF2YzYxLjE5LjEwMCBsaWJ4MjY0Z8ihRaOIRFVSQVRJT05Eh5MwMDowMDowMC4xMDAwMDAwMDAAc3PTY8CLY8WIoWHsTHnc1rRnyJ5Fo4dFTkNPREVSRIeRTGF2YzYxLjE5LjEwMCBhYWNnyKFFo4hEVVJBVElPTkSHkzAwOjAwOjAwLjI0ODAwMDAwMAAfQ7Z1Qpq/hN4O5BvngQCjmYIAAIDeAgBMYXZjNjEuMTkuMTAwAAIwQA6jQmmBAACAAAACVAYF//9Q3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NCByMzE5MiBjMjRlMDZjIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyNCAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTAgcmVmPTEgZGVibG9jaz0wOjA6MCBhbmFseXNlPTA6MCBtZT1kaWEgc3VibWU9MCBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0wIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MCA4eDhkY3Q9MCBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNldD0wIHRocmVhZHM9MSBsb29rYWhlYWRfdGhyZWFkcz0xIHNsaWNlZF90aHJlYWRzPTAgbnI9MCBkZWNpbWF0ZT0xIGludGVybGFjZWQ9MCBibHVyYXlfY29tcGF0PTAgY29uc3RyYWluZWRfaW50cmE9MCBiZnJhbWVzPTAgd2VpZ2h0cD0wIGtleWludD0yNTAga2V5aW50X21pbj0xMCBzY2VuZWN1dD0wIGludHJhX3JlZnJlc2g9MCByYz1jcmYgbWJ0cmVlPTAgY3JmPTUxLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4PTY5IHFwc3RlcD00IGlwX3JhdGlvPTEuNDAgYXE9MACAAAAACWWIhDomKAAVwKOIggCAgAEYIAccU7trl7+EEJz2AruPs4EAt4r3gQHxggK28IEk
'@
            [IO.File]::WriteAllBytes(
                $Path,
                [Convert]::FromBase64String(
                    ($base64 -replace '\s', '')
                )
            )
        }
    }

    It 'resolves a complete hash-verified runtime and corresponding source' {
        $runtime = InModuleScope -ModuleName RenderKit -ScriptBlock {
            Resolve-RenderKitMkvToolNixRuntime
        }
        $runtime.Available | Should -BeTrue
        $runtime.Source | Should -Be 'Bundled'
        $runtime.Version | Should -Be '99.0'
        Test-Path -LiteralPath $runtime.PropEditPath -PathType Leaf |
            Should -BeTrue
        Test-Path -LiteralPath $runtime.ExtractPath -PathType Leaf |
            Should -BeTrue

        $manifest = Get-Content `
            -LiteralPath (
                Join-Path `
                    $script:RepositoryRoot `
                    'src/Resources/ThirdParty/MKVToolNix/manifest.json'
            ) `
            -Raw |
            ConvertFrom-Json
        $sourcePath = Join-Path `
            -Path (
                Join-Path `
                    $script:RepositoryRoot `
                    'src/Resources/ThirdParty/MKVToolNix'
            ) `
            -ChildPath ([string]$manifest.sourceRelativePath)
        (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash |
            Should -Be $manifest.sourceSha256
    }

    It 'writes global tags, first track headers and canonical chapters atomically' {
        $path = Join-Path $TestDrive 'structured.mkv'
        New-TestMatroska -Path $path
        $metadata = [ordered]@{
            Album = 'Production Album'
            Genre = 'Field Recording'
            AudioTrackNumber = 2
            AudioTrackTotal = 9
            ReleaseDate = '2026-07-03'
            Synopsis = 'Night exterior'
            AudioTitle = 'German Mix'
            AudioLanguage = 'de-DE'
            AudioDefaultStream = $true
            AudioForcedStream = $false
            VideoTrackTitle = 'Clean Feed'
            VideoLanguage = 'en-US'
            VideoDefaultStream = $true
            VideoForcedStream = $false
            StereoMode = 'LeftRight'
            Chapters = @(
                [PSCustomObject]@{
                    Start = 0
                    End = 100
                    Title = 'Intro'
                    Language = 'en'
                },
                [PSCustomObject]@{
                    Start = 100
                    End = 200
                    Title = 'Body'
                    Language = 'de'
                }
            )
        }

        $write = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path; Metadata = $metadata } `
            -ScriptBlock {
                param($Path, $Metadata)
                Invoke-RenderKitMkvToolNixMetadataWrite `
                    -Path $Path `
                    -Metadata $Metadata
            }
        $write.Verified | Should -BeTrue
        $write.Adapter | Should -Be 'MkvToolNix'
        $write.GlobalTagsChanged | Should -BeTrue
        $write.ChaptersChanged | Should -BeTrue
        $write.ChapterCount | Should -Be 2

        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path -IncludeRaw
            }
        $read.Fields.Album | Should -Be 'Production Album'
        $read.Fields.Genre | Should -Be 'Field Recording'
        $read.Fields.AudioTrackNumber | Should -Be 2
        $read.Fields.AudioTrackTotal | Should -Be 9
        $read.Fields.ReleaseDate | Should -Be '2026-07-03'
        $read.Fields.AudioTitle | Should -Be 'German Mix'
        $read.Fields.AudioLanguage | Should -Be 'de-DE'
        $read.Fields.AudioDefaultStream | Should -BeTrue
        $read.Fields.AudioForcedStream | Should -BeFalse
        $read.Fields.VideoTrackTitle | Should -Be 'Clean Feed'
        $read.Fields.VideoLanguage | Should -Be 'en-US'
        $read.Fields.VideoDefaultStream | Should -BeTrue
        $read.Fields.VideoForcedStream | Should -BeFalse
        $read.Fields.StereoMode | Should -Be 'LeftRight'
        $read.Fields.ChapterCount | Should -Be 2
        @($read.Fields.Chapters).Count | Should -Be 2
        $read.Fields.Chapters[0].Title | Should -Be 'Intro'
        $read.FieldProvenance.Album.EffectiveSource |
            Should -Be 'EmbeddedMkvToolNix'
        $read.Raw.MkvToolNix.ChapterCount | Should -Be 2
        $read.Warnings | Should -BeNullOrEmpty

        $encoderPreserved = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                $runtime = Resolve-RenderKitMkvToolNixRuntime
                $temporaryPath = Join-Path `
                    -Path ([IO.Path]::GetTempPath()) `
                    -ChildPath (
                        'renderkit-test-tags-{0}.xml' -f
                            [guid]::NewGuid().ToString('N')
                    )
                try {
                    Invoke-RenderKitMkvToolNixApplication `
                        -Path $runtime.ExtractPath `
                        -Name 'mkvextract tags' `
                        -Arguments @($Path, 'tags', $temporaryPath) |
                        Out-Null
                    $document =
                        Read-RenderKitMkvToolNixXmlDocument `
                            -Path $temporaryPath `
                            -RootName Tags
                    $values =
                        Get-RenderKitMkvToolNixSimpleTagValues `
                            -Document $document
                    $values.Contains('ENCODER')
                }
                finally {
                    Remove-Item `
                        -LiteralPath $temporaryPath `
                        -Force `
                        -ErrorAction SilentlyContinue
                }
            }
        $encoderPreserved | Should -BeTrue
    }

    It 'routes public writes and supplemental reads through MKVToolNix' {
        $path = Join-Path $TestDrive 'public.mkv'
        New-TestMatroska -Path $path

        $result = Add-Metadata `
            -Path $path `
            -Field Synopsis `
            -Value 'Public synopsis'
        $result.Embedded.Count | Should -Be 1
        $result.Embedded[0].Status | Should -Be 'Written'
        $result.Embedded[0].Adapter | Should -Be 'MkvToolNix'
        $result.Embedded[0].Verified | Should -BeTrue

        $read = Get-Metadata `
            -Path $path `
            -Field Synopsis `
            -IncludeMetadata
        $read.Metadata.Synopsis | Should -Be 'Public synopsis'
    }

    It 'rejects an ambiguous stereo layout without changing source bytes' {
        $path = Join-Path $TestDrive 'ambiguous.mkv'
        New-TestMatroska -Path $path
        $before = [IO.File]::ReadAllBytes($path)

        {
            InModuleScope `
                -ModuleName RenderKit `
                -Parameters @{ Path = $path } `
                -ScriptBlock {
                    param($Path)
                    Invoke-RenderKitMkvToolNixMetadataWrite `
                        -Path $Path `
                        -Metadata ([ordered]@{
                            StereoMode = 'SeparateStreams'
                        })
                }
        } | Should -Throw '*TrackOperation*'

        [IO.File]::ReadAllBytes($path) | Should -Be $before
    }
}
