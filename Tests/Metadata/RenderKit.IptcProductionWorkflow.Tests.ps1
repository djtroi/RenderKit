Describe 'RenderKit IPTC production workflows' {
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
        $script:RenderKitModule = Get-Module RenderKit
        $script:PngBytes = [Convert]::FromBase64String(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
        )
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
        $env:RENDERKIT_HOME = $script:PreviousHome
    }

    It 'applies Extension fields through metadata templates' {
        $samplePath = Join-Path $TestDrive 'template-target.png'
        [System.IO.File]::WriteAllBytes($samplePath, $script:PngBytes)

        New-MetadataTemplate -Name 'iptc-extension' | Out-Null
        Add-MetadataTemplateField `
            -Name 'iptc-extension' `
            -Field DigitalSourceType `
            -Value TrainedAlgorithmicMedia |
            Out-Null
        Add-MetadataTemplateField `
            -Name 'iptc-extension' `
            -Field PersonShown `
            -Value @('Alice', 'Bob') |
            Out-Null

        $applied = Add-MetadataTemplate `
            -Name 'iptc-extension' `
            -Path $samplePath
        $read = Get-Metadata -Path $samplePath -IncludeMetadata

        @($applied.Changes).Count | Should -Be 2
        @($applied.Embedded | Where-Object Status -eq 'Written').Count |
            Should -Be 2
        $read.Metadata.DigitalSourceType |
            Should -Be 'TrainedAlgorithmicMedia'
        @($read.Metadata.PersonShown) | Should -Contain 'Alice'
        @($read.Metadata.PersonShown) | Should -Contain 'Bob'
    }

    It 'exports and imports mapped IPTC values without flattening lists' {
        $sourceRoot = Join-Path $TestDrive 'source-project'
        $targetRoot = Join-Path $TestDrive 'target-project'
        New-Item -ItemType Directory -Path $sourceRoot, $targetRoot |
            Out-Null
        $sourcePath = Join-Path $sourceRoot 'frame.png'
        $targetPath = Join-Path $targetRoot 'frame.png'
        [System.IO.File]::WriteAllBytes($sourcePath, $script:PngBytes)
        [System.IO.File]::WriteAllBytes($targetPath, $script:PngBytes)

        Add-Metadata `
            -Path $sourcePath `
            -ProjectRoot $sourceRoot `
            -Field Headline `
            -Value 'Imported IPTC' `
            -Override |
            Out-Null
        Add-Metadata `
            -Path $sourcePath `
            -ProjectRoot $sourceRoot `
            -Field Keywords `
            -Value @('Berlin, Germany', 'Press launch') `
            -Override |
            Out-Null

        $exportPath = Join-Path $TestDrive 'iptc-export.json'
        Export-Metadata `
            -Path $sourcePath `
            -ProjectRoot $sourceRoot `
            -DestinationPath $exportPath |
            Out-Null
        $export = Get-Content -LiteralPath $exportPath -Raw |
            ConvertFrom-Json

        @($export.profiles) | Should -Contain 'IPTC'
        $export.records[0].profiles.iptc.Headline |
            Should -Be 'Imported IPTC'
        @($export.records[0].profiles.iptc.Keywords).Count |
            Should -Be 2

        $imported = Import-Metadata `
            -Path $exportPath `
            -ProjectRoot $targetRoot `
            -ConflictAction Overwrite
        $read = Get-Metadata -Path $targetPath -IncludeMetadata

        $imported.Succeeded | Should -Be 1
        $imported.Failed | Should -Be 0
        $read.Metadata.Headline | Should -Be 'Imported IPTC'
        @($read.Metadata.Keywords).Count | Should -Be 2
        @($read.Metadata.Keywords)[0] | Should -Be 'Berlin, Germany'
        @($read.Metadata.Keywords)[1] | Should -Be 'Press launch'
    }

    It 'exports and imports Dublin Core and XMP profiles through a sidecar' {
        $available = InModuleScope -ModuleName RenderKit -ScriptBlock {
            [bool](Resolve-RenderKitExifToolReader).Available
        }
        if (-not $available) {
            Set-ItResult -Skipped -Because 'No ExifTool runtime is available.'
            return
        }
        $sourceRoot = Join-Path $TestDrive 'xmp-source-project'
        $targetRoot = Join-Path $TestDrive 'xmp-target-project'
        New-Item -ItemType Directory -Path $sourceRoot, $targetRoot |
            Out-Null
        $sourcePath = Join-Path $sourceRoot 'frame.png'
        $targetPath = Join-Path $targetRoot 'frame.png'
        [System.IO.File]::WriteAllBytes($sourcePath, $script:PngBytes)
        [System.IO.File]::WriteAllBytes($targetPath, $script:PngBytes)

        foreach ($entry in @(
            @{ Field = 'Title'; Value = 'XMP profile export' },
            @{ Field = 'Contributor'; Value = @('Editor One', 'Editor Two') },
            @{ Field = 'Rating'; Value = 4 },
            @{
                Field = 'LicenseUrl'
                Value = 'https://creativecommons.org/licenses/by/4.0/'
            }
        )) {
            Add-Metadata `
                -Path $sourcePath `
                -ProjectRoot $sourceRoot `
                -Field $entry.Field `
                -Value $entry.Value `
                -Override `
                -XmpSidecar |
                Out-Null
        }

        $exportPath = Join-Path $TestDrive 'xmp-export.json'
        Export-Metadata `
            -Path $sourcePath `
            -ProjectRoot $sourceRoot `
            -DestinationPath $exportPath |
            Out-Null
        $export = Get-Content -LiteralPath $exportPath -Raw |
            ConvertFrom-Json

        @($export.profiles) | Should -Contain 'DublinCoreXmp'
        @($export.profiles) | Should -Contain 'XMP'
        $export.records[0].profiles.dublinCoreXmp.Title |
            Should -Be 'XMP profile export'
        @($export.records[0].profiles.dublinCoreXmp.Contributor).Count |
            Should -Be 2
        $export.records[0].profiles.xmp.Rating | Should -Be 4
        $export.records[0].profiles.xmp.LicenseUrl |
            Should -Be 'https://creativecommons.org/licenses/by/4.0/'

        $imported = Import-Metadata `
            -Path $exportPath `
            -ProjectRoot $targetRoot `
            -ConflictAction Overwrite `
            -XmpSidecar
        $read = InModuleScope `
            -ModuleName RenderKit `
            -Parameters @{ Path = $targetPath } `
            -ScriptBlock {
                param($Path)
                Read-RenderKitFileMetadata -Path $Path
            }

        $imported.Succeeded | Should -Be 1
        $imported.Failed | Should -Be 0
        $imported.Profiles | Should -Contain 'DublinCoreXmp'
        $imported.Profiles | Should -Contain 'XMP'
        $read.Fields.Title | Should -Be 'XMP profile export'
        @($read.Fields.Contributor) | Should -Contain 'Editor Two'
        $read.Fields.Rating | Should -Be 4
        $read.Fields.LicenseUrl |
            Should -Be 'https://creativecommons.org/licenses/by/4.0/'
        $read.XmpState | Should -Be 'Sidecar'
    }
}
