BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repositoryRoot 'RenderKit.psd1') -Force
}

AfterAll {
    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
}

Describe 'RenderKit template folder security' {
    It 'accepts a normal bounded folder tree' {
        $folders = @(
            [PSCustomObject]@{
                Name = '01_Raw'
                SubFolders = @(
                    [PSCustomObject]@{
                        Name = 'Video'
                        SubFolders = @()
                    },
                    [PSCustomObject]@{
                        Name = 'Audio'
                        SubFolders = @()
                    }
                )
            }
        )

        {
            InModuleScope RenderKit -Parameters @{ Folders = $folders } {
                Test-RenderKitTemplateFolderTree -Folder $Folders
            }
        } | Should -Not -Throw
    }

    It 'rejects path traversal and nested path fragments' -ForEach @(
        @{ Name = '..' },
        @{ Name = '../Outside' },
        @{ Name = '..\Outside' },
        @{ Name = 'Nested/Folder' },
        @{ Name = 'Nested\Folder' }
    ) {
        $folders = @(
            [PSCustomObject]@{
                Name = $Name
                SubFolders = @()
            }
        )

        {
            InModuleScope RenderKit -Parameters @{ Folders = $folders } {
                Test-RenderKitTemplateFolderTree -Folder $Folders
            }
        } | Should -Throw '*single path component*'
    }

    It 'rejects duplicate or case-colliding siblings' {
        $folders = @(
            [PSCustomObject]@{
                Name = 'Media'
                SubFolders = @(
                    [PSCustomObject]@{ Name = 'Video'; SubFolders = @() },
                    [PSCustomObject]@{ Name = 'VIDEO'; SubFolders = @() }
                )
            }
        )

        {
            InModuleScope RenderKit -Parameters @{ Folders = $folders } {
                Test-RenderKitTemplateFolderTree -Folder $Folders
            }
        } | Should -Throw '*duplicate or case-colliding child*'
    }

    It 'rejects a folder node without a name' {
        $folders = @(
            [PSCustomObject]@{ SubFolders = @() }
        )

        {
            InModuleScope RenderKit -Parameters @{ Folders = $folders } {
                Test-RenderKitTemplateFolderTree -Folder $Folders
            }
        } | Should -Throw "*missing the 'Name' property*"
    }

    It 'rejects a folder tree deeper than the configured bound' {
        $root = [PSCustomObject]@{ Name = 'Level1'; SubFolders = @() }
        $current = $root
        foreach ($level in 2..5) {
            $child = [PSCustomObject]@{
                Name = "Level$level"
                SubFolders = @()
            }
            $current.SubFolders = @($child)
            $current = $child
        }

        {
            InModuleScope RenderKit -Parameters @{ Root = $root } {
                Test-RenderKitTemplateFolderTree `
                    -Folder @($Root) `
                    -MaximumDepth 4
            }
        } | Should -Throw '*maximum depth of 4*'
    }

    It 'rejects a folder tree exceeding the configured node bound' {
        $folders = @(
            [PSCustomObject]@{ Name = 'One'; SubFolders = @() },
            [PSCustomObject]@{ Name = 'Two'; SubFolders = @() },
            [PSCustomObject]@{ Name = 'Three'; SubFolders = @() }
        )

        {
            InModuleScope RenderKit -Parameters @{ Folders = $folders } {
                Test-RenderKitTemplateFolderTree `
                    -Folder $Folders `
                    -MaximumNodes 2
            }
        } | Should -Throw '*maximum node count of 2*'
    }

    It 'keeps legacy Children collections within the same security validation' {
        $folders = @(
            [PSCustomObject]@{
                Name = 'LegacyRoot'
                Children = @(
                    [PSCustomObject]@{
                        Name = 'LegacyChild'
                        Children = @()
                    }
                )
            }
        )

        {
            InModuleScope RenderKit -Parameters @{ Folders = $folders } {
                Test-RenderKitTemplateFolderTree -Folder $Folders
            }
        } | Should -Not -Throw
    }
}
