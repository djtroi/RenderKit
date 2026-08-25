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
        $quote = [string][char]34
        ConvertTo-BackupProcessArgumentText -Arguments @('') |
            Should -Be ($quote + $quote)
    }

    It 'quotes whitespace without changing the argument boundary' {
        $quote = [string][char]34
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Files\clip.mov') |
            Should -Be ($quote + 'C:\Media Files\clip.mov' + $quote)
    }

    It 'escapes an embedded quote so following option-like text stays inside one argument' {
        $quote = [string][char]34
        ConvertTo-BackupProcessArgumentText -Arguments @('clip" -y') |
            Should -Be ($quote + 'clip\" -y' + $quote)
    }

    It 'doubles trailing backslashes before a closing quote' {
        $quote = [string][char]34
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Folder\') |
            Should -Be ($quote + 'C:\Media Folder\\' + $quote)
    }

    It 'preserves backslashes that do not precede a quote' {
        $quote = [string][char]34
        ConvertTo-BackupProcessArgumentText -Arguments @('C:\Media Files\sub\clip.mov') |
            Should -Be ($quote + 'C:\Media Files\sub\clip.mov' + $quote)
    }
}
