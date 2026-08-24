function Read-RenderKitProjectArchiveManifestSecure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int64]$MaximumManifestBytes = 16MB
    )

    if ($MaximumManifestBytes -le 0) {
        throw 'Maximum manifest size must be greater than zero.'
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('project.xml')
        if (-not $entry) {
            throw "Archive '$Path' does not contain project.xml."
        }
        if ([int64]$entry.Length -gt $MaximumManifestBytes) {
            throw (
                "Archive project.xml exceeds the maximum allowed uncompressed " +
                "size of $MaximumManifestBytes bytes."
            )
        }

        $settings = [System.Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $settings.MaxCharactersInDocument = $MaximumManifestBytes
        $settings.MaxCharactersFromEntities = 0
        $settings.IgnoreComments = $true
        $settings.IgnoreProcessingInstructions = $true

        $stream = $entry.Open()
        try {
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
