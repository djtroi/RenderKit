function Save-BackupManifest {
    [CmdletBinding()]
    param(
    [Parameter(Mandatory)]
    [pscustomobject]$Manifest,
    [Parameter(Mandatory)]
    [string]$ProjectRoot
    )

    $renderKitPath = Join-Path $ProjectRoot ".renderkit"

    if (!(Test-Path $renderKitPath)) {
        New-Item -ItemType Directory -Path $renderKitPath | Out-Null
    }

    $manifestPath = Join-Path $renderKitPath "backup.manifest.json"

    $Manifest |
    ConvertTo-Json -Depth 10 | 
    Set-Content -Path $manifestPath -Encoding UTF8

    return $manifestPath
}
