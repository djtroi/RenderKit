BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Import/RenderKit.ImportInteractiveMenuService.ps1')
}

Describe 'RenderKit interactive import menu' {
    It 'builds the Import-Media setup options without turning IsDefault into an object array' {
        $script:capturedOptions = @()
        Mock Invoke-RenderKitInteractiveMenu {
            $script:capturedOptions = @($Options)
            return [PSCustomObject]@{
                Action = 'Cancel'
                Option = $null
            }
        }

        Start-RenderKitImportInteractiveSetupMenu | Should -BeNullOrEmpty

        $script:capturedOptions.Count | Should -Be 9
        $script:capturedOptions[0].Key | Should -Be 'project'
        $script:capturedOptions[0].IsDefault | Should -BeOfType ([bool])
        $script:capturedOptions[0].IsDefault | Should -BeTrue
        @($script:capturedOptions | Where-Object { $_ -isnot [PSCustomObject] }).Count | Should -Be 0
    }

    It 'writes the menu to the host without leaking screen text into the layout result' {
        Mock Clear-Host
        Mock Write-Host
        $options = @(
            New-RenderKitInteractiveMenuOption -Key 'one' -Label 'One'
            New-RenderKitInteractiveMenuOption -Key 'two' -Label 'Two'
        )

        $result = @(Write-RenderKitInteractiveMenuScreen -Title 'Test' -Options $options)

        $result.Count | Should -Be 1
        $result[0].PageSize | Should -Be 2
    }

    It 'falls back to numbered text input when raw key input is unavailable' {
        Mock Clear-Host
        Mock Write-Host
        Mock Read-RenderKitInteractiveMenuKey { return $null }
        Mock Read-Host { return '2' }
        $options = @(
            New-RenderKitInteractiveMenuOption -Key 'one' -Label 'One' -Value 1
            New-RenderKitInteractiveMenuOption -Key 'two' -Label 'Two' -Value 2
        )

        $result = Invoke-RenderKitInteractiveMenu -Title 'Test' -Options $options

        $result.Action | Should -Be 'Select'
        $result.Option.Key | Should -Be 'two'
        $result.Value | Should -Be 2
    }

    It 'supports multi-selection in text input mode' {
        Mock Clear-Host
        Mock Write-Host
        $script:responses = [System.Collections.Generic.Queue[string]]::new()
        $script:responses.Enqueue('1')
        $script:responses.Enqueue('3')
        $script:responses.Enqueue('')
        Mock Read-Host { return $script:responses.Dequeue() }
        $options = @(
            New-RenderKitInteractiveMenuOption -Key 'one' -Label 'One' -Value 1
            New-RenderKitInteractiveMenuOption -Key 'two' -Label 'Two' -Value 2
            New-RenderKitInteractiveMenuOption -Key 'three' -Label 'Three' -Value 3
        )

        $result = Invoke-RenderKitInteractiveMenuTextMode `
            -Title 'Test' `
            -Options $options `
            -MultiSelect

        $result.Action | Should -Be 'Select'
        @($result.SelectedValues) | Should -Be @(1, 3)
    }
}
