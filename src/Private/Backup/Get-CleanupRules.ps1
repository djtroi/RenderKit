function Get-CleanupRules{
    [CmdletBinding()]
    param(
        [Alias("Software")]
        [string[]]$Profile
    )

    $profiles = Get-BackupCleanupProfiles
    $requestedProfiles = @(
        $Profile |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() } |
            Sort-Object -Unique
    )

    if ($requestedProfiles.Count -eq 0) {
        $requestedProfiles = @("General")
    }

    $unknownProfiles = @(
        $requestedProfiles |
            Where-Object { -not $profiles.ContainsKey($_) }
    )
    if ($unknownProfiles.Count -gt 0) {
        $available = @($profiles.Keys | Sort-Object) -join ", "
        throw "Unknown backup profile(s): $($unknownProfiles -join ', '). Available profiles: $available."
    }

    $folders = New-Object System.Collections.Generic.List[string]
    $extensions = New-Object System.Collections.Generic.List[string]

    foreach ($profileName in $requestedProfiles){
        $profile = $profiles[$profileName]
        if (-not $profile) {
            continue
        }

        foreach ($folder in @($profile.Folders)) {
            if ([string]::IsNullOrWhiteSpace($folder)) {
                continue
            }

            $folders.Add($folder.Trim())
        }

        foreach ($extension in @($profile.Extensions)) {
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
