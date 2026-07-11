Describe 'RenderKit BWF, iXML, ID3 and Matroska metadata profiles' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:RepositoryRoot 'RenderKit.psd1') -Force
    }

    It 'covers every registry field assigned to each profile' {
        $coverage = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $registry = Read-RenderKitMetadataFieldRegistry
            foreach ($profile in @('BWF', 'iXML', 'ID3', 'Matroska')) {
                $map = Read-RenderKitAudioContainerMetadataProfileMap `
                    -Profile $profile `
                    -Reload
                $covered = @(
                    @($map.fields) + @($map.unmappedFields) |
                        ForEach-Object { [string]$_.field }
                )
                $expected = @(
                    $registry.fields |
                        Where-Object {
                            @(
                                ([string]$_.sourceStandards -split '/') |
                                    ForEach-Object { $_.Trim() }
                            ) -contains $profile
                        } |
                        ForEach-Object { [string]$_.name }
                )

                [PSCustomObject]@{
                    Profile = $profile
                    ArtifactType = [string]$map.artifactType
                    WriteStatus = [string]$map.writeCapability.status
                    ExpectedCount = $expected.Count
                    CoveredCount = $covered.Count
                    Missing = @($expected | Where-Object {
                        $covered -notcontains $_
                    })
                    Unknown = @($covered | Where-Object {
                        $expected -notcontains $_
                    })
                }
            }
        }

        @($coverage).Count | Should -Be 4
        foreach ($result in @($coverage)) {
            $result.ArtifactType | Should -Match 'MetadataMap$'
            $expectedStatus = if (
                $result.Profile -in @(
                    'BWF',
                    'iXML',
                    'ID3',
                    'Matroska'
                )
            ) {
                'Available'
            }
            else {
                'NotImplemented'
            }
            $result.WriteStatus | Should -Be $expectedStatus
            $result.CoveredCount | Should -Be $result.ExpectedCount
            $result.Missing | Should -BeNullOrEmpty
            $result.Unknown | Should -BeNullOrEmpty
        }
    }

    It 'advertises the native ID3 writer without routing writes to ExifTool' {
        $adapter = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $routing = Read-RenderKitMetadataAdapterRouting -Reload
            $routing.adapters |
                Where-Object id -eq 'ID3' |
                Select-Object -First 1
        }

        $adapter.canRead | Should -BeTrue
        $adapter.canWrite | Should -BeTrue
        $adapter.readerAdapter | Should -Be 'ExifTool'
    }

    It 'advertises target-aware Matroska writes alongside MediaInfo reads' {
        $adapter = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $routing = Read-RenderKitMetadataAdapterRouting -Reload
            $routing.adapters |
                Where-Object id -eq 'Matroska' |
                Select-Object -First 1
        }

        $adapter.canRead | Should -BeTrue
        $adapter.canWrite | Should -BeTrue
        $adapter.readerAdapter | Should -Be 'MediaInfo'
    }

    It 'normalizes BEXT values from ExifTool and keeps date and time separate' {
        $fields = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $raw = [PSCustomObject][ordered]@{
                'RIFF:BitsPerSample' = 24
                'RIFF:SampleRate' = 48000
                'RIFF:Description' = 'Exterior ambience'
                'RIFF:Originator' = 'RenderKit Recorder'
                'RIFF:OriginatorReference' = 'RK-REF-42'
                'RIFF:DateTimeOriginal' = '2026:07:02 10:11:12'
                'RIFF:TimeReference' = 123456
                'RIFF:BWFVersion' = 2
                'RIFF:BWF_UMID' = '060A2B34'
                'RIFF:CodingHistory' = 'A=PCM,F=48000,W=24,M=mono,'
            }

            ConvertFrom-RenderKitAudioContainerMetadataProfile `
                -Raw $raw `
                -Profile BWF `
                -Adapter ExifTool
        }

        $fields.AudioBitDepth | Should -Be 24
        $fields.AudioSampleRate | Should -Be 48000
        $fields.BwfDescription | Should -Be 'Exterior ambience'
        $fields.BwfOriginationDate | Should -Be '2026-07-02'
        $fields.BwfOriginationTime | Should -Be '10:11:12'
        $fields.BwfTimeReferenceSamples | Should -Be 123456
        $fields.BwfVersion | Should -Be 2
    }

    It 'preserves structured iXML values and combines the timestamp words' {
        $fields = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $raw = [PSCustomObject][ordered]@{
                'XML:Bwfxml' = [PSCustomObject][ordered]@{
                    Project = 'Feature A'
                    Scene = '12A'
                    Take = 4
                    Circled = $true
                    NoGood = $false
                    WildTrack = $true
                    Speed = [PSCustomObject]@{
                        FileSampleRate = 48000
                        AudioBitDepth = 24
                        TimecodeRate = 24
                    }
                    TimestampSamplesSinceMidnightHi = 1
                    TimestampSamplesSinceMidnightLo = 2
                    TrackList = [PSCustomObject]@{
                        Track = @(
                            [PSCustomObject]@{
                                ChannelIndex = 1
                                InterleaveIndex = 1
                                Name = 'Boom'
                                Function = 'Dialog'
                            },
                            [PSCustomObject]@{
                                ChannelIndex = 2
                                InterleaveIndex = 2
                                Name = 'Lav'
                                Function = 'Dialog'
                            }
                        )
                    }
                }
            }

            ConvertFrom-RenderKitAudioContainerMetadataProfile `
                -Raw $raw `
                -Profile iXML `
                -Adapter ExifTool
        }

        $fields.IxmlProject | Should -Be 'Feature A'
        $fields.IxmlScene | Should -Be '12A'
        $fields.IxmlTake | Should -Be '4'
        $fields.IxmlCircled | Should -BeTrue
        $fields.IxmlNoGood | Should -BeFalse
        $fields.IxmlSampleRate | Should -Be 48000
        $fields.IxmlBitDepth | Should -Be 24
        $fields.IxmlTimestampSamplesSinceMidnight |
            Should -Be ([uint64]4294967298)
        @($fields.IxmlTrackList).Count | Should -Be 2
        $fields.IxmlTrackList[1].Name | Should -Be 'Lav'
        $fields.IxmlSpeed.TimecodeRate | Should -Be 24
    }

    It 'prefers the newest ID3 group and splits track and disc pairs' {
        $fields = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $raw = [PSCustomObject][ordered]@{
                'ID3v2_3:Title' = 'Old title'
                'ID3v2_4:Title' = 'Current title'
                'ID3v2_4:Artist' = @('Artist One', 'Artist Two')
                'ID3v2_4:Band' = 'Album Artist'
                'ID3v2_4:Track' = '2/9'
                'ID3v2_4:PartOfSet' = '1/3'
                'ID3v2_4:RecordingTime' = '2026:07:02'
                'ID3v2_4:BeatsPerMinute' = '128.5'
                'ID3v2_4:Comment' = 'Field note'
            }

            ConvertFrom-RenderKitAudioContainerMetadataProfile `
                -Raw $raw `
                -Profile ID3 `
                -Adapter ExifTool
        }

        $fields.Title | Should -Be 'Current title'
        $fields.AudioTitle | Should -Be 'Current title'
        $fields.AlbumArtist | Should -Be 'Album Artist'
        $fields.AudioTrackNumber | Should -Be 2
        $fields.AudioTrackTotal | Should -Be 9
        $fields.AudioDiscNumber | Should -Be 1
        $fields.AudioDiscTotal | Should -Be 3
        $fields.RecordingDate | Should -Be '2026-07-02'
        $fields.Bpm | Should -Be 128.5
        $fields.UserComment | Should -Be 'Field note'
        @($fields.Creator) | Should -Contain 'Artist Two'
    }

    It 'reads Matroska segment tags and track flags from their distinct tracks' {
        $fields = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $raw = [PSCustomObject]@{
                media = [PSCustomObject]@{
                    track = @(
                        [PSCustomObject][ordered]@{
                            '@type' = 'General'
                            extra = [PSCustomObject]@{
                                ALBUM = 'Production Audio'
                                GENRE = 'Field Recording'
                                SYNOPSIS = 'Night exterior'
                            }
                        },
                        [PSCustomObject][ordered]@{
                            '@type' = 'Audio'
                            Title = 'German Mix'
                            Language = 'de'
                            Default = 'Yes'
                            Forced = 'No'
                        },
                        [PSCustomObject][ordered]@{
                            '@type' = 'Video'
                            Title = 'Clean Feed'
                            Language = 'und'
                            Default = '1'
                            Forced = '0'
                        }
                    )
                }
            }

            ConvertFrom-RenderKitAudioContainerMetadataProfile `
                -Raw $raw `
                -Profile Matroska `
                -Adapter MediaInfo
        }

        $fields.Album | Should -Be 'Production Audio'
        $fields.Genre | Should -Be 'Field Recording'
        $fields.Synopsis | Should -Be 'Night exterior'
        $fields.AudioTitle | Should -Be 'German Mix'
        $fields.AudioLanguage | Should -Be 'de'
        $fields.AudioDefaultStream | Should -BeTrue
        $fields.AudioForcedStream | Should -BeFalse
        $fields.VideoTrackTitle | Should -Be 'Clean Feed'
        $fields.VideoDefaultStream | Should -BeTrue
        $fields.VideoForcedStream | Should -BeFalse
    }

    It 'reads BEXT and iXML through the bundled ExifTool path' {
        $resolved = InModuleScope -ModuleName RenderKit -ScriptBlock {
            Resolve-RenderKitExifToolReader
        }
        if (-not [bool]$resolved.Available) {
            Set-ItResult -Skipped -Because 'No ExifTool runtime is available on this test host.'
            return
        }

        function Write-FixedAscii {
            param(
                [Parameter(Mandatory)]
                [System.IO.BinaryWriter]$Writer,
                [Parameter(Mandatory)]
                [string]$Value,
                [Parameter(Mandatory)]
                [int]$Length
            )

            $bytes = [Text.Encoding]::ASCII.GetBytes($Value)
            if ($bytes.Length -gt $Length) {
                throw "Value '$Value' exceeds $Length bytes."
            }
            $Writer.Write($bytes)
            if ($bytes.Length -lt $Length) {
                $Writer.Write((New-Object byte[] ($Length - $bytes.Length)))
            }
        }

        function Write-RiffChunk {
            param(
                [Parameter(Mandatory)]
                [System.IO.BinaryWriter]$Writer,
                [Parameter(Mandatory)]
                [string]$Id,
                [Parameter(Mandatory)]
                [byte[]]$Payload
            )

            $Writer.Write([Text.Encoding]::ASCII.GetBytes($Id))
            $Writer.Write([uint32]$Payload.Length)
            $Writer.Write($Payload)
            if (($Payload.Length % 2) -ne 0) {
                $Writer.Write([byte]0)
            }
        }

        $bextStream = [IO.MemoryStream]::new()
        $bextWriter = [IO.BinaryWriter]::new($bextStream)
        Write-FixedAscii $bextWriter 'Reference BWF' 256
        Write-FixedAscii $bextWriter 'RenderKit' 32
        Write-FixedAscii $bextWriter 'RK-REFERENCE-1' 32
        Write-FixedAscii $bextWriter '2026-07-02' 10
        Write-FixedAscii $bextWriter '10:11:12' 8
        $bextWriter.Write([uint32]123456)
        $bextWriter.Write([uint32]0)
        $bextWriter.Write([uint16]1)
        $bextWriter.Write((New-Object byte[] 64))
        foreach ($value in @(0, 0, 0, 0, 0)) {
            $bextWriter.Write([int16]$value)
        }
        $bextWriter.Write((New-Object byte[] 180))
        $bextWriter.Write(
            [Text.Encoding]::ASCII.GetBytes('A=PCM,F=48000,W=16,M=mono,')
        )
        $bextWriter.Flush()
        $bext = $bextStream.ToArray()
        $bextWriter.Dispose()
        $bextStream.Dispose()

        $ixml = [Text.Encoding]::UTF8.GetBytes(@'
<BWFXML>
  <IXML_VERSION>3.01</IXML_VERSION>
  <PROJECT>Reference Project</PROJECT>
  <SCENE>42B</SCENE>
  <TAKE>7</TAKE>
  <CIRCLED>TRUE</CIRCLED>
  <TRACK_LIST>
    <TRACK>
      <CHANNEL_INDEX>1</CHANNEL_INDEX>
      <INTERLEAVE_INDEX>1</INTERLEAVE_INDEX>
      <NAME>Boom</NAME>
      <FUNCTION>Dialog</FUNCTION>
    </TRACK>
  </TRACK_LIST>
</BWFXML>
'@)

        $fmtStream = [IO.MemoryStream]::new()
        $fmtWriter = [IO.BinaryWriter]::new($fmtStream)
        $fmtWriter.Write([uint16]1)
        $fmtWriter.Write([uint16]1)
        $fmtWriter.Write([uint32]48000)
        $fmtWriter.Write([uint32]96000)
        $fmtWriter.Write([uint16]2)
        $fmtWriter.Write([uint16]16)
        $fmtWriter.Flush()
        $fmt = $fmtStream.ToArray()
        $fmtWriter.Dispose()
        $fmtStream.Dispose()

        $riffStream = [IO.MemoryStream]::new()
        $riffWriter = [IO.BinaryWriter]::new($riffStream)
        $riffWriter.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
        $riffWriter.Write([uint32]0)
        $riffWriter.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
        Write-RiffChunk $riffWriter 'fmt ' $fmt
        Write-RiffChunk $riffWriter 'bext' $bext
        Write-RiffChunk $riffWriter 'iXML' $ixml
        Write-RiffChunk $riffWriter 'data' ([byte[]](0, 0))
        $riffSize = [uint32]($riffStream.Length - 8)
        $riffStream.Position = 4
        $riffWriter.Write($riffSize)
        $riffWriter.Flush()
        $bytes = $riffStream.ToArray()
        $riffWriter.Dispose()
        $riffStream.Dispose()

        $samplePath = Join-Path $TestDrive 'bwf-ixml-reference.wav'
        [IO.File]::WriteAllBytes($samplePath, $bytes)
        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $samplePath } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path -IncludeRaw
            }

        $read.Fields.BwfDescription | Should -Be 'Reference BWF'
        $read.Fields.BwfOriginator | Should -Be 'RenderKit'
        $read.Fields.BwfTimeReferenceSamples | Should -Be 123456
        $read.Fields.BwfOriginationDate | Should -Be '2026-07-02'
        $read.Fields.BwfOriginationTime | Should -Be '10:11:12'
        $read.Fields.IxmlProject | Should -Be 'Reference Project'
        $read.Fields.IxmlScene | Should -Be '42B'
        $read.Fields.IxmlTake | Should -Be '7'
        $read.Fields.IxmlCircled | Should -BeTrue
        @($read.Fields.IxmlTrackList).Count | Should -Be 1
        $read.Raw.ExifTool.'XML:Bwfxml'.Project | Should -Be 'Reference Project'
        $read.Warnings | Should -BeNullOrEmpty
    }
}
