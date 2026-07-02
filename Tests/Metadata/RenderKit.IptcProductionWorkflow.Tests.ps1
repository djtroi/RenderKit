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
}
