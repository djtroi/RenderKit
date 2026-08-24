BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Backup/RenderKit.BackupProcessExecution.ps1')
    $script:Quote = [char]34
}

Describe 'Backup process argument quoting security' {
    It 'keeps simple arguments unquoted' {
        ConvertTo-BackupProcessArgumentText -Arguments @('ffmpeg', '-y') |
            Should -Be 'ffmpeg -y'
    }

    It 'preserves an empty argument as an explicit quoted argument' {
        $expected = "$script:Quote$script:Quote"
        ConvertTo-BackupProcessArgumentText -Arguments @('') |
            Should -Be $expected
    }

    It 'quotes whitespace without changing the argument boundary' {
        $expected = "$script:Quote" + 'C:\Media Files\clip.mov' + "$script:Quote"
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Files\clip.mov') |
            Should -Be $expected
    }

    It 'escapes an embedded quote so following option-like text stays inside one argument' {
        $expected = "$script:Quote" + 'clip\" -y' + "$script:Quote"
        ConvertTo-BackupProcessArgumentText -Arguments @('clip" -y') |
            Should -Be $expected
    }

    It 'doubles trailing backslashes before a closing quote' {
        $expected = "$script:Quote" + 'C:\Media Folder\\' + "$script:Quote"
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Folder\') |
            Should -Be $expected
    }

    It 'preserves backslashes that do not precede a quote' {
        $expected = "$script:Quote" + 'C:\Media Files\sub\clip.mov' + "$script:Quote"
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Files\sub\clip.mov') |
            Should -Be $expected
    }
}
