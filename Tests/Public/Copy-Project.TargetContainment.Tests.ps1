BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repositoryRoot 'RenderKit.psd1') -Force
}

AfterAll {
    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
}

Describe 'Project target containment' {
    It 'resolves a normal project name directly below its parent' {
        $parent = Join-Path $TestDrive 'projects'
        New-Item -ItemType Directory -Path $parent -Force | Out-Null

        $result = InModuleScope RenderKit -Parameters @{ Parent = $parent } {
            Resolve-RenderKitProjectSiblingTarget `
                -ParentPath $Parent `
                -ProjectName 'ClientA-Copy'
        }

        $result.Name | Should -Be 'ClientA-Copy'
        $result.ParentPath | Should -Be ([System.IO.Path]::GetFullPath($parent))
        $result.Path | Should -Be (
            [System.IO.Path]::GetFullPath((Join-Path $parent 'ClientA-Copy'))
        )
    }

    It 'rejects parent traversal and path separators' -ForEach @(
        @{ Name = '..' },
        @{ Name = '.' },
        @{ Name = '../Outside' },
        @{ Name = '..\Outside' },
        @{ Name = 'Nested/Project' },
        @{ Name = 'Nested\Project' }
    ) {
        $parent = Join-Path $TestDrive 'projects'
        New-Item -ItemType Directory -Path $parent -Force | Out-Null

        {
            InModuleScope RenderKit -Parameters @{
                Parent = $parent
                CandidateName = $Name
            } {
                Resolve-RenderKitProjectSiblingTarget `
                    -ParentPath $Parent `
                    -ProjectName $CandidateName
            }
        } | Should -Throw '*single path component*'
    }

    It 'rejects Windows reserved device names' {
        $parent = Join-Path $TestDrive 'projects'
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $previousOs = $env:OS
        try {
            $env:OS = 'Windows_NT'
            {
                InModuleScope RenderKit -Parameters @{ Parent = $parent } {
                    Resolve-RenderKitProjectSiblingTarget `
                        -ParentPath $Parent `
                        -ProjectName 'NUL.txt'
                }
            } | Should -Throw '*reserved Windows device name*'
        }
        finally {
            $env:OS = $previousOs
        }
    }

    It 'rejects traversal through the public Copy-Project command before filesystem copy' {
        $parent = Join-Path $TestDrive 'projects'
        $sourceRoot = Join-Path $parent 'SourceProject'
        New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
        $outside = [System.IO.Path]::GetFullPath((Join-Path $parent '../OutsideProject'))

        InModuleScope RenderKit -Parameters @{
            Parent = $parent
            SourceRoot = $sourceRoot
        } {
            Mock Write-RenderKitLog {}
            Mock Get-RenderKitProject {
                [PSCustomObject]@{
                    Name = 'SourceProject'
                    Id = '11111111-1111-1111-1111-111111111111'
                    RootPath = $SourceRoot
                    MetadataPath = Join-Path $SourceRoot '.renderkit/project.json'
                }
            }
            Mock Copy-RenderKitProjectDirectory {}

            {
                Copy-Project `
                    -ProjectName 'SourceProject' `
                    -NewName '../OutsideProject' `
                    -Path $Parent `
                    -Confirm:$false
            } | Should -Throw '*single path component*'

            Should -Invoke Copy-RenderKitProjectDirectory -Times 0
        }

        Test-Path -LiteralPath $outside | Should -BeFalse
    }

    It 'rejects traversal through New-Project before template resolution or directory creation' {
        $parent = Join-Path $TestDrive 'new-projects'
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $outside = [System.IO.Path]::GetFullPath((Join-Path $parent '../OutsideProject'))

        InModuleScope RenderKit -Parameters @{ Parent = $parent } {
            Mock Write-RenderKitLog {}
            Mock Get-ProjectTemplate {
                throw 'Template resolution must not run for an unsafe target.'
            }
            Mock New-RenderKitProjectFromTemplate {}

            {
                New-Project `
                    -Name '../OutsideProject' `
                    -Path $Parent `
                    -Confirm:$false
            } | Should -Throw '*single path component*'

            Should -Invoke Get-ProjectTemplate -Times 0
            Should -Invoke New-RenderKitProjectFromTemplate -Times 0
        }

        Test-Path -LiteralPath $outside | Should -BeFalse
    }
}
