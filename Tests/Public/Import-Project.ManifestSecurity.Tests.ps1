BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectManifestSecurity.ps1')

    function New-TestProjectArchive {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Manifest
        )

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
                    $writer.Write($Manifest)
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

Describe 'Project archive manifest parser security' {
    It 'loads a normal manifest through the hardened XML reader' {
        $archive = Join-Path $TestDrive 'valid.rkitpkg'
        New-TestProjectArchive -Path $archive -Manifest @'
<RenderKitProjectManifest schemaVersion="1.0">
  <Project name="Example" sourceRootName="Example" />
</RenderKitProjectManifest>
'@

        $document = Read-RenderKitProjectArchiveManifest -Path $archive

        $document.RenderKitProjectManifest.schemaVersion | Should -Be '1.0'
        $document.RenderKitProjectManifest.Project.name | Should -Be 'Example'
    }

    It 'rejects DTD declarations from untrusted manifests' {
        $archive = Join-Path $TestDrive 'dtd.rkitpkg'
        New-TestProjectArchive -Path $archive -Manifest @'
<!DOCTYPE RenderKitProjectManifest [
  <!ENTITY payload "expanded">
]>
<RenderKitProjectManifest schemaVersion="1.0">
  <Project name="&payload;" sourceRootName="Example" />
</RenderKitProjectManifest>
'@

        {
            Read-RenderKitProjectArchiveManifest -Path $archive
        } | Should -Throw
    }

    It 'rejects a manifest whose uncompressed entry exceeds the configured limit' {
        $archive = Join-Path $TestDrive 'oversized.rkitpkg'
        New-TestProjectArchive `
            -Path $archive `
            -Manifest '<RenderKitProjectManifest schemaVersion="1.0" />'

        {
            Read-RenderKitProjectArchiveManifest `
                -Path $archive `
                -MaximumManifestBytes 16
        } | Should -Throw '*exceeds*byte limit*'
    }
}
