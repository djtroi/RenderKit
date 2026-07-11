Describe 'RenderKit release documentation' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot
        )
        $manifest = Import-PowerShellDataFile (
            Join-Path $repositoryRoot 'RenderKit.psd1'
        )
        $readme = Get-Content (
            Join-Path $repositoryRoot 'README.md'
        ) -Raw
        $changelog = Get-Content (
            Join-Path $repositoryRoot 'CHANGELOG.md'
        ) -Raw
        $reference = Get-Content (
            Join-Path $repositoryRoot 'docs/public-functions.md'
        ) -Raw
    }

    It 'keeps manifest, README, and changelog release versions aligned' {
        $version = [regex]::Escape([string]$manifest.ModuleVersion)

        $readme | Should -Match (
            "Current repository version:\s+\*\*$version\*\*"
        )
        $changelog | Should -Match "(?m)^## $version(?:\s|$)"
    }

    It 'documents every exported function in the complete reference' {
        $missing = @($manifest.FunctionsToExport | Where-Object {
            $reference -notmatch [regex]::Escape("``$_``")
        })

        $missing | Should -BeNullOrEmpty
    }

    It 'contains no obsolete Clone-Project command guidance' {
        $documentation = @(
            Get-Item (Join-Path $repositoryRoot 'README.md')
            Get-ChildItem (Join-Path $repositoryRoot 'docs') `
                -Recurse `
                -File `
                -Filter '*.md'
        )

        foreach ($file in $documentation) {
            (Get-Content $file.FullName -Raw) |
                Should -Not -Match '(?i)Clone-Project'
        }
    }

    It 'resolves every relative Markdown link' {
        $documentation = @(
            Get-Item (Join-Path $repositoryRoot 'README.md')
            Get-ChildItem (Join-Path $repositoryRoot 'docs') `
                -Recurse `
                -File `
                -Filter '*.md'
        )

        $broken = New-Object System.Collections.Generic.List[string]
        foreach ($file in $documentation) {
            $content = Get-Content $file.FullName -Raw
            foreach ($match in [regex]::Matches(
                $content,
                '\[[^\]]+\]\(([^)]+)\)'
            )) {
                $target = ([string]$match.Groups[1].Value -split '#', 2)[0]
                if ([string]::IsNullOrWhiteSpace($target) -or
                    $target -match '^(?:https?://|mailto:)') {
                    continue
                }

                $resolved = Join-Path $file.DirectoryName $target
                if (-not (Test-Path -LiteralPath $resolved)) {
                    $broken.Add("$($file.FullName) -> $target")
                }
            }
        }

        @($broken.ToArray()) | Should -BeNullOrEmpty
    }
}
