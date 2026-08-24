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
    function Write-RenderKitLog { param($Level, $Message) }

    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectImportTargetSecurityService.ps1')
    . (Join-Path $repositoryRoot 'src/Public/Import-Project.ps1')
}

Describe 'Import-Project target reparse security' {
    BeforeEach {
        $destinationRoot = Join-Path $TestDrive 'Imports'
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        $archivePath = Join-Path $TestDrive 'project.rkitpkg'
        Set-Content -LiteralPath $archivePath -Value 'placeholder'
        $script:ImportManifest = [pscustomobject]@{
            RenderKitProjectManifest = [pscustomobject]@{
                schemaVersion = '1.0'
                Project = [pscustomobject]@{
                    sourceRootName = 'ProjectA'
                    name = 'ProjectA'
                }
                Export = [pscustomobject]@{ mode = 'ManifestOnly' }
                Folders = [pscustomobject]@{ Folder = @() }
                Resources = [pscustomobject]@{
                    Templates = [pscustomobject]@{ Template = @() }
                    Mappings = [pscustomobject]@{ Mapping = @() }
                }
                Metadata = [pscustomobject]@{ MetadataFile = @() }
                Files = [pscustomobject]@{ File = @() }
            }
        }
    }

    It 'accepts a normal path below the project root' {
        $root = Join-Path $destinationRoot 'ProjectA'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $nested = Join-Path $root 'media/clip.mov'

        {
            Assert-RenderKitProjectImportTargetPathSafe `
                -TargetRoot $root `
                -Path $nested
        } | Should -Not -Throw
    }

    It 'rejects a symbolic-link project root' {
        $outside = Join-Path $TestDrive 'outside-root'
        $root = Join-Path $destinationRoot 'ProjectA'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null

        try {
            New-Item -ItemType SymbolicLink -Path $root -Target $outside -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'Symbolic link creation is not available on this runner.'
            return
        }

        {
            Assert-RenderKitProjectImportTargetPathSafe -TargetRoot $root -Path $root
        } | Should -Throw '*symbolic link or reparse point*'
    }

    It 'rejects a symbolic-link directory inside the project target' {
        $root = Join-Path $destinationRoot 'ProjectA'
        $outside = Join-Path $TestDrive 'outside-media'
        $link = Join-Path $root 'media'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        New-Item -ItemType Directory -Path $outside -Force | Out-Null

        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'Symbolic link creation is not available on this runner.'
            return
        }

        {
            Assert-RenderKitProjectImportTargetPathSafe `
                -TargetRoot $root `
                -Path (Join-Path $link 'clip.mov')
        } | Should -Throw '*symbolic link or reparse point*'
    }

    It 'refuses overwrite of a symlinked project root before outside data is touched' {
        $outside = Join-Path $TestDrive 'outside-overwrite'
        $sentinel = Join-Path $outside 'do-not-delete.txt'
        $root = Join-Path $destinationRoot 'ProjectA'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content -LiteralPath $sentinel -Value 'protected'

        try {
            New-Item -ItemType SymbolicLink -Path $root -Target $outside -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'Symbolic link creation is not available on this runner.'
            return
        }

        {
            Import-Project `
                -Path $archivePath `
                -DestinationRoot $destinationRoot `
                -ConflictAction Overwrite
        } | Should -Throw '*symbolic link or reparse point*'

        Test-Path -LiteralPath $sentinel -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $sentinel -Raw).Trim() | Should -Be 'protected'
    }
}
