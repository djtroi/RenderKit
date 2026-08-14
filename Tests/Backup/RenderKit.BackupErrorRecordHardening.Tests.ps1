Describe 'RS-1518 backup error record hardening' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        Import-Module `
            (Join-Path $repositoryRoot 'RenderKit.psd1') `
            -Force
    }

    AfterAll {
        Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    }

    It 'keeps terminating validation failures off the secondary error stream' {
        $definitions = InModuleScope RenderKit {
            [PSCustomObject]@{
                manifest = (Get-Command Save-BackupManifest).Definition
                archivePath = (Get-Command Resolve-BackupArchivePath).Definition
                logInjection = (Get-Command Add-BackupLogsToArchive).Definition
                fileInjection = (Get-Command Add-BackupFileToArchive).Definition
                integrity = (Get-Command Test-BackupArchiveContentIntegrity).Definition
            }
        }

        foreach ($definition in @(
                $definitions.manifest,
                $definitions.archivePath,
                $definitions.logInjection,
                $definitions.fileInjection,
                $definitions.integrity
            )) {
            $definition | Should -Match 'RS-1518'
            $definition | Should -Match 'NoConsole'
        }
    }

    It 'still throws the canonical manifest validation error' {
        InModuleScope RenderKit {
            {
                Save-BackupManifest `
                    -Manifest ([PSCustomObject]@{}) `
                    -ErrorAction Stop
            } | Should -Throw '*Either -ProjectRoot or -ManifestPath*'
        }
    }

    It 'still throws canonical archive injection validation errors' {
        $missingArchive = Join-Path $TestDrive 'missing.zip'
        $missingFile = Join-Path $TestDrive 'missing.txt'

        InModuleScope RenderKit -Parameters @{
            MissingArchive = $missingArchive
            MissingFile = $missingFile
        } {
            {
                Add-BackupFileToArchive `
                    -ArchivePath $MissingArchive `
                    -FilePath $MissingFile `
                    -ErrorAction Stop
            } | Should -Throw '*Archive*was not found*'
        }
    }
}
