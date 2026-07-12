BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:RenderKitModuleRoot = $repositoryRoot
    $script:RenderKitModuleVersion = '1.2.0'
    function Register-RenderKitFunction { param([string]$Name) }
    function Write-RenderKitLog { param([string]$Level, [string]$Message) }

    . (Join-Path $repositoryRoot 'src/Classes/RenderKit.Classes.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Versioning/RenderKit.ArtifactVersionService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Template/RenderKit.TemplateService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Mapping/RenderKit.MappingService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Resource/RenderKit.ResourcePortabilityService.ps1')
    foreach ($name in @(
            'Import-RenderKitTemplate', 'Export-RenderKitTemplate',
            'Test-RenderKitTemplate', 'Import-RenderKitMapping',
            'Export-RenderKitMapping', 'Test-RenderKitMapping')) {
        . (Join-Path $repositoryRoot "src/Public/$name.ps1")
    }
}

Describe 'RenderKit template and mapping portability' {
    BeforeEach {
        $env:RENDERKIT_HOME = Join-Path $TestDrive 'renderkit-home'
        $script:RenderKitArtifactVersionCatalog = $null
        $script:RenderKitArtifactMigrations = @{}
    }

    AfterEach { Remove-Item Env:RENDERKIT_HOME -ErrorAction SilentlyContinue }

    It 'imports, validates, exports, and renames templates' {
        $source = Join-Path $TestDrive 'template.json'
        @{ Version = '1.1'; Name = 'portable'; Folders = @(); Mappings = @(); Deliverables = @() } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $source

        $imported = Import-RenderKitTemplate -Path $source -Confirm:$false
        $imported.Name | Should -Be 'portable'
        $imported.Source | Should -Be 'User'
        (Test-RenderKitTemplate -Name portable -Source User).IsValid | Should -BeTrue

        $renamed = Import-RenderKitTemplate -Path $source `
            -ConflictAction Rename -Confirm:$false
        $renamed.Name | Should -Be 'portable-2'

        $exportPath = Join-Path $TestDrive 'exports/portable.json'
        $exported = Export-RenderKitTemplate -Name portable -Source User `
            -Path $exportPath -Confirm:$false
        $exported.SizeBytes | Should -BeGreaterThan 0
        (Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json).Name |
            Should -Be 'portable'
    }

    It 'imports, validates, exports, and renames mappings' {
        $source = Join-Path $TestDrive 'mapping.json'
        @{ Version = '1.1'; Id = 'camera'; Types = @() } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $source

        $imported = Import-RenderKitMapping -Path $source -Confirm:$false
        $imported.Name | Should -Be 'camera'
        (Test-RenderKitMapping -Name camera -Source User).IsValid | Should -BeTrue

        $renamed = Import-RenderKitMapping -Path $source `
            -ConflictAction Rename -Confirm:$false
        $renamed.Name | Should -Be 'camera-2'

        $exportPath = Join-Path $TestDrive 'exports/camera.json'
        Export-RenderKitMapping -Name camera -Source User `
            -Path $exportPath -Confirm:$false | Out-Null
        (Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json).Id |
            Should -Be 'camera'
    }

    It 'returns a validation result for missing resources' {
        $result = Test-RenderKitTemplate -Name missing -Source User
        $result.IsValid | Should -BeFalse
        $result.Message | Should -Match 'not found'
    }

    It 'rejects resource names that could escape user storage' {
        $source = Join-Path $TestDrive 'unsafe.json'
        @{ Version = '1.1'; Id = '../outside'; Types = @() } |
            ConvertTo-Json | Set-Content -LiteralPath $source

        { Import-RenderKitMapping -Path $source -Confirm:$false } |
            Should -Throw '*safe file name*'
    }

    It 'supports export WhatIf without creating a file' {
        $source = Join-Path $TestDrive 'whatif.json'
        @{ Version = '1.1'; Name = 'whatif'; Folders = @() } |
            ConvertTo-Json | Set-Content -LiteralPath $source
        Import-RenderKitTemplate -Path $source -Confirm:$false | Out-Null
        $destination = Join-Path $TestDrive 'not-written.json'

        $result = Export-RenderKitTemplate -Name whatif -Source User `
            -Path $destination -WhatIf
        $result.Written | Should -BeFalse
        Test-Path -LiteralPath $destination | Should -BeFalse
    }
}
