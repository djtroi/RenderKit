# Native libraries are loaded in-process via DllImport. Do not treat executable
# PATH directories as native-library trust roots: user-writable PATH entries are
# common and would turn ordinary executable discovery into an in-process code
# loading boundary. Explicit configuration and bundled assets remain supported.
function Find-RenderKitMediaInfoSystemNativeLibrary {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $names = @(Get-RenderKitMediaInfoSystemNativeName)
    $directories = New-Object System.Collections.Generic.List[string]

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if ([string]::IsNullOrWhiteSpace([string]$base)) { continue }
            $candidateDir = Join-Path -Path $base -ChildPath 'MediaInfo'
            if (Test-Path -LiteralPath $candidateDir -PathType Container) {
                $directories.Add((Resolve-Path -LiteralPath $candidateDir).ProviderPath)
            }
        }
    }
    else {
        foreach ($candidateDir in @(
            '/usr/local/lib',
            '/usr/lib',
            '/usr/lib/x86_64-linux-gnu',
            '/usr/lib/aarch64-linux-gnu',
            '/opt/homebrew/lib',
            '/opt/local/lib'
        )) {
            if (Test-Path -LiteralPath $candidateDir -PathType Container) {
                $directories.Add((Resolve-Path -LiteralPath $candidateDir).ProviderPath)
            }
        }
    }

    foreach ($directory in @($directories.ToArray() | Select-Object -Unique)) {
        foreach ($name in $names) {
            $candidatePath = Join-Path -Path $directory -ChildPath $name
            if (Test-RenderKitMediaInfoUsableFile -Path $candidatePath) {
                return [System.IO.Path]::GetFullPath($candidatePath)
            }
        }
    }

    return $null
}
