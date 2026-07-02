Describe 'RenderKit IPTC Core metadata mapping' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:RepositoryRoot 'RenderKit.psd1') -Force
        $script:RenderKitModule = Get-Module RenderKit
    }

    It 'loads a versioned IPTC Core map whose fields exist in the registry' {
        $result = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $map = Read-RenderKitIptcMetadataMap -Reload
            $registry = Read-RenderKitMetadataFieldRegistry
            $registryFields = @($registry.fields | ForEach-Object { [string]$_.name })

            [PSCustomObject]@{
                ArtifactType = [string]$map.artifactType
                StandardVersion = [string]$map.standardVersion
                Profile = [string]$map.profile
                FieldCount = @($map.fields).Count
                MissingFields = @(
                    $map.fields |
                        Where-Object { $registryFields -notcontains [string]$_.field } |
                        ForEach-Object { [string]$_.field }
                )
            }
        }

        $result.ArtifactType | Should -Be 'IptcMetadataMap'
        $result.StandardVersion | Should -Be '2025.1'
        $result.Profile | Should -Be 'IPTC Core 1.5 + IPTC Extension 1.9'
        $result.FieldCount | Should -BeGreaterThan 50
        $result.MissingFields | Should -BeNullOrEmpty
    }

    It 'prefers current XMP values and preserves multiple values as arrays' {
        $fields = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $raw = [PSCustomObject][ordered]@{
                'IPTC:Headline' = 'Legacy headline'
                'XMP-photoshop:Headline' = 'Current headline'
                'IPTC:Keywords' = @('legacy')
                'XMP-dc:Subject' = @('press', 'launch')
            }

            ConvertFrom-RenderKitIptcMetadata -Raw $raw
        }

        $fields.Headline | Should -Be 'Current headline'
        @($fields.Keywords).Count | Should -Be 2
        @($fields.Keywords)[0] | Should -Be 'press'
        @($fields.Keywords)[1] | Should -Be 'launch'
    }

    It 'does not split a scalar value on punctuation' {
        $fields = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $raw = [PSCustomObject][ordered]@{
                'IPTC:Keywords' = 'Berlin, Germany'
            }

            ConvertFrom-RenderKitIptcMetadata -Raw $raw
        }

        @($fields.Keywords).Count | Should -Be 1
        @($fields.Keywords)[0] | Should -Be 'Berlin, Germany'
    }

    It 'maps Extension structures without flattening ambiguous values' {
        $result = InModuleScope -ModuleName RenderKit -ScriptBlock {
            ConvertFrom-RenderKitIptcMetadataDetailed `
                -Raw ([PSCustomObject][ordered]@{
                    'XMP-plus:CopyrightOwner' = @(
                        [PSCustomObject]@{
                            CopyrightOwnerID = 'owner-1'
                            CopyrightOwnerName = 'First owner'
                        },
                        [PSCustomObject]@{
                            CopyrightOwnerID = 'owner-2'
                            CopyrightOwnerName = 'Second owner'
                        }
                    )
                    'XMP-iptcExt:PersonInImageWDetails' = @(
                        [PSCustomObject]@{
                            PersonName = 'Ada Lovelace'
                            PersonId = @('https://example.test/person/ada')
                        }
                    )
                })
        }

        $result.Fields.CopyrightOwner | Should -BeNullOrEmpty
        @($result.Fields.PersonShownDetails).Count | Should -Be 1
        $result.Fields.PersonShownDetails[0].PersonName |
            Should -Be 'Ada Lovelace'
        @(
            $result.Conflicts |
                Where-Object {
                    $_.Field -eq 'CopyrightOwner' -and
                    $_.Reason -eq 'AmbiguousStructure'
                }
        ).Count | Should -Be 1
    }

    It 'maps controlled vocabulary URIs and rejects ambiguous writes' {
        $result = InModuleScope -ModuleName RenderKit -ScriptBlock {
            [PSCustomObject]@{
                Read = ConvertFrom-RenderKitIptcControlledVocabularyValue `
                    -Vocabulary DigitalSourceType `
                    -Value (
                        'http://cv.iptc.org/newscodes/' +
                        'digitalsourcetype/trainedAlgorithmicMedia'
                    )
                Write = ConvertTo-RenderKitIptcControlledVocabularyValue `
                    -Vocabulary DigitalSourceType `
                    -Value OriginalDigitalCapture
                AmbiguousWrite =
                    ConvertTo-RenderKitIptcControlledVocabularyValue `
                        -Vocabulary DigitalSourceType `
                        -Value DigitizedFromFilm
            }
        }

        $result.Read | Should -Be 'TrainedAlgorithmicMedia'
        $result.Write | Should -Be (
            'http://cv.iptc.org/newscodes/' +
            'digitalsourcetype/digitalCapture'
        )
        $result.AmbiguousWrite | Should -BeNullOrEmpty
    }

    It 'roundtrips IPTC Core scalar and list fields through the bundled runtime' {
        $resolved = InModuleScope -ModuleName RenderKit -ScriptBlock {
            Resolve-RenderKitExifToolReader
        }
        if (-not [bool]$resolved.Available) {
            Set-ItResult -Skipped -Because 'No ExifTool runtime is available on this test host.'
            return
        }

        $samplePath = Join-Path $TestDrive 'iptc-roundtrip.png'
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
                    -Metadata ([ordered]@{
                        Headline = 'IPTC integration'
                        Keywords = @('press', 'launch')
                    })
            }
        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $samplePath } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path -IncludeRaw
            }

        @($write | Where-Object Status -eq 'Written').Count | Should -Be 2
        $read.Fields.Headline | Should -Be 'IPTC integration'
        @($read.Fields.Keywords).Count | Should -Be 2
        @($read.Fields.Keywords) | Should -Contain 'press'
        @($read.Fields.Keywords) | Should -Contain 'launch'
        $read.Raw.ExifTool.'XMP-photoshop:Headline' | Should -Be 'IPTC integration'
        @($read.Raw.ExifTool.'XMP-dc:Subject') | Should -Contain 'press'
        @($read.Raw.ExifTool.'IPTC:Keywords') | Should -Contain 'launch'
        (Test-Path -LiteralPath "${samplePath}_original") | Should -BeFalse
    }

    It 'roundtrips Extension structures and controlled vocabulary values' {
        $resolved = InModuleScope -ModuleName RenderKit -ScriptBlock {
            Resolve-RenderKitExifToolReader
        }
        if (-not [bool]$resolved.Available) {
            Set-ItResult -Skipped -Because 'No ExifTool runtime is available on this test host.'
            return
        }

        $samplePath = Join-Path $TestDrive 'iptc-extension-roundtrip.png'
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
                    -Metadata ([ordered]@{
                        DigitalSourceType = 'TrainedAlgorithmicMedia'
                        PersonShownDetails = @(
                            [PSCustomObject]@{
                                name = 'Alice, Bob'
                                id = @('https://example.test/person/alice')
                                description = 'Editor=Lead'
                            }
                        )
                    })
            }
        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $samplePath } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path -IncludeRaw
            }

        @($write | Where-Object Status -eq 'Written').Count | Should -Be 2
        $read.Fields.DigitalSourceType |
            Should -Be 'TrainedAlgorithmicMedia'
        @($read.Fields.PersonShownDetails).Count | Should -Be 1
        $read.Fields.PersonShownDetails[0].PersonName |
            Should -Be 'Alice, Bob'
        $read.Fields.PersonShownDetails[0].PersonDescription |
            Should -Be 'Editor=Lead'
        $read.FieldProvenance.DigitalSourceType.EffectiveSource |
            Should -Be 'EmbeddedIPTC'
    }

    It 'reads the official reference image when a smoke path is configured' {
        $referencePath = [Environment]::GetEnvironmentVariable(
            'RENDERKIT_IPTC_REFERENCE_IMAGE'
        )
        if ([string]::IsNullOrWhiteSpace($referencePath) -or
            -not (Test-Path -LiteralPath $referencePath -PathType Leaf)) {
            Set-ItResult `
                -Skipped `
                -Because 'Set RENDERKIT_IPTC_REFERENCE_IMAGE for the cross-platform reference smoke.'
            return
        }

        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $referencePath } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path
            }

        $read.IsSupported | Should -BeTrue
        $read.IptcState | Should -BeIn @('Embedded', 'Conflicting')
        @($read.Fields.ArtworkOrObject).Count | Should -BeGreaterThan 0
        @($read.Fields.PersonShownDetails).Count | Should -BeGreaterThan 0
        @($read.Fields.ProductShown).Count | Should -BeGreaterThan 0
    }
}
