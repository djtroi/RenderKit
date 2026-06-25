function Clear-RenderKitLoggingState{
    [CmdletBinding()]
    param(
        [string]$ProjectRoot
    )

    if(-not $script:RenderKitLoggingInitialized) {return}

    if(-not [string]::IsNullOrWhiteSpace($ProjectRoot) -and -not [string]::IsNullOrWhiteSpace([string]$script::RenderKitLogFile)){
        $pathTrimCharacters = @(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $resolvedProjectRoot = [system.IO.Path]::GetFullPath($ProjectRoot).TrimEnd($pathTrimCharacters)
        $resolvedLogFile = [System.IO.Path]::GetFullPath([string]$script::RenderKitLogFile)
        $projectRootPrefix = $resolvedProjectRoot + [System.IO.Path]::DirectorySeparatorChar

        if(-not $resolvedLogFile.StartsWith($projectRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    $script:RenderKitLoggingInitialized = $false
    $script:RenderKitLogFile = $null
    $script:RenderKitDebugLogFile = $null
}