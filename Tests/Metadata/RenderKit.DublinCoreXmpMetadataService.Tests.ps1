Describe 'RenderKit Dublin Core XMP metadata mapping' {
    BeforeAll {
        $script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:RepositoryRoot 'RenderKit.psd1') -Force
    }

    It 'covers all fifteen DCMES elements without inventing registry fields' {
        $result = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $map = Read-RenderKitDublinCoreXmpMap -Reload
            $registry = Read-RenderKitMetadataFieldRegistry
            $registryFields = @($registry.fields | ForEach-Object { [string]$_.name })

            [PSCustomObject]@{
                ArtifactType = [string]$map.artifactType
                StandardVersion = [string]$map.standardVersion
                MappedCount = @($map.fields).Count
                UnmappedCount = @($map.unmappedElements).Count
                TotalCount = @($map.fields).Count + @($map.unmappedElements).Count
                MissingFields = @(
                    $map.fields |
                        Where-Object { $registryFields -notcontains [string]$_.field } |
                        ForEach-Object { [string]$_.field }
                )
            }
        }

        $result.ArtifactType | Should -Be 'DublinCoreXmpMap'
        $result.StandardVersion | Should -Be '1.1'
        $result.MappedCount | Should -Be 8
        $result.UnmappedCount | Should -Be 7
        $result.TotalCount | Should -Be 15
        $result.MissingFields | Should -BeNullOrEmpty
    }

    It 'normalizes repeated values and applies explicit scalar constraints' {
        $fields = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $raw = [PSCustomObject][ordered]@{
                'XMP-dc:Contributor' = @('Editor One', 'Editor Two')
                'XMP-dc:Publisher' = @('Primary Publisher', 'Secondary Publisher')
                'XMP-dc:Subject' = @('architecture', 'design')
            }

            ConvertFrom-RenderKitDublinCoreXmpMetadata -Raw $raw
        }

        @($fields.Contributor).Count | Should -Be 2
        @($fields.Contributor) | Should -Contain 'Editor Two'
        $fields.Publisher | Should -Be 'Primary Publisher'
        @($fields.Subject).Count | Should -Be 2
    }

    It 'keeps semantically ambiguous Dublin Core source unmapped' {
        $fields = InModuleScope -ModuleName RenderKit -ScriptBlock {
            $raw = [PSCustomObject][ordered]@{
                'XMP-dc:Source' = 'urn:example:source-resource'
            }

            ConvertFrom-RenderKitDublinCoreXmpMetadata -Raw $raw
        }

        $fields.Contains('Source') | Should -BeFalse
    }

    It 'roundtrips scalar and repeated Dublin Core fields through ExifTool' {
        $resolved = InModuleScope -ModuleName RenderKit -ScriptBlock {
            Resolve-RenderKitExifToolReader
        }
        if (-not [bool]$resolved.Available) {
            Set-ItResult -Skipped -Because 'No ExifTool runtime is available on this test host.'
            return
        }

        $samplePath = Join-Path $TestDrive 'dublin-core-roundtrip.png'
        $pngBytes = [Convert]::FromBase64String(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
        )
        [System.IO.File]::WriteAllBytes($samplePath, $pngBytes)

        InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $samplePath } `
            -ScriptBlock {
                param($Path)
                Invoke-RenderKitExifToolCommand `
                    -Arguments @(
                        '-overwrite_original',
                        '-XMP-dc:Title-de=Deutscher Titel',
                        $Path
                    ) |
                    Out-Null
            }
        $write = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $samplePath } `
            -ScriptBlock {
                param($Path)
                Invoke-RenderKitEmbeddedMetadataWrite `
                    -Path $Path `
                    -Metadata ([ordered]@{
                        Contributor = @('Editor One', 'Editor Two')
                        Publisher = 'RenderKit Press'
                        Subject = @('architecture', 'design')
                        Title = 'Dublin Core integration'
                    })
            }
        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $samplePath } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path -IncludeRaw
            }
        $languageAlternative = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $samplePath } `
            -ScriptBlock {
                param($Path)
                $result = Invoke-RenderKitExifToolCommand `
                    -Arguments @(
                        '-json',
                        '-G1',
                        '-XMP-dc:Title-de',
                        $Path
                    )
                return ($result.Output -join "`n") |
                    ConvertFrom-Json |
                    Select-Object -First 1
            }

        @($write | Where-Object Status -eq 'Written').Count | Should -Be 4
        @($read.Fields.Contributor) | Should -Contain 'Editor Two'
        $read.Fields.Publisher | Should -Be 'RenderKit Press'
        @($read.Fields.Subject) | Should -Contain 'design'
        $read.Fields.Title | Should -Be 'Dublin Core integration'
        @($read.Raw.ExifTool.'XMP-dc:Contributor') | Should -Contain 'Editor One'
        @($read.Raw.ExifTool.'XMP-dc:Subject') | Should -Contain 'architecture'
        $read.Raw.ExifTool.'IPTC:ObjectName' | Should -Be 'Dublin Core integration'
        $languageAlternative.'XMP-dc:Title-de' | Should -Be 'Deutscher Titel'
        (Test-Path -LiteralPath "${samplePath}_original") | Should -BeFalse
    }
}
