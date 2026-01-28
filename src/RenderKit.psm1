Get-ChildItem "$PSScriptRoot\Public\*.ps1" | ForEach-Object { . $_ } 
Get-ChildItem "$PSSciptRoot\Private\*.ps1" | ForEach-Object { . $_ }