function Remove-ProjectArtifacts{
    param(
        [string]$ProjectPath,
        [hashtable]$rules,
        [switch]$DryRun
    )
    Get-ChildItem $ProjectPath -Recurse -Force | ForEach-Object {

        if ($Rules.Extensions -contains $_.Extension){
            if ($DryRun){
                Write-Verbose "[DRY] Remove file $($_.FullName)"
            }
            else {
                Remove-Item $_.FullName -Force
            }
        }
        if ($_.PSIsContainer -and $rules.Folders -contains $_.Name){
            if ($DryRun){
                Write-Verbose "[DRY] Remove file $($_.FullName)"
            }
            else {
                Remove-Item $_.FullName -Recurse -Force
            }
        }
    }
}