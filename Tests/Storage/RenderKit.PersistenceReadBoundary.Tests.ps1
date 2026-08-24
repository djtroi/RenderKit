BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.StorageService.ps1')
    . (Join-Path $repositoryRoot 'src/Private/Storage/RenderKit.PersistenceService.ps1')
}

Describe 'RenderKit JSON read boundary' {
    It 'enforces the byte limit in the text reader itself' {
        $path = Join-Path $TestDrive 'oversized.json'
        [System.IO.File]::WriteAllText($path, '{"value":"0123456789"}')

        {
            Read-RenderKitTextFile -Path $path -MaximumBytes 8
        } | Should -Throw '*exceeds the 8 byte limit*'
    }

    It 'still reads a valid document below the byte limit' {
        $path = Join-Path $TestDrive 'valid.json'
        [System.IO.File]::WriteAllText($path, '{"value":1}')

        $value = Read-RenderKitJsonFile -Path $path -MaximumBytes 64
        $value.value | Should -Be 1
    }
}
