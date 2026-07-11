BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $storageServicePath = Join-Path $repositoryRoot `
        'src/Private/Storage/RenderKit.StorageService.ps1'
    . $storageServicePath
    $script:getUserHomeImplementation = ${function:Get-RenderKitUserHome}
}

Describe 'RenderKit cross-platform storage service' {
    BeforeEach {
        $script:originalEnvironment = @{
            RENDERKIT_HOME = $env:RENDERKIT_HOME
            HOME = $env:HOME
            APPDATA = $env:APPDATA
            LOCALAPPDATA = $env:LOCALAPPDATA
            XDG_CONFIG_HOME = $env:XDG_CONFIG_HOME
            XDG_STATE_HOME = $env:XDG_STATE_HOME
            XDG_CACHE_HOME = $env:XDG_CACHE_HOME
            XDG_DATA_HOME = $env:XDG_DATA_HOME
        }

        $script:testRoot = Join-Path $TestDrive 'renderkit-storage'
        $env:RENDERKIT_HOME = $null
        $env:APPDATA = $null
        $env:LOCALAPPDATA = $null
        $env:XDG_CONFIG_HOME = $null
        $env:XDG_STATE_HOME = $null
        $env:XDG_CACHE_HOME = $null
        $env:XDG_DATA_HOME = $null

        Mock Get-RenderKitUserHome {
            return Join-Path $script:testRoot 'home'
        }
    }

    AfterEach {
        foreach ($name in $script:originalEnvironment.Keys) {
            $value = $script:originalEnvironment[$name]
            if ($null -eq $value) {
                Remove-Item -Path "env:$name" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -Path "env:$name" -Value $value
            }
        }
    }

    It 'isolates all semantic roots below RENDERKIT_HOME' {
        $env:RENDERKIT_HOME = Join-Path $script:testRoot 'override'

        $configuration = Get-RenderKitStorageRoot `
            -Kind Configuration `
            -Platform Linux
        $state = Get-RenderKitStorageRoot -Kind State -Platform Windows
        $cache = Get-RenderKitStorageRoot -Kind Cache -Platform macOS
        $userData = Get-RenderKitStorageRoot -Kind UserData -Platform Linux

        $configuration | Should -Be (
            Join-Path $env:RENDERKIT_HOME 'config'
        )
        $state | Should -Be (Join-Path $env:RENDERKIT_HOME 'state')
        $cache | Should -Be (Join-Path $env:RENDERKIT_HOME 'cache')
        $userData | Should -Be (Join-Path $env:RENDERKIT_HOME 'data')
    }

    It 'prefers the HOME environment variable for the user home' {
        $expectedHome = Join-Path $script:testRoot 'environment-home'
        $env:HOME = $expectedHome

        & $script:getUserHomeImplementation |
            Should -Be ([System.IO.Path]::GetFullPath($expectedHome))
    }

    It 'creates a requested semantic root only when Ensure is used' {
        $env:RENDERKIT_HOME = Join-Path $script:testRoot 'ensure'

        $path = Get-RenderKitStorageRoot -Kind State -Platform Linux
        Test-Path -LiteralPath $path | Should -BeFalse

        $ensuredPath = Get-RenderKitStorageRoot `
            -Kind State `
            -Platform Linux `
            -Ensure

        $ensuredPath | Should -Be $path
        Test-Path -LiteralPath $path -PathType Container |
            Should -BeTrue
    }

    It 'does not create the configuration directory when only resolving its path' {
        $env:RENDERKIT_HOME = Join-Path $script:testRoot 'config-path'

        $path = Get-RenderKitConfigPath -SkipLegacyMigration

        $path | Should -Be (
            Join-Path $env:RENDERKIT_HOME 'config/config.json'
        )
        Test-Path -LiteralPath (Split-Path $path -Parent) |
            Should -BeFalse
    }

    It 'uses XDG roots on Linux' {
        $env:XDG_CONFIG_HOME = Join-Path $script:testRoot 'xdg-config'
        $env:XDG_STATE_HOME = Join-Path $script:testRoot 'xdg-state'
        $env:XDG_CACHE_HOME = Join-Path $script:testRoot 'xdg-cache'
        $env:XDG_DATA_HOME = Join-Path $script:testRoot 'xdg-data'

        Get-RenderKitStorageRoot -Kind Configuration -Platform Linux |
            Should -Be (Join-Path $env:XDG_CONFIG_HOME 'renderkit')
        Get-RenderKitStorageRoot -Kind State -Platform Linux |
            Should -Be (Join-Path $env:XDG_STATE_HOME 'renderkit')
        Get-RenderKitStorageRoot -Kind Cache -Platform Linux |
            Should -Be (Join-Path $env:XDG_CACHE_HOME 'renderkit')
        Get-RenderKitStorageRoot -Kind UserData -Platform Linux |
            Should -Be (Join-Path $env:XDG_DATA_HOME 'renderkit')
    }

    It 'uses native macOS locations when XDG variables are absent' {
        $userHome = Get-RenderKitUserHome
        $applicationSupport = Join-Path $userHome `
            'Library/Application Support/RenderKit'
        $cache = Join-Path $userHome 'Library/Caches/RenderKit'

        Get-RenderKitStorageRoot -Kind Configuration -Platform macOS |
            Should -Be $applicationSupport
        Get-RenderKitStorageRoot -Kind State -Platform macOS |
            Should -Be $applicationSupport
        Get-RenderKitStorageRoot -Kind UserData -Platform macOS |
            Should -Be $applicationSupport
        Get-RenderKitStorageRoot -Kind Cache -Platform macOS |
            Should -Be $cache
    }

    It 'uses roaming and local application data on Windows' {
        $env:APPDATA = Join-Path $script:testRoot 'roaming'
        $env:LOCALAPPDATA = Join-Path $script:testRoot 'local'

        Get-RenderKitStorageRoot -Kind Configuration -Platform Windows |
            Should -Be (Join-Path $env:APPDATA 'RenderKit')
        Get-RenderKitStorageRoot -Kind UserData -Platform Windows |
            Should -Be (Join-Path $env:APPDATA 'RenderKit')
        Get-RenderKitStorageRoot -Kind State -Platform Windows |
            Should -Be (Join-Path $env:LOCALAPPDATA 'RenderKit')
        Get-RenderKitStorageRoot -Kind Cache -Platform Windows |
            Should -Be (
                Join-Path $env:LOCALAPPDATA 'RenderKit/cache'
            )
    }

    It 'copies a legacy file only when the destination does not exist' {
        $legacyDirectory = Join-Path $script:testRoot 'legacy'
        $destinationDirectory = Join-Path $script:testRoot 'destination'
        New-Item -ItemType Directory -Path $legacyDirectory -Force |
            Out-Null
        New-Item -ItemType Directory -Path $destinationDirectory -Force |
            Out-Null

        $legacyPath = Join-Path $legacyDirectory 'config.json'
        $destinationPath = Join-Path $destinationDirectory 'config.json'
        Set-Content -LiteralPath $legacyPath -Value '{"source":"legacy"}'

        Copy-RenderKitLegacyStorageItem `
            -LegacyPath $legacyPath `
            -DestinationPath $destinationPath
        Get-Content -LiteralPath $destinationPath -Raw |
            Should -Match 'legacy'

        Set-Content -LiteralPath $destinationPath `
            -Value '{"source":"current"}'
        Copy-RenderKitLegacyStorageItem `
            -LegacyPath $legacyPath `
            -DestinationPath $destinationPath

        Get-Content -LiteralPath $destinationPath -Raw |
            Should -Match 'current'
    }

    It 'migrates the legacy device whitelist into state storage' {
        $env:RENDERKIT_HOME = Join-Path $script:testRoot 'device-migration'
        $script:legacyRoot = Join-Path $script:testRoot 'legacy-device'
        New-Item -ItemType Directory -Path $script:legacyRoot -Force |
            Out-Null
        Set-Content `
            -LiteralPath (Join-Path $script:legacyRoot 'Devices.json') `
            -Value '{"Version":"1.0"}'
        Mock Get-RenderKitLegacyRoot { return $script:legacyRoot }

        $path = Get-RenderKitDevicesPath

        $path | Should -Be (
            Join-Path $env:RENDERKIT_HOME 'state/Devices.json'
        )
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
    }

    It 'stores config, devices, templates, and mappings by semantic kind' {
        $env:RENDERKIT_HOME = Join-Path $script:testRoot 'specific-paths'

        Get-RenderKitConfigPath |
            Should -Be (
                Join-Path $env:RENDERKIT_HOME 'config/config.json'
            )
        Get-RenderKitDevicesPath |
            Should -Be (
                Join-Path $env:RENDERKIT_HOME 'state/Devices.json'
            )
        Get-RenderKitUserTemplatesRoot |
            Should -Be (
                Join-Path $env:RENDERKIT_HOME 'data/templates'
            )
        Get-RenderKitUserMappingsRoot |
            Should -Be (
                Join-Path $env:RENDERKIT_HOME 'data/mappings'
            )
    }
    It 'resolves user template and mapping file paths with json extensions' {
        $env:RENDERKIT_HOME = Join-Path $script:testRoot 'user-artifacts'

        Get-RenderKitUserTemplatePath -TemplateName 'client-delivery' |
            Should -Be (
                Join-Path $env:RENDERKIT_HOME `
                    'data/templates/client-delivery.json'
            )
        Get-RenderKitUserTemplatePath -TemplateName 'client-delivery.json' |
            Should -Be (
                Join-Path $env:RENDERKIT_HOME `
                    'data/templates/client-delivery.json'
            )
        Get-RenderKitUserMappingPath -MappingId 'camera' |
            Should -Be (
                Join-Path $env:RENDERKIT_HOME 'data/mappings/camera.json'
            )
        Get-RenderKitUserMappingPath -MappingId 'camera.json' |
            Should -Be (
                Join-Path $env:RENDERKIT_HOME 'data/mappings/camera.json'
            )
    }

    It 'resolves bundled template and mapping roots from module resources' {
        Get-RenderKitSystemTemplatesRoot |
            Should -Be (
                Join-Path $repositoryRoot 'src/Resources/Templates'
            )
        Get-RenderKitSystemMappingsRoot |
            Should -Be (
                Join-Path $repositoryRoot 'src/Resources/Mappings'
            )
        Get-RenderKitSystemMappingPath -MappingId 'video.json' |
            Should -Be (
                Join-Path $repositoryRoot 'src/Resources/Mappings/video.json'
            )
    }
}
