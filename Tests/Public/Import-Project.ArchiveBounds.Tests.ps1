BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repositoryRoot 'RenderKit.psd1') -Force

    function New-ArchiveBoundsTestZip {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][object[]]$Entries
        )

        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force
        }
        $zip = [System.IO.Compression.ZipFile]::Open(
            $Path,
            [System.IO.Compression.ZipArchiveMode]::Create
        )
        try {
            foreach ($definition in $Entries) {
                $entry = $zip.CreateEntry([string]$definition.Name)
                $stream = $entry.Open()
                try {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$definition.Content)
                    $stream.Write($bytes, 0, $bytes.Length)
                }
                finally {
                    $stream.Dispose()
                }
            }
        }
        finally {
            $zip.Dispose()
        }
    }

    function New-ArchiveBoundsManifest {
        param(
            [string]$RelativePath = 'clip.txt',
            [int64]$SizeBytes = 5
        )

        return [xml](
            '<RenderKitProjectManifest schemaVersion="1.0">' +
            '<Export mode="SelfContained" />' +
            '<Resources><Templates /><Mappings /></Resources>' +
            '<Metadata />' +
            '<Files><File relativePath="' + $RelativePath + '" sizeBytes="' + $SizeBytes + '" /></Files>' +
            '</RenderKitProjectManifest>'
        )
    }
}

AfterAll {
    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
}

Describe 'RenderKit project archive extraction bounds' {
    It 'accepts a bounded archive whose project entry matches the manifest' {
        $archive = Join-Path $TestDrive 'valid.rkitpkg'
        New-ArchiveBoundsTestZip -Path $archive -Entries @(
            [PSCustomObject]@{ Name = 'project.xml'; Content = '<x />' },
            [PSCustomObject]@{ Name = 'project/clip.txt'; Content = '12345' }
        )
        $manifest = New-ArchiveBoundsManifest -SizeBytes 5

        $result = InModuleScope RenderKit -Parameters @{
            Archive = $archive
            Manifest = $manifest
            Destination = $TestDrive
        } {
            Test-RenderKitProjectArchivePreflight `
                -ArchivePath $Archive `
                -Manifest $Manifest `
                -DestinationRoot $Destination `
                -IncludeMetadata $false `
                -IncludeProjectFiles $true `
                -MinimumFreeSpaceReserveBytes 0
        }

        $result.RequiredEntryCount | Should -Be 1
        $result.TotalRequiredBytes | Should -Be 5
    }

    It 'rejects duplicate or case-colliding archive entry names' {
        $archive = Join-Path $TestDrive 'duplicate.rkitpkg'
        New-ArchiveBoundsTestZip -Path $archive -Entries @(
            [PSCustomObject]@{ Name = 'project/clip.txt'; Content = 'one' },
            [PSCustomObject]@{ Name = 'PROJECT/clip.txt'; Content = 'two' }
        )

        {
            InModuleScope RenderKit -Parameters @{ Archive = $archive } {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
                try {
                    Get-RenderKitProjectArchiveEntryIndex -Archive $zip
                }
                finally {
                    $zip.Dispose()
                }
            }
        } | Should -Throw '*duplicate or case-colliding*'
    }

    It 'rejects an archive entry whose expanded size disagrees with the manifest' {
        $archive = Join-Path $TestDrive 'size-mismatch.rkitpkg'
        New-ArchiveBoundsTestZip -Path $archive -Entries @(
            [PSCustomObject]@{ Name = 'project/clip.txt'; Content = '1234' }
        )
        $manifest = New-ArchiveBoundsManifest -SizeBytes 5

        {
            InModuleScope RenderKit -Parameters @{
                Archive = $archive
                Manifest = $manifest
                Destination = $TestDrive
            } {
                Test-RenderKitProjectArchivePreflight `
                    -ArchivePath $Archive `
                    -Manifest $Manifest `
                    -DestinationRoot $Destination `
                    -IncludeMetadata $false `
                    -IncludeProjectFiles $true `
                    -MinimumFreeSpaceReserveBytes 0
            }
        } | Should -Throw '*manifest expects 5 bytes*'
    }

    It 'rejects excessive archive entry counts before extraction' {
        $archive = Join-Path $TestDrive 'too-many.rkitpkg'
        New-ArchiveBoundsTestZip -Path $archive -Entries @(
            [PSCustomObject]@{ Name = 'one.txt'; Content = '1' },
            [PSCustomObject]@{ Name = 'two.txt'; Content = '2' }
        )

        {
            InModuleScope RenderKit -Parameters @{ Archive = $archive } {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
                try {
                    Get-RenderKitProjectArchiveEntryIndex `
                        -Archive $zip `
                        -MaximumArchiveEntries 1
                }
                finally {
                    $zip.Dispose()
                }
            }
        } | Should -Throw '*maximum allowed is 1*'
    }

    It 'does not create output when the bounded extractor rejects the entry size' {
        $archive = Join-Path $TestDrive 'bounded.rkitpkg'
        $destination = Join-Path $TestDrive 'output/clip.txt'
        New-ArchiveBoundsTestZip -Path $archive -Entries @(
            [PSCustomObject]@{ Name = 'project/clip.txt'; Content = '12345' }
        )

        {
            InModuleScope RenderKit -Parameters @{
                Archive = $archive
                Destination = $destination
            } {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
                try {
                    $entry = $zip.GetEntry('project/clip.txt')
                    Expand-RenderKitProjectArchiveEntryBounded `
                        -Entry $entry `
                        -DestinationPath $Destination `
                        -ExpectedSize 4
                }
                finally {
                    $zip.Dispose()
                }
            }
        } | Should -Throw '*expected 4 bytes*'

        Test-Path -LiteralPath $destination | Should -BeFalse
    }
}
