BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    function Register-RenderKitFunction {
        param([string]$Name)
    }
    function ConvertTo-RenderKitImportUserPath {
        param([string]$Path)
        return $Path
    }
    function Test-RenderKitImportArchivePath {
        param([string]$Path)
        return $Path -match '\.rkit(pkg)?$'
    }
    function Read-RenderKitProjectArchiveManifest {
        param([string]$Path)
        return $script:ImportManifest
    }

    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectImportSecurityService.ps1')
    . (Join-Path $repositoryRoot 'src/Public/Import-Project.ps1')
}

Describe 'Import-Project target boundary security' {
    BeforeEach {
        $destinationRoot = Join-Path $TestDrive 'Imports'
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        $archivePath = Join-Path $TestDrive 'malicious.rkitpkg'
        Set-Content -LiteralPath $archivePath -Value 'placeholder'
        $script:ImportManifest = [pscustomobject]@{
            RenderKitProjectManifest = [pscustomobject]@{
                schemaVersion = '1.0'
                Project = [pscustomobject]@{
                    sourceRootName = 'SafeProject'
                    name = 'SafeProject'
                }
            }
        }
    }

    It 'resolves a normal project name strictly below the destination root' {
        $target = Resolve-RenderKitProjectImportTargetRoot `
            -DestinationRoot $destinationRoot `
            -ProjectName 'ProjectA'

        $target | Should -Be (
            [System.IO.Path]::GetFullPath((Join-Path $destinationRoot 'ProjectA'))
        )
    }

    It 'rejects dot segments, rooted names, and path separators' {
        $badNames = @('..', '.', '../outside', '..\outside', 'nested/project', 'nested\project')
        if ($env:OS -eq 'Windows_NT') {
            $badNames += 'C:\outside'
        }
        else {
            $badNames += '/tmp/outside'
        }

        foreach ($name in $badNames) {
            {
                Resolve-RenderKitProjectImportTargetRoot `
                    -DestinationRoot $destinationRoot `
                    -ProjectName $name
            } | Should -Throw
        }
    }

    It 'rejects a traversal name supplied by the archive before overwrite can delete outside data' {
        $outsideRoot = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path $outsideRoot -Force | Out-Null
        $sentinel = Join-Path $outsideRoot 'do-not-delete.txt'
        Set-Content -LiteralPath $sentinel -Value 'protected'
        $script:ImportManifest.RenderKitProjectManifest.Project.sourceRootName = '../outside'
        $script:ImportManifest.RenderKitProjectManifest.Project.name = '../outside'

        {
            Import-Project `
                -Path $archivePath `
                -DestinationRoot $destinationRoot `
                -ConflictAction Overwrite
        } | Should -Throw '*single path component*'

        Test-Path -LiteralPath $sentinel -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $sentinel -Raw).Trim() | Should -Be 'protected'
    }

    It 'rejects an explicit traversal ProjectName before filesystem mutation' {
        {
            Import-Project `
                -Path $archivePath `
                -DestinationRoot $destinationRoot `
                -ProjectName '../outside' `
                -ConflictAction Overwrite
        } | Should -Throw '*single path component*'
    }
}
