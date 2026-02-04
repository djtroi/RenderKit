function Get-CleanupRules{
    param(
        [string[]]$Software
    )
    $rules = @{
        Folders = @()
        Extensions = @()
    }
    foreach ($s in $Software){
        if ($CleanupProfiles[$s]){
            $rules.Folders += $CleanupProfiles[$s].Folders
            $rules.Extensions += $CleanupProfiles[$s].Extensions
        }
    }
    return $rules
}