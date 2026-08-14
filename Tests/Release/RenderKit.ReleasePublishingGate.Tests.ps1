Describe 'RS-1520 release publishing gate' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot)
        $workflowPath = Join-Path `
            $repositoryRoot `
            '.github/workflows/release.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
    }

    It 'authorizes publishing only from the exact main push Quality Gate' {
        $workflow | Should -Match "--branch 'main'"
        $workflow | Should -Match '--commit \$env:GITHUB_SHA'
        $workflow | Should -Match '--event push'
        $workflow | Should -Match 'headSha,headBranch,event'
        $workflow | Should -Match "headBranch -eq 'main'"
    }

    It 'serializes release workflow runs without cancelling an active publication' {
        $workflow | Should -Match 'group: renderkit-release'
        $workflow | Should -Match 'cancel-in-progress: false'
    }

    It 'runs publication preflight before any package registry mutation' {
        $workflow | Should -Match 'publish-preflight:'
        $workflow | Should -Match 'Missing repository secret NUGETAPIKEY\. Nothing has been published\.'
        $workflow | Should -Match 'Expected exactly one non-empty CHANGELOG\.md entry'
        $workflow | Should -Match 'Release \$tag already exists'
        $workflow | Should -Match 'needs: \[build, package-compatibility, publish-preflight\]'
    }

    It 'does not hide an orphaned duplicate GitHub package' {
        $workflow | Should -Not -Match '--skip-duplicate'
        $workflow | Should -Match 'An orphaned package from a previous partial'
    }

    It 'creates the visible GitHub Release only after gallery installation validation' {
        $githubReleaseIndex = $workflow.IndexOf("`n  github-release:")
        $galleryValidationIndex = $workflow.IndexOf("`n  gallery-validation:")
        $githubReleaseIndex | Should -BeGreaterThan $galleryValidationIndex
        $workflow | Should -Match '(?s)github-release:.*?- gallery-validation'
        $workflow | Should -Match 'GitHub Release is the final success marker'
    }
}
