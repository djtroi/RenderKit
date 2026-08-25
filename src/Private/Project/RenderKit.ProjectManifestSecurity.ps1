function Read-RenderKitProjectArchiveManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1, 268435456)]
        [long]$MaximumManifestBytes = 67108864
    )

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('project.xml')
        if (-not $entry) {
            throw "Archive '$Path' does not contain project.xml."
        }
        if ([int64]$entry.Length -gt $MaximumManifestBytes) {
            throw (
                "Project manifest in '$Path' exceeds the " +
                "$MaximumManifestBytes byte limit."
            )
        }

        $stream = $entry.Open()
        try {
            $settings = [System.Xml.XmlReaderSettings]::new()
            $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
            $settings.XmlResolver = $null
            $settings.MaxCharactersInDocument = $MaximumManifestBytes
            $settings.MaxCharactersFromEntities = 0
            $settings.CloseInput = $false

            $reader = [System.Xml.XmlReader]::Create($stream, $settings)
            try {
                $document = [System.Xml.XmlDocument]::new()
                $document.XmlResolver = $null
                $document.Load($reader)
                return $document
            }
            finally {
                $reader.Dispose()
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
