BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    function Register-RenderKitFunction {
        param([string]$Name)
    }

    . (Join-Path $repositoryRoot 'src/Public/Import-Project.ps1')
}

Describe 'Import-Project target containment' {
    It 'resolves a simple project name below the destination root' {
        $destination = Join-Path $TestDrive 'imports'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null

        $result = Resolve-RenderKitProjectImportTargetRoot `
            -DestinationRoot $destination `
            -ProjectName 'ProjectA'

        $result | Should -Be ([System.IO.Path]::GetFullPath(
            (Join-Path $destination 'ProjectA')
        ))
    }

    It 'rejects parent traversal from an archive-controlled project name' {
        $destination = Join-Path $TestDrive 'imports'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null

        {
            Resolve-RenderKitProjectImportTargetRoot `
                -DestinationRoot $destination `
                -ProjectName '../outside'
        } | Should -Throw '*Unsafe project name*'
    }

    It 'rejects Windows-style traversal on every platform' {
        $destination = Join-Path $TestDrive 'imports'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null

        {
            Resolve-RenderKitProjectImportTargetRoot `
                -DestinationRoot $destination `
                -ProjectName '..\outside'
        } | Should -Throw '*Unsafe project name*'
    }

    It 'rejects absolute and nested project names' {
        $destination = Join-Path $TestDrive 'imports'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        $absolute = Join-Path ([System.IO.Path]::GetPathRoot(
            [System.IO.Path]::GetFullPath($destination)
        )) 'outside'

        {
            Resolve-RenderKitProjectImportTargetRoot `
                -DestinationRoot $destination `
                -ProjectName $absolute
        } | Should -Throw '*Unsafe project name*'

        {
            Resolve-RenderKitProjectImportTargetRoot `
                -DestinationRoot $destination `
                -ProjectName 'nested/project'
        } | Should -Throw '*Unsafe project name*'
    }
}
