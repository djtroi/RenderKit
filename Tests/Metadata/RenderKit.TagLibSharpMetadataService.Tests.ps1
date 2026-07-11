Describe 'RenderKit TagLibSharp ID3 metadata integration' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot
        )
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (
            Join-Path $script:RepositoryRoot 'RenderKit.psd1'
        ) -Force

        function New-TestMp3 {
            param(
                [Parameter(Mandatory)]
                [string]$Path
            )

            $frameLength = 417
            $bytes = New-Object byte[] ($frameLength * 4)
            for ($index = 0; $index -lt 4; $index++) {
                $offset = $index * $frameLength
                $bytes[$offset] = 0xff
                $bytes[$offset + 1] = 0xfb
                $bytes[$offset + 2] = 0x90
                $bytes[$offset + 3] = 0x64
            }
            [IO.File]::WriteAllBytes($Path, $bytes)
        }
    }

    It 'resolves the bundled assembly only after its manifest hash matches' {
        $runtime = InModuleScope -ModuleName RenderKit -ScriptBlock {
            Resolve-RenderKitTagLibSharpRuntime
        }

        $runtime.Available | Should -BeTrue
        $runtime.Source | Should -Be 'Bundled'
        $runtime.Version | Should -Be '2.3.0'
        $runtime.Hash | Should -Match '^[A-F0-9]{64}$'
        Test-Path -LiteralPath $runtime.Path -PathType Leaf |
            Should -BeTrue
    }

    It 'writes and reads structured ID3v2.4 metadata while preserving unknown frames' {
        $path = Join-Path $TestDrive 'structured.mp3'
        New-TestMp3 -Path $path
        $coverPath = Join-Path $TestDrive 'cover.png'
        [IO.File]::WriteAllBytes(
            $coverPath,
            [Convert]::FromBase64String(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
            )
        )

        InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Import-RenderKitTagLibSharpRuntime | Out-Null
                $file = [TagLib.File]::Create($Path)
                try {
                    $tag = $file.GetTag(
                        [TagLib.TagTypes]::Id3v2,
                        $true
                    )
                    $tag.AddFrame(
                        [TagLib.Id3v2.PrivateFrame]::new(
                            'renderkit.test',
                            [TagLib.ByteVector]::new(
                                [byte[]](1, 2, 3, 4)
                            )
                        )
                    )
                    $file.Save()
                }
                finally {
                    $file.Dispose()
                }
            }

        $metadata = [ordered]@{
            Title = 'Native ID3'
            Artist = @('Artist One', 'Artist Two')
            Album = 'RenderKit Sessions'
            AudioTrackNumber = 2
            AudioTrackTotal = 9
            Bpm = '128.5'
            RecordingDate = '2026-07-03'
            Barcode = '123456789'
            ArtistUrl = 'https://example.test/artist'
            Arranger = 'A. Range'
            Lyrics = 'First line'
            LyricsLanguage = 'eng'
            SynchronizedLyrics = @(
                [PSCustomObject]@{
                    TimestampMilliseconds = 100
                    Text = 'First line'
                },
                [PSCustomObject]@{
                    TimestampMilliseconds = 900
                    Text = 'Second line'
                }
            )
            AttachedPictures = @(
                [PSCustomObject]@{
                    Path = $coverPath
                    Mime = 'image/png'
                    Type = 'FrontCover'
                    Description = 'Test cover'
                }
            )
            Chapters = @(
                [PSCustomObject]@{
                    Start = 0
                    End = 750
                    Title = 'Intro'
                    Url = 'https://example.test/intro'
                },
                [PSCustomObject]@{
                    Start = 750
                    End = 1500
                    Title = 'Body'
                }
            )
        }

        $write = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path; Metadata = $metadata } `
            -ScriptBlock {
                param($Path, $Metadata)
                Invoke-RenderKitTagLibSharpMetadataWrite `
                    -Path $Path `
                    -Metadata $Metadata
            }
        $write.Verified | Should -BeTrue
        $write.Adapter | Should -Be 'TagLibSharp'
        $write.TagVersion | Should -Be 4

        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitTagLibSharpEmbeddedMetadata -Path $Path
            }
        $read.Fields.Title | Should -Be 'Native ID3'
        @($read.Fields.Artist) | Should -Be @(
            'Artist One',
            'Artist Two'
        )
        $read.Fields.AudioTrackNumber | Should -Be 2
        $read.Fields.AudioTrackTotal | Should -Be 9
        $read.Fields.Bpm | Should -Be 128.5
        $read.Fields.Barcode | Should -Be '123456789'
        $read.Fields.LyricsLanguage | Should -Be 'eng'
        @($read.Fields.SynchronizedLyrics).Count | Should -Be 2
        @($read.Fields.AttachedPictures).Count | Should -Be 1
        $read.Fields.AttachedPictures[0].Type | Should -Be 'FrontCover'
        @($read.Fields.Chapters).Count | Should -Be 2
        $read.Fields.Chapters[0].Title | Should -Be 'Intro'
        $read.Fields.Chapters[0].Url |
            Should -Be 'https://example.test/intro'

        $privateFrame = @(InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                $file = [TagLib.File]::Create($Path)
                try {
                    @(
                        $file.GetTag(
                            [TagLib.TagTypes]::Id3v2,
                            $false
                        ).GetFrames[
                            TagLib.Id3v2.PrivateFrame
                        ]() |
                            Where-Object Owner -eq 'renderkit.test' |
                            Select-Object -First 1
                    )
                }
                finally {
                    $file.Dispose()
                }
            })
        $privateFrame.Count | Should -Be 1
        @($privateFrame[0].PrivateData.Data) |
            Should -Be @([byte[]](1, 2, 3, 4))
    }

    It 'routes public embedded writes and native reads through TagLibSharp' {
        $path = Join-Path $TestDrive 'public.mp3'
        New-TestMp3 -Path $path

        $result = Add-Metadata `
            -Path $path `
            -Field Title `
            -Value 'Public title'
        $result.Embedded.Count | Should -Be 1
        $result.Embedded[0].Status | Should -Be 'Written'
        $result.Embedded[0].Adapter | Should -Be 'TagLibSharp'
        $result.Embedded[0].Verified | Should -BeTrue

        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata `
                    -Path $Path `
                    -IncludeRaw
            }
        $read.Fields.Title | Should -Be 'Public title'
        $read.FieldProvenance.Title.EffectiveSource |
            Should -Be 'EmbeddedTagLibSharp'
        $read.Raw.TagLibSharp.TagPresent | Should -BeTrue
        $read.Warnings | Should -BeNullOrEmpty
    }

    It 'rejects conflicting aliases without changing the source file' {
        $path = Join-Path $TestDrive 'conflict.mp3'
        New-TestMp3 -Path $path
        $before = [IO.File]::ReadAllBytes($path)

        {
            InModuleScope `
                -ModuleName RenderKit `
                -Parameters @{ Path = $path } `
                -ScriptBlock {
                    param($Path)
                    Invoke-RenderKitTagLibSharpMetadataWrite `
                        -Path $Path `
                        -Metadata ([ordered]@{
                            Title = 'First title'
                            AudioTitle = 'Second title'
                        })
                }
        } | Should -Throw '*Conflicting values*'

        $after = [IO.File]::ReadAllBytes($path)
        $after | Should -Be $before
        Get-ChildItem `
            -LiteralPath $TestDrive `
            -Filter '*.bak' |
            Should -BeNullOrEmpty
    }
}
