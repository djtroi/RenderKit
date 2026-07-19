BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Project/RenderKit.ProjectLifecycleService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Import/RenderKit.ImportService.ps1')
    function Write-RenderKitLog { param([string]$Level, [string]$Message) }
}

Describe 'RenderKit import service' {
    It 'loads a system mapping after the storage path normalization change' {
        $systemMappingPath = Join-Path $TestDrive 'video.json'
        '{"Id":"video","Types":[]}' |
            Set-Content -LiteralPath $systemMappingPath

        Mock Get-RenderKitUserMappingPath {
            Join-Path $TestDrive 'missing-user-mapping.json'
        }
        Mock Get-RenderKitSystemMappingPath { $systemMappingPath }

        $mapping = Read-RenderKitImportMappingFile -MappingId 'video'

        $mapping.Id | Should -Be 'video'
        Should -Invoke Get-RenderKitSystemMappingPath `
            -Exactly 1 `
            -ParameterFilter { $MappingId -eq 'video' }
    }

    It 'only materializes rows that are visible in the import preview' {
        Mock Write-RenderKitLog
        $files = for ($index = 0; $index -lt 20; $index++) {
            $file = [PSCustomObject]@{
                RelativeDirectory = '.'
                LastWriteTime = [datetime]::UtcNow
                Length = [int64]1
            }
            if ($index -lt 3) {
                $file | Add-Member -NotePropertyName Name -NotePropertyValue "file-$index.mov"
            }
            else {
                $file | Add-Member -MemberType ScriptProperty -Name Name -Value {
                    throw 'A non-visible preview row was materialized.'
                }
            }
            $file
        }

        Show-RenderKitImportPreviewTable `
            -Files $files `
            -PreviewCount 3 `
            -Title 'Bounded preview'

        Should -Invoke Write-RenderKitLog `
            -ParameterFilter {
                $Message -eq 'Showing first 3 of 20 file(s).'
            }
    }

    It 'rejects an archived target before an import transfer starts' {
        $projectRoot = Join-Path $TestDrive 'archived-project'
        $metadataRoot = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
        @{
            project = @{ id = 'archived-project'; name = 'Archived project' }
            lifecycle = @{ status = 'Archived'; history = @() }
        } | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $metadataRoot 'project.json')

        {
            Assert-RenderKitImportProjectAcceptsTransfer `
                -ProjectRoot $projectRoot
        } | Should -Throw '*Archived*terminal*'
    }

    It 'accepts an active target for an import transfer' {
        $projectRoot = Join-Path $TestDrive 'active-project'
        $metadataRoot = Join-Path $projectRoot '.renderkit'
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
        @{
            project = @{ id = 'active-project'; name = 'Active project' }
            lifecycle = @{ status = 'Active'; history = @() }
        } | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $metadataRoot 'project.json')

        Assert-RenderKitImportProjectAcceptsTransfer `
            -ProjectRoot $projectRoot |
            Should -Be (Resolve-Path -LiteralPath $projectRoot).ProviderPath
    }
}
