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

    It 'rejects traversal when resolving an existing project before metadata is read' {
        $parent = Join-Path $TestDrive 'existing-projects'
        New-Item -ItemType Directory -Path $parent -Force | Out-Null

        InModuleScope RenderKit -Parameters @{ Parent = $parent } {
            Mock Write-RenderKitLog {}
            Mock Read-RenderKitJsonFile {
                throw 'Metadata must not be read for an unsafe project name.'
            }

            {
                Get-RenderKitProject `
                    -ProjectName '../OutsideProject' `
                    -Path $Parent
            } | Should -Throw '*single path component*'

            Should -Invoke Read-RenderKitJsonFile -Times 0
        }
    }

    It 'rejects a symbolic-link project root before following project control data' {
        $parent = Join-Path $TestDrive 'linked-roots'
        $outside = Join-Path $TestDrive 'outside-root'
        $projectLink = Join-Path $parent 'LinkedProject'
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        New-Item -ItemType Directory -Path $outside -Force | Out-Null

        try {
            New-Item -ItemType SymbolicLink -Path $projectLink -Target $outside -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'Symbolic link creation is not available on this runner.'
            return
        }

        {
            InModuleScope RenderKit -Parameters @{
                Parent = $parent
            } {
                Get-RenderKitProject -ProjectName 'LinkedProject' -Path $Parent
            }
        } | Should -Throw '*Project root*symbolic link, junction, or reparse point*'
    }

    It 'rejects a linked .renderkit control directory' {
        $parent = Join-Path $TestDrive 'linked-control'
        $projectRoot = Join-Path $parent 'ProjectA'
        $outsideControl = Join-Path $TestDrive 'outside-control'
        $controlLink = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $outsideControl -Force | Out-Null

        try {
            New-Item -ItemType SymbolicLink -Path $controlLink -Target $outsideControl -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'Symbolic link creation is not available on this runner.'
            return
        }

        {
            InModuleScope RenderKit -Parameters @{
                Parent = $parent
            } {
                Get-RenderKitProject -ProjectName 'ProjectA' -Path $Parent
            }
        } | Should -Throw '*Project control path*symbolic link, junction, or reparse point*'
    }

    It 'rejects a linked project.json metadata file' {
        $parent = Join-Path $TestDrive 'linked-metadata'
        $projectRoot = Join-Path $parent 'ProjectA'
        $controlPath = Join-Path $projectRoot '.renderkit'
        $outsideMetadata = Join-Path $TestDrive 'outside-project.json'
        $metadataLink = Join-Path $controlPath 'project.json'
        New-Item -ItemType Directory -Path $controlPath -Force | Out-Null
        Set-Content -LiteralPath $outsideMetadata -Value '{"tool":"RenderKit"}' -Encoding UTF8

        try {
            New-Item -ItemType SymbolicLink -Path $metadataLink -Target $outsideMetadata -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'Symbolic link creation is not available on this runner.'
            return
        }

        {
            InModuleScope RenderKit -Parameters @{
                Parent = $parent
            } {
                Get-RenderKitProject -ProjectName 'ProjectA' -Path $Parent
            }
        } | Should -Throw '*Project metadata path*symbolic link, hard link, or reparse point*'
    }
}
