function Get-RenderKitPlatform {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [ValidateSet('Auto', 'Windows', 'Linux', 'macOS')]
        [string]$Platform = 'Auto'
    )

    if ($Platform -ne 'Auto') {
        return $Platform
    }

    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        return 'Windows'
    }

    $isWindowsVariable = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
    $isLinuxVariable = Get-Variable -Name IsLinux -ErrorAction SilentlyContinue
    $isMacOSVariable = Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue

    if ($isWindowsVariable -and [bool]$isWindowsVariable.Value) { return 'Windows' }
    if ($isLinuxVariable -and [bool]$isLinuxVariable.Value) { return 'Linux' }
    if ($isMacOSVariable -and [bool]$isMacOSVariable.Value) { return 'macOS' }

    throw 'RenderKit could not determine the current operating system.'
}

function Get-RenderKitUserHome {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    if (-not [string]::IsNullOrWhiteSpace([string]$homes)) {
        return [System.IO.Path]::GetFullPath([string]$homes)
    }

    $profilePath = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::UserProfile
    )
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
        return [System.IO.Path]::GetFullPath($profilePath)
    }

    throw 'RenderKit could not resolve the current user home directory.'
}

function Get-RenderKitKnownFolderPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ApplicationData', 'LocalApplicationData')]
        [string]$Name
    )

    $specialFolder = [Environment+SpecialFolder](
        [Enum]::Parse([Environment+SpecialFolder], $Name)
    )
    $path = [Environment]::GetFolderPath($specialFolder)
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $null
    }

    return [System.IO.Path]::GetFullPath($path)
}

function New-RenderKitStorageDirectory {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop |
            Out-Null
    }

    return [System.IO.Path]::GetFullPath($Path)
}

function Get-RenderKitStorageRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Configuration', 'State', 'Cache', 'UserData')]
        [string]$Kind,

        [ValidateSet('Auto', 'Windows', 'Linux', 'macOS')]
        [string]$Platform = 'Auto',

        [switch]$Ensure
    )

    $resolvedPlatform = Get-RenderKitPlatform -Platform $Platform
    $overrideRoot = [string]$env:RENDERKIT_HOME

    if (-not [string]::IsNullOrWhiteSpace($overrideRoot)) {
        $rootName = switch ($Kind) {
            'Configuration' { 'config' }
            'State' { 'state' }
            'Cache' { 'cache' }
            'UserData' { 'data' }
        }
        $root = Join-Path -Path (
            [System.IO.Path]::GetFullPath($overrideRoot)
        ) -ChildPath $rootName
    }
    else {
        $homes = Get-RenderKitUserHome
        switch ($resolvedPlatform) {
            'Windows' {
                $roaming = [string]$env:APPDATA
                if ([string]::IsNullOrWhiteSpace($roaming)) {
                    $roaming = Get-RenderKitKnownFolderPath `
                        -Name ApplicationData
                }

                $local = [string]$env:LOCALAPPDATA
                if ([string]::IsNullOrWhiteSpace($local)) {
                    $local = Get-RenderKitKnownFolderPath `
                        -Name LocalApplicationData
                }

                if ([string]::IsNullOrWhiteSpace($roaming)) {
                    $roaming = Join-Path -Path $homes -ChildPath 'AppData/Roaming'
                }
                if ([string]::IsNullOrWhiteSpace($local)) {
                    $local = Join-Path -Path $homes -ChildPath 'AppData/Local'
                }

                $root = switch ($Kind) {
                    'Configuration' {
                        Join-Path -Path $roaming -ChildPath 'RenderKit'
                    }
                    'State' {
                        Join-Path -Path $local -ChildPath 'RenderKit'
                    }
                    'Cache' {
                        Join-Path -Path (
                            Join-Path -Path $local -ChildPath 'RenderKit'
                        ) -ChildPath 'cache'
                    }
                    'UserData' {
                        Join-Path -Path $roaming -ChildPath 'RenderKit'
                    }
                }
            }
            'Linux' {
                $configBase = [string]$env:XDG_CONFIG_HOME
                if ([string]::IsNullOrWhiteSpace($configBase)) {
                    $configBase = Join-Path -Path $homes -ChildPath '.config'
                }

                $stateBase = [string]$env:XDG_STATE_HOME
                if ([string]::IsNullOrWhiteSpace($stateBase)) {
                    $stateBase = Join-Path -Path $homes `
                        -ChildPath '.local/state'
                }

                $cacheBase = [string]$env:XDG_CACHE_HOME
                if ([string]::IsNullOrWhiteSpace($cacheBase)) {
                    $cacheBase = Join-Path -Path $homes -ChildPath '.cache'
                }

                $dataBase = [string]$env:XDG_DATA_HOME
                if ([string]::IsNullOrWhiteSpace($dataBase)) {
                    $dataBase = Join-Path -Path $homes `
                        -ChildPath '.local/share'
                }

                $base = switch ($Kind) {
                    'Configuration' { $configBase }
                    'State' { $stateBase }
                    'Cache' { $cacheBase }
                    'UserData' { $dataBase }
                }
                $root = Join-Path -Path $base -ChildPath 'renderkit'
            }
            'macOS' {
                $applicationSupport = Join-Path -Path $homes `
                    -ChildPath 'Library/Application Support'
                $cacheBase = Join-Path -Path $homes `
                    -ChildPath 'Library/Caches'

                $base = switch ($Kind) {
                    'Configuration' {
                        if ($env:XDG_CONFIG_HOME) {
                            $env:XDG_CONFIG_HOME
                        }
                        else {
                            $applicationSupport
                        }
                    }
                    'State' {
                        if ($env:XDG_STATE_HOME) {
                            $env:XDG_STATE_HOME
                        }
                        else {
                            $applicationSupport
                        }
                    }
                    'Cache' {
                        if ($env:XDG_CACHE_HOME) {
                            $env:XDG_CACHE_HOME
                        }
                        else {
                            $cacheBase
                        }
                    }
                    'UserData' {
                        if ($env:XDG_DATA_HOME) {
                            $env:XDG_DATA_HOME
                        }
                        else {
                            $applicationSupport
                        }
                    }
                }
                $root = Join-Path -Path $base -ChildPath 'RenderKit'
            }
        }
    }

    $resolvedRoot = [System.IO.Path]::GetFullPath($root)
    if ($Ensure) {
        return New-RenderKitStorageDirectory -Path $resolvedRoot
    }

    return $resolvedRoot
}

function Get-RenderKitLegacyRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [ValidateSet('Auto', 'Windows', 'Linux', 'macOS')]
        [string]$Platform = 'Auto'
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$env:RENDERKIT_HOME)) {
        return $null
    }

    $resolvedPlatform = Get-RenderKitPlatform -Platform $Platform
    $homes = Get-RenderKitUserHome

    switch ($resolvedPlatform) {
        'Windows' {
            $base = [string]$env:APPDATA
            if ([string]::IsNullOrWhiteSpace($base)) {
                $base = Get-RenderKitKnownFolderPath -Name ApplicationData
            }
        }
        'Linux' {
            $base = [string]$env:XDG_CONFIG_HOME
            if ([string]::IsNullOrWhiteSpace($base)) {
                $base = Join-Path -Path $homes -ChildPath '.config'
            }
        }
        'macOS' {
            $base = Join-Path -Path $homes -ChildPath '.config'
        }
    }

    if ([string]::IsNullOrWhiteSpace($base)) {
        return $null
    }

    return [System.IO.Path]::GetFullPath(
        (Join-Path -Path $base -ChildPath 'RenderKit')
    )
}

function Copy-RenderKitLegacyStorageItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LegacyPath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $legacyFullPath = [System.IO.Path]::GetFullPath($LegacyPath)
    $destinationFullPath = [System.IO.Path]::GetFullPath($DestinationPath)
    if (
        $legacyFullPath.Equals(
            $destinationFullPath,
            [System.StringComparison]::Ordinal
        )
    ) {
        return
    }

    if (
        (Test-Path -LiteralPath $legacyFullPath) -and
        -not (Test-Path -LiteralPath $destinationFullPath)
    ) {
        $destinationParent = Split-Path -Path $destinationFullPath -Parent
        New-RenderKitStorageDirectory -Path $destinationParent | Out-Null
        Copy-Item -LiteralPath $legacyFullPath `
            -Destination $destinationFullPath `
            -Recurse `
            -ErrorAction Stop
    }
}

function Get-RenderKitConfigPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [switch]$EnsureParent,
        [switch]$SkipLegacyMigration
    )

    $root = Get-RenderKitStorageRoot `
        -Kind Configuration `
        -Ensure:$EnsureParent
    $path = Join-Path -Path $root -ChildPath 'config.json'
    if (-not $SkipLegacyMigration) {
        $legacyRoot = Get-RenderKitLegacyRoot
        if ($legacyRoot) {
            Copy-RenderKitLegacyStorageItem `
                -LegacyPath (Join-Path $legacyRoot 'config.json') `
                -DestinationPath $path
        }
    }

    return $path
}
function Get-RenderKitSystemTemplatesRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return Get-RenderKitModuleResourceRoot -RelativePath 'Resources/Templates'
}

function Get-RenderKitUserTemplatePath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName
    )

    $normalizedName = [IO.Path]::GetFileNameWithoutExtension($TemplateName)
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        throw 'Template name must not be empty.'
    }

    return Join-Path `
        -Path (Get-RenderKitUserTemplatesRoot) `
        -ChildPath "$normalizedName.json"
}


function Get-RenderKitDevicesPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $root = Get-RenderKitStorageRoot -Kind State -Ensure
    $path = Join-Path -Path $root -ChildPath 'Devices.json'
    $legacyRoot = Get-RenderKitLegacyRoot
    if ($legacyRoot) {
        Copy-RenderKitLegacyStorageItem `
            -LegacyPath (Join-Path $legacyRoot 'Devices.json') `
            -DestinationPath $path
    }

    return $path
}

function Get-RenderKitProjectRegistryPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $root = Get-RenderKitStorageRoot -Kind State -Ensure
    return Join-Path -Path $root -ChildPath 'Projects.json'
}
function Get-RenderKitDiscoveredProjectsPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $root = Get-RenderKitStorageRoot -Kind State -Ensure
    return Join-Path -Path $root -ChildPath 'DiscoveredProjects.json'
}

function Get-RenderKitProjectSearchIndexPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $root = Get-RenderKitStorageRoot -Kind State -Ensure
    return Join-Path -Path $root -ChildPath 'ProjectSearchIndex.json'
}

function Get-RenderKitEventStorePath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $root = Get-RenderKitStorageRoot -Kind State -Ensure
    return Join-Path -Path $root -ChildPath 'Events.json'
}

function Get-RenderKitJobStorePath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $root = Get-RenderKitStorageRoot -Kind State -Ensure
    return Join-Path -Path $root -ChildPath 'Jobs.json'
}

function Get-RenderKitRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    # Compatibility wrapper for existing internal callers. New code should
    # request a semantic storage root or a specific storage path.
    return Get-RenderKitStorageRoot -Kind Configuration -Ensure
}

function Get-RenderKitUserTemplatesRoot {
    $root = Get-RenderKitStorageRoot -Kind UserData -Ensure
    $path = Join-Path $root 'templates'
    $legacyRoot = Get-RenderKitLegacyRoot
    if ($legacyRoot) {
        Copy-RenderKitLegacyStorageItem `
            -LegacyPath (Join-Path $legacyRoot 'templates') `
            -DestinationPath $path
    }

    return New-RenderKitStorageDirectory -Path $path
}

function Get-RenderKitUserMappingsRoot {
    $root = Get-RenderKitStorageRoot -Kind UserData -Ensure
    $path = Join-Path $root 'mappings'
    $legacyRoot = Get-RenderKitLegacyRoot
    if ($legacyRoot) {
        Copy-RenderKitLegacyStorageItem `
            -LegacyPath (Join-Path $legacyRoot 'mappings') `
            -DestinationPath $path
    }

    return New-RenderKitStorageDirectory -Path $path
}

function Get-RenderKitBackupConfigProfilesRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    $root = Get-RenderKitStorageRoot -Kind UserData -Ensure
    return New-RenderKitStorageDirectory `
        -Path (Join-Path -Path $root -ChildPath 'backup-config-profiles')
}

function Get-RenderKitBackupConfigProfilePath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $fileName = [IO.Path]::GetFileNameWithoutExtension($Name)
    if ([string]::IsNullOrWhiteSpace($fileName) -or
        $fileName -notmatch '^[a-z0-9][a-z0-9-]*$') {
        throw "Backup config profile name '$Name' is not a safe file name."
    }
    return Join-Path `
        -Path (Get-RenderKitBackupConfigProfilesRoot) `
        -ChildPath "$fileName.rkprofile.json"
}

function Get-RenderKitUserMappingPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    $normalizedName = [IO.Path]::GetFileNameWithoutExtension($MappingId)
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        throw 'Mapping id must not be empty.'
    }

    return Join-Path `
        -Path (Get-RenderKitUserMappingsRoot) `
        -ChildPath "$normalizedName.json"
}

function Get-RenderKitSystemMappingsRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return Get-RenderKitModuleResourceRoot -RelativePath 'Resources/Mappings'
}

function Get-RenderKitSystemMappingPath {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$MappingId
    )

    $normalizedName = [IO.Path]::GetFileNameWithoutExtension($MappingId)
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        throw 'Mapping id must not be empty.'
    }

    return Join-Path `
        -Path (Get-RenderKitSystemMappingsRoot) `
        -ChildPath "$normalizedName.json"
}

function Get-RenderKitModuleResourceRoot {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $candidateBasePaths = New-Object System.Collections.Generic.List[string]
    $moduleRootVariable = Get-Variable `
        -Name RenderKitModuleRoot `
        -Scope Script `
        -ErrorAction SilentlyContinue
    if ($moduleRootVariable -and
        -not [string]::IsNullOrWhiteSpace([string]$moduleRootVariable.Value)) {
        $candidateBasePaths.Add([string]$moduleRootVariable.Value)
        }
    $fallbackBasePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if (-not $candidateBasePaths.Contains($fallbackBasePath)) {
        $candidateBasePaths.Add($fallbackBasePath)
    }

    foreach ($basePath in $candidateBasePaths) {
        $resourceCandidates = @(
            (Join-Path -Path $basePath -ChildPath $RelativePath),
            (Join-Path -Path (Join-Path -Path $basePath -ChildPath 'src') -ChildPath $RelativePath)
        )

        foreach ($candidatePath in $resourceCandidates) {
            if (Test-Path -LiteralPath $candidatePath -PathType Container) {
                return (Resolve-Path -LiteralPath $candidatePath).ProviderPath
            }
        }
    }

    throw "RenderKit resource root '$RelativePath' was not found below: $($candidateBasePaths -join ', ')."
}

        
