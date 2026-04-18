function Get-CleanupRule{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Alias("Software")]
        [string[]]$Preset
    )

    Write-RenderKitLog -Level Debug -Message "Get-CleanupRules started: ProfileCount=$(@($Preset).Count)."

    $profiles = Get-BackupCleanupProfile
    $requestedProfiles = @(
        $Preset |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() } |
            Sort-Object -Unique
    )

    if ($requestedProfiles.Count -eq 0) {
        Write-RenderKitLog -Level Warning -Message "No cleanup profiles specified. Using default profile 'General'."
        $requestedProfiles = @("General")
    }

    $unknownProfiles = @(
        $requestedProfiles |
            Where-Object { -not $profiles.ContainsKey($_) }
    )
    if ($unknownProfiles.Count -gt 0) {
        $available = @($profiles.Keys | Sort-Object) -join ", "
        Write-RenderKitLog -Level Error -Message "Unknown backup profile(s): $($unknownProfiles -join ', '). Available profiles: $available."
        throw "Unknown backup profile(s): $($unknownProfiles -join ', '). Available profiles: $available."
    }

    $folders = New-Object System.Collections.Generic.List[string]
    $extensions = New-Object System.Collections.Generic.List[string]

    foreach ($profileName in $requestedProfiles){
        $preset = $profiles[$profileName]
        if (-not $preset) {
            continue
        }

        foreach ($folder in @($preset.Folders)) {
            if ([string]::IsNullOrWhiteSpace($folder)) {
                continue
            }

            $folders.Add($folder.Trim())
        }

        foreach ($extension in @($preset.Extensions)) {
            if ([string]::IsNullOrWhiteSpace($extension)) {
                continue
            }

            $normalizedExtension = $extension.Trim().ToLowerInvariant()
            if (-not $normalizedExtension.StartsWith(".")) {
                $normalizedExtension = ".$normalizedExtension"
            }

            $extensions.Add($normalizedExtension)
        }
    }

    return @{
        Profiles   = @($requestedProfiles)
        Folders    = @($folders | Sort-Object -Unique)
        Extensions = @($extensions | Sort-Object -Unique)
    }
}
