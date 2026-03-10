function Get-BackupFileHashIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [Parameter(Mandatory)]
        [string]$BasePath,
        [ValidateSet("SHA256", "SHA1", "MD5")]
        [string]$Algorithm = "SHA256"
    )

    $resolvedRootPath = (Resolve-Path -Path $RootPath -ErrorAction Stop).ProviderPath
    $resolvedBasePath = (Resolve-Path -Path $BasePath -ErrorAction Stop).ProviderPath

    $index = @{}
    $files = @(
        Get-ChildItem -Path $resolvedRootPath -Recurse -File -Force -ErrorAction SilentlyContinue
    )

    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($resolvedBasePath.Length).TrimStart('\', '/')
        $normalizedRelativePath = $relativePath -replace '\\', '/'
        $hash = Get-FileHash -Path $file.FullName -Algorithm $Algorithm -ErrorAction Stop

        $index[$normalizedRelativePath] = [PSCustomObject]@{
            RelativePath = $normalizedRelativePath
            FullPath     = $file.FullName
            Length       = [int64]$file.Length
            Algorithm    = $Algorithm
            Hash         = [string]$hash.Hash
        }
    }

    return $index
}
