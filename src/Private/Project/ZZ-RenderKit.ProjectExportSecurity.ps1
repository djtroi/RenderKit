function Get-RenderKitProjectExportArchiveSourceFile {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath
    )

    $file = Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
    if (-not ($file -is [System.IO.FileInfo])) {
        throw "Project export source '$SourcePath' is not a regular file."
    }

    if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Project export source '$SourcePath' is a symbolic link or reparse point."
    }

    return $file
}

# Security override loaded after RenderKit.ProjectExportService.ps1. Archive source
# paths are validated at the final read boundary so project files, metadata,
# templates, and mappings all receive the same no-reparse policy.
function Add-RenderKitFileToZipArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$EntryName,
        [ValidateSet('NoCompression', 'Fastest', 'Optimal')]
        [string]$DefaultCompressionLevel = 'Optimal'
    )

    $file = Get-RenderKitProjectExportArchiveSourceFile -SourcePath $SourcePath
    $level = Get-RenderKitProjectArchiveCompressionLevel `
        -File $file `
        -DefaultCompressionLevel $DefaultCompressionLevel
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $Archive,
        $file.FullName,
        ($EntryName -replace '\\', '/'),
        $level
    )
}
