BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repositoryRoot 'src/Private/Backup/RenderKit.BackupProcessExecution.ps1')
}

Describe 'Backup process argument quoting security' {
    BeforeAll {
        $quote = [string][char]34
    }

    It 'keeps simple arguments unquoted' {
        ConvertTo-BackupProcessArgumentText -Arguments @('ffmpeg', '-y') |
            Should -Be 'ffmpeg -y'
    }

    It 'preserves an empty argument as an explicit quoted argument' {
        ConvertTo-BackupProcessArgumentText -Arguments @('') |
            Should -Be ($quote + $quote)
    }

    It 'quotes whitespace without changing the argument boundary' {
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Files\clip.mov') |
            Should -Be ($quote + 'C:\Media Files\clip.mov' + $quote)
    }

    It 'escapes an embedded quote so following option-like text stays inside one argument' {
        ConvertTo-BackupProcessArgumentText -Arguments @('clip" -y') |
            Should -Be ($quote + 'clip\" -y' + $quote)
    }

    It 'doubles trailing backslashes before a closing quote' {
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Folder\') |
            Should -Be ($quote + 'C:\Media Folder\\' + $quote)
    }

    It 'preserves backslashes that do not precede a quote' {
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Files\sub\clip.mov') |
            Should -Be ($quote + 'C:\Media Files\sub\clip.mov' + $quote)
    }
}
