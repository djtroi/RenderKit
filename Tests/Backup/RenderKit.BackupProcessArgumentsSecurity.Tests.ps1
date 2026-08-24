BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Backup/RenderKit.BackupProcessExecution.ps1')
}

Describe 'Backup process argument quoting security' {
    It 'keeps simple arguments unquoted' {
        ConvertTo-BackupProcessArgumentText -Arguments @('ffmpeg', '-y') |
            Should -Be 'ffmpeg -y'
    }

    It 'preserves an empty argument as an explicit quoted argument' {
        ConvertTo-BackupProcessArgumentText -Arguments @('') |
            Should -Be '""'.Replace('\', '')
    }

    It 'quotes whitespace without changing the argument boundary' {
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Files\clip.mov') |
            Should -Be '"C:\Media Files\clip.mov"'.Replace('\"', '"')
    }

    It 'escapes an embedded quote so following option-like text stays inside one argument' {
        ConvertTo-BackupProcessArgumentText -Arguments @('clip" -y') |
            Should -Be '"clip\" -y"'.Replace('\"', '"', 1)
    }

    It 'doubles trailing backslashes before a closing quote' {
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Folder\') |
            Should -Be '"C:\Media Folder\\"'.Replace('\"', '"', 1)
    }

    It 'preserves backslashes that do not precede a quote' {
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Files\sub\clip.mov') |
            Should -Be '"C:\Media Files\sub\clip.mov"'.Replace('\"', '"')
    }
}
