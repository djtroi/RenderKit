Describe 'RenderKit native BWF and iXML RIFF writer' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:RepositoryRoot 'RenderKit.psd1') -Force

        function Write-TestFixedAscii {
            param(
                [Parameter(Mandatory)]
                [System.IO.BinaryWriter]$Writer,
                [Parameter(Mandatory)]
                [string]$Value,
                [Parameter(Mandatory)]
                [int]$Length
            )

            $bytes = [Text.Encoding]::ASCII.GetBytes($Value)
            $Writer.Write($bytes)
            if ($bytes.Length -lt $Length) {
                $Writer.Write((New-Object byte[] ($Length - $bytes.Length)))
            }
        }

        function Write-TestRiffChunk {
            param(
                [Parameter(Mandatory)]
                [System.IO.BinaryWriter]$Writer,
                [Parameter(Mandatory)]
                [string]$Id,
                [Parameter(Mandatory)]
                [byte[]]$Payload,
                [byte]$PaddingByte = 0
            )

            $Writer.Write([Text.Encoding]::ASCII.GetBytes($Id))
            $Writer.Write([uint32]$Payload.Length)
            $Writer.Write($Payload)
            if (($Payload.Length % 2) -ne 0) {
                $Writer.Write($PaddingByte)
            }
        }

        function New-TestBextPayload {
            $stream = [IO.MemoryStream]::new()
            $writer = [IO.BinaryWriter]::new($stream)
            Write-TestFixedAscii $writer 'Original BWF' 256
            Write-TestFixedAscii $writer 'Original Recorder' 32
            Write-TestFixedAscii $writer 'ORIGINAL-REF' 32
            Write-TestFixedAscii $writer '2026-07-01' 10
            Write-TestFixedAscii $writer '09:10:11' 8
            $writer.Write([uint32]1234)
            $writer.Write([uint32]0)
            $writer.Write([uint16]1)
            $writer.Write((New-Object byte[] 64))
            foreach ($value in @(32767, 32767, 32767, 32767, 32767)) {
                $writer.Write([int16]$value)
            }
            $reserved = New-Object byte[] 180
            $reserved[78] = 0xab
            $writer.Write($reserved)
            $writer.Write(
                [Text.Encoding]::ASCII.GetBytes(
                    'A=PCM,F=48000,W=16,M=mono,'
                )
            )
            $writer.Flush()
            $bytes = $stream.ToArray()
            $writer.Dispose()
            $stream.Dispose()
            return ,$bytes
        }

        function New-TestWaveFile {
            param(
                [Parameter(Mandatory)]
                [string]$Path,
                [switch]$Rf64,
                [switch]$IncludeMetadata
            )

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

            $stream = [IO.MemoryStream]::new()
            $writer = [IO.BinaryWriter]::new($stream)
            $writer.Write(
                [Text.Encoding]::ASCII.GetBytes(
                    $(if ($Rf64) { 'RF64' } else { 'RIFF' })
                )
            )
            $writer.Write(
                $(if ($Rf64) {
                    [uint32]::MaxValue
                }
                else {
                    [uint32]0
                })
            )
            $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))

            if ($Rf64) {
                $ds64 = New-Object byte[] 28
                Write-TestRiffChunk $writer 'ds64' $ds64
            }
            Write-TestRiffChunk $writer 'fmt ' $fmt
            Write-TestRiffChunk `
                $writer `
                'JUNK' `
                ([byte[]](0x10, 0x20, 0x30)) `
                0x7f

            if ($IncludeMetadata) {
                Write-TestRiffChunk $writer 'bext' (New-TestBextPayload)
                $ixml = [Text.Encoding]::UTF8.GetBytes(@'
<?xml version="1.0" encoding="UTF-8"?>
<BWFXML>
  <IXML_VERSION>3.01</IXML_VERSION>
  <PROJECT>Original Project</PROJECT>
  <VENDOR_EXTENSION>
    <FOO>preserve-me</FOO>
  </VENDOR_EXTENSION>
</BWFXML>
'@)
                Write-TestRiffChunk $writer 'iXML' $ixml
            }

            $data = [byte[]](0x40, 0x50, 0x60, 0x70)
            $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
            $writer.Write(
                $(if ($Rf64) {
                    [uint32]::MaxValue
                }
                else {
                    [uint32]$data.Length
                })
            )
            $writer.Write($data)
            $writer.Flush()
            $bytes = $stream.ToArray()
            $writer.Dispose()
            $stream.Dispose()

            if ($Rf64) {
                [Array]::Copy(
                    [BitConverter]::GetBytes([uint64]($bytes.Length - 8)),
                    0,
                    $bytes,
                    20,
                    8
                )
                [Array]::Copy(
                    [BitConverter]::GetBytes([uint64]$data.Length),
                    0,
                    $bytes,
                    28,
                    8
                )
                [Array]::Copy(
                    [BitConverter]::GetBytes([uint64]2),
                    0,
                    $bytes,
                    36,
                    8
                )
            }
            else {
                [Array]::Copy(
                    [BitConverter]::GetBytes([uint32]($bytes.Length - 8)),
                    0,
                    $bytes,
                    4,
                    4
                )
            }
            [IO.File]::WriteAllBytes($Path, $bytes)
        }
    }

    It 'advertises the built-in RIFF writer for BWF and iXML fields' {
        $path = Join-Path $TestDrive 'capability.wav'
        New-TestWaveFile -Path $path

        $capabilities = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                @(
                    Get-RenderKitEmbeddedMetadataWriteCapability `
                        -Field BwfDescription `
                        -MediaKind Audio `
                        -Path $Path
                    Get-RenderKitEmbeddedMetadataWriteCapability `
                        -Field IxmlProject `
                        -MediaKind Audio `
                        -Path $Path
                )
            }

        @($capabilities).Count | Should -Be 2
        @($capabilities | Select-Object -ExpandProperty adapter -Unique) |
            Should -Be @('RenderKitRiff')
        @($capabilities[0].tags) | Should -Contain 'BWF:Description'
        @($capabilities[1].tags) | Should -Contain 'iXML:PROJECT'
    }

    It 'writes BEXT v2 and structured iXML while preserving other chunks' {
        $path = Join-Path $TestDrive 'combined.wav'
        New-TestWaveFile -Path $path -IncludeMetadata
        $timestamp = [datetime]::UtcNow.AddHours(-1)
        [IO.File]::SetLastWriteTimeUtc($path, $timestamp)

        $before = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitRiffLayout `
                    -Path $Path `
                    -PayloadChunkId @('bext', 'iXML', 'JUNK', 'data')
            }
        $beforeJunk = @($before.Chunks | Where-Object Id -eq 'JUNK')[0]
        $beforeData = @($before.Chunks | Where-Object Id -eq 'data')[0]

        $write = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Invoke-RenderKitRiffMetadataWrite `
                    -Path $Path `
                    -Metadata ([ordered]@{
                        BwfDescription = 'Updated BWF'
                        BwfOriginator = 'RenderKit'
                        BwfOriginationDate = '2026-07-03'
                        BwfOriginationTime = '11:22:33'
                        BwfTimeReferenceSamples = [uint64]987654321
                        BwfLoudnessValue = -23.0
                        BwfLoudnessRange = 7.5
                        IxmlProject = 'Writer Project'
                        IxmlScene = '17B'
                        IxmlTake = '8'
                        IxmlCircled = $true
                        IxmlTimestampSamplesSinceMidnight = [uint64]4294967298
                        IxmlSpeed = [PSCustomObject]@{
                            MasterSpeed = '24/1'
                            CurrentSpeed = '24/1'
                            TimecodeRate = '24/1'
                            TimecodeFlag = 'NDF'
                        }
                        IxmlTrackList = @(
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
                    })
            }

        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path -IncludeRaw
            }
        $after = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitRiffLayout `
                    -Path $Path `
                    -PayloadChunkId @('bext', 'iXML', 'JUNK', 'data')
            }
        $afterJunk = @($after.Chunks | Where-Object Id -eq 'JUNK')[0]
        $afterData = @($after.Chunks | Where-Object Id -eq 'data')[0]
        $bytes = [IO.File]::ReadAllBytes($path)

        $write.Verified | Should -BeTrue
        @($write.Chunks) | Should -Be @('bext', 'iXML')
        $read.Fields.BwfDescription | Should -Be 'Updated BWF'
        $read.Fields.BwfVersion | Should -Be 2
        $read.Fields.BwfLoudnessValue | Should -Be -23
        $read.Fields.BwfLoudnessRange | Should -Be 7.5
        $read.Fields.BwfTimeReferenceSamples | Should -Be 987654321
        $read.Fields.IxmlProject | Should -Be 'Writer Project'
        $read.Fields.IxmlTimestampSamplesSinceMidnight |
            Should -Be ([uint64]4294967298)
        @($read.Fields.IxmlTrackList).Count | Should -Be 2
        $read.Fields.IxmlTrackList[1].Name | Should -Be 'Lav'
        $read.Fields.IxmlSpeed.TimecodeRate | Should -Be '24/1'
        $read.FieldProvenance.IxmlTrackList.EffectiveSource |
            Should -Be 'EmbeddedRenderKitRiff'
        $read.Warnings | Should -BeNullOrEmpty

        @($afterJunk.Payload) | Should -Be @($beforeJunk.Payload)
        @($afterData.Payload) | Should -Be @($beforeData.Payload)
        $bytes[[int](
            [uint64]$afterJunk.DataOffset +
            [uint64]$afterJunk.LogicalSize
        )] | Should -Be 0x7f
        $afterData.LogicalSize | Should -Be $beforeData.LogicalSize
        $afterBext = @($after.Chunks | Where-Object Id -eq 'bext')[0]
        $afterBext.Payload[500] | Should -Be 0xab
        [Text.Encoding]::UTF8.GetString(
            @($after.Chunks | Where-Object Id -eq 'iXML')[0].Payload
        ) | Should -Match '<FOO>preserve-me</FOO>'
        [IO.File]::GetLastWriteTimeUtc($path) |
            Should -Be $timestamp
        @(Get-ChildItem `
            -LiteralPath $TestDrive `
            -Filter '.combined.renderkit-*').Count |
            Should -Be 0
    }

    It 'keeps RF64 and updates ds64 after inserting metadata chunks' {
        $path = Join-Path $TestDrive 'small.rf64'
        New-TestWaveFile -Path $path -Rf64

        $write = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Invoke-RenderKitRiffMetadataWrite `
                    -Path $Path `
                    -Metadata ([ordered]@{
                        BwfDescription = 'RF64 metadata'
                        IxmlProject = 'RF64 Project'
                    })
            }
        $layout = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitRiffLayout -Path $Path
            }
        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path
            }

        $write.Container | Should -Be 'RF64'
        $layout.ContainerId | Should -Be 'RF64'
        $layout.DeclaredSize32 | Should -Be ([uint32]::MaxValue)
        $layout.Ds64.RiffSize | Should -Be ($layout.FileLength - 8)
        $layout.Ds64.DataSize | Should -Be 4
        $read.Fields.BwfDescription | Should -Be 'RF64 metadata'
        $read.Fields.IxmlProject | Should -Be 'RF64 Project'
    }

    It 'uses the native writer through Add-Metadata' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        $path = Join-Path $projectRoot 'public.wav'
        New-TestWaveFile -Path $path

        $result = Add-Metadata `
            -Path $path `
            -Field IxmlProject `
            -Value 'Public Workflow' `
            -ProjectRoot $projectRoot `
            -Override
        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $path } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path
            }

        @($result.Embedded).Count | Should -Be 1
        $result.Embedded[0].Status | Should -Be 'Written'
        $result.Embedded[0].Adapter | Should -Be 'RenderKitRiff'
        $result.Embedded[0].Verified | Should -BeTrue
        $read.Fields.IxmlProject | Should -Be 'Public Workflow'
    }

    It 'restores the original bytes when validation rejects a BWF value' {
        $path = Join-Path $TestDrive 'invalid.wav'
        New-TestWaveFile -Path $path -IncludeMetadata
        $beforeHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

        {
            InModuleScope `
                -ModuleName RenderKit `
                -Parameters @{ Path = $path } `
                -ScriptBlock {
                    param($Path)
                    Invoke-RenderKitRiffMetadataWrite `
                        -Path $Path `
                        -Metadata ([ordered]@{
                            BwfOriginator = 'Nicht-ASCII-Ä'
                        })
                }
        } | Should -Throw '*only accepts ASCII*'

        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash |
            Should -Be $beforeHash
        @(Get-ChildItem `
            -LiteralPath $TestDrive `
            -Filter '.invalid.renderkit-*').Count |
            Should -Be 0
    }

    It 'rejects conflicting aliases before replacing the file' {
        $path = Join-Path $TestDrive 'conflict.wav'
        New-TestWaveFile -Path $path
        $beforeHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

        {
            InModuleScope `
                -ModuleName RenderKit `
                -Parameters @{ Path = $path } `
                -ScriptBlock {
                    param($Path)
                    Invoke-RenderKitRiffMetadataWrite `
                        -Path $Path `
                        -Metadata ([ordered]@{
                            IxmlScene = '10A'
                            Scene = '10B'
                        })
                }
        } | Should -Throw '*conflicting values*'

        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash |
            Should -Be $beforeHash
    }
}
