function Get-BackupCleanupProfiles {
    [CmdletBinding()]
    param()

    if ($script:RenderKitBackupCleanupProfiles) {
        return $script:RenderKitBackupCleanupProfiles
    }

    $script:RenderKitBackupCleanupProfiles = @{
        General = @{
            Folders    = @(
                "_cache",
                "cache",
                "caches",
                "temp",
                "tmp",
                "__macosx"
            )
            Extensions = @(
                ".tmp",
                ".temp",
                ".bak",
                ".old",
                ".dmp"
            )
        }
        DaVinci = @{
            Folders    = @(
                "CacheClip",
                "ProxyMedia",
                "RenderCache",
                "OptimizedMedia"
            )
            Extensions = @(
                ".dvcc"
            )
        }
        Adobe = @{
            Folders    = @(
                "Media Cache",
                "Media Cache Files",
                "Peak Files",
                "Adobe Premiere Pro Video Previews",
                "Adobe Premiere Pro Audio Previews"
            )
            Extensions = @(
                ".pek",
                ".cfa",
                ".ims"
            )
        }
    }

    return $script:RenderKitBackupCleanupProfiles
}
