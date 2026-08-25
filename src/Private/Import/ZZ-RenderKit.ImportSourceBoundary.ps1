function Get-RenderKitImportFileCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath
    )

    $rootDirectory = [System.IO.DirectoryInfo]::new($SourcePath)
    if (-not $rootDirectory.Exists) {
        Write-RenderKitLog -Level Error -Message "Source path '$SourcePath' does not exist."
        throw "Source path '$SourcePath' does not exist."
    }

    $files = New-Object System.Collections.Generic.List[object]
    $pendingDirectories = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pendingDirectories.Push($rootDirectory)

    while ($pendingDirectories.Count -gt 0) {
        $currentDirectory = $pendingDirectories.Pop()

        try {
            foreach ($subDirectory in $currentDirectory.EnumerateDirectories()) {
                if (($subDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    Write-RenderKitLog `
                        -Level Warning `
                        -Message "Skipping import directory reparse point '$($subDirectory.FullName)'."
                    continue
                }
                $pendingDirectories.Push($subDirectory)
            }
        }
        catch {
            Write-RenderKitLog -Level Debug -Message "Skipping directory '$($currentDirectory.FullName)': $_"
        }

        try {
            foreach ($file in $currentDirectory.EnumerateFiles()) {
                if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    Write-RenderKitLog `
                        -Level Warning `
                        -Message "Skipping import file reparse point '$($file.FullName)'."
                    continue
                }

                $relativePath = $file.FullName.Substring(
                    $rootDirectory.FullName.Length
                ).TrimStart('\', '/')
                $relativePath = $relativePath -replace '/', '\'

                $relativeDirectory = [System.IO.Path]::GetDirectoryName($relativePath)
                if ([string]::IsNullOrWhiteSpace($relativeDirectory)) {
                    $relativeDirectory = '.'
                }

                $files.Add([PSCustomObject]@{
                        Name              = $file.Name
                        FullName          = $file.FullName
                        RelativePath      = $relativePath
                        RelativeDirectory = $relativeDirectory
                        Extension         = $file.Extension
                        LastWriteTime     = $file.LastWriteTime
                        Length            = [int64]$file.Length
                    })
            }
        }
        catch {
            Write-RenderKitLog -Level Debug -Message "Skipping files in '$($currentDirectory.FullName)': $_"
        }
    }

    return $files.ToArray()
}
