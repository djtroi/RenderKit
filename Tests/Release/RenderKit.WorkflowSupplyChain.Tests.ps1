Describe 'RenderKit workflow action supply-chain policy' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $workflowRoot = Join-Path $repositoryRoot '.github/workflows'
    }

    It 'pins every remote workflow action to an immutable commit SHA' {
        $violations = New-Object 'System.Collections.Generic.List[string]'
        $workflowFiles = @(
            Get-ChildItem `
                -LiteralPath $workflowRoot `
                -Filter '*.yml' `
                -File
        )

        foreach ($workflowFile in $workflowFiles) {
            $lineNumber = 0
            foreach ($line in @(Get-Content -LiteralPath $workflowFile.FullName)) {
                $lineNumber++
                if ($line -notmatch '^\s*(?:-\s*)?uses:\s*(?<target>[^\s#]+)') {
                    continue
                }

                $target = [string]$Matches.target
                $target = $target.Trim("'`"")
                if ($target.StartsWith('./')) {
                    continue
                }

                if ($target -notmatch '@[0-9a-fA-F]{40}$') {
                    [void]$violations.Add(
                        "$($workflowFile.Name):$lineNumber -> $target")
                }
            }
        }

        @($violations) | Should -BeNullOrEmpty `
            -Because ('remote workflow actions must be immutable: ' +
                ($violations -join ', '))
    }
}
