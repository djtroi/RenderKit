BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectImportManifestSecurityService.ps1')

    function New-TestProjectArchive {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Xml
        )
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force
        }
        $zip = [System.IO.Compression.ZipFile]::Open(
            $Path,
            [System.IO.Compression.ZipArchiveMode]::Create
        )
        try {
            $entry = $zip.CreateEntry('project.xml')
            $stream = $entry.Open()
            try {
                $writer = [System.IO.StreamWriter]::new(
                    $stream,
                    [System.Text.UTF8Encoding]::new($false)
                )
                try {
                    $writer.Write($Xml)
                }
                finally {
                    $writer.Dispose()
                }
            }
            finally {
                $stream.Dispose()
            }
        }
        finally {
            $zip.Dispose()
        }
    }
}

Describe 'RenderKit project manifest parser security' {
    It 'parses a normal bounded project manifest' {
        $archive = Join-Path $TestDrive 'normal.rkit'
        New-TestProjectArchive -Path $archive -Xml @'
<?xml version="1.0" encoding="utf-8"?>
<RenderKitProjectManifest schemaVersion="1.0">
  <Project name="Example" sourceRootName="Example" />
</RenderKitProjectManifest>
'@

        $manifest = Read-RenderKitProjectArchiveManifestSecure -Path $archive

        $manifest.RenderKitProjectManifest.schemaVersion | Should -Be '1.0'
        $manifest.RenderKitProjectManifest.Project.name | Should -Be 'Example'
    }

    It 'rejects DTD and entity declarations before expansion' {
        $archive = Join-Path $TestDrive 'dtd.rkit'
        New-TestProjectArchive -Path $archive -Xml @'
<?xml version="1.0"?>
<!DOCTYPE RenderKitProjectManifest [
  <!ENTITY payload "expanded-value">
]>
<RenderKitProjectManifest schemaVersion="1.0">
  <Project name="&payload;" sourceRootName="Example" />
</RenderKitProjectManifest>
'@

        {
            Read-RenderKitProjectArchiveManifestSecure -Path $archive
        } | Should -Throw
    }

    It 'rejects an oversized uncompressed project.xml before XML parsing' {
        $archive = Join-Path $TestDrive 'oversized.rkit'
        $payload = '<RenderKitProjectManifest schemaVersion="1.0"><Project name="' +
            ('A' * 4096) +
            '" /></RenderKitProjectManifest>'
        New-TestProjectArchive -Path $archive -Xml $payload

        {
            Read-RenderKitProjectArchiveManifestSecure `
                -Path $archive `
                -MaximumManifestBytes 512
        } | Should -Throw '*maximum allowed uncompressed size*'
    }
}
