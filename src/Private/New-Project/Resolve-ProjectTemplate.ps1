function Resolve-ProjectTemplate {

    param(
        [string]$TemplateName
    )

    Write-RenderKitLog -Level Debug -Message "Resolving project template..."

    $templates = Get-RenderKitTemplates

    # user template input overrides system
    if ($TemplateName) {

        $match = $templates |
            Where-Object Name -eq $TemplateName |
            Sort-Object @{Expression = {$_.Source -eq "user"}; Descending = $true} |
            Select-Object -First 1

        if (-not $match) {
            throw "Template '$TemplateName' not found."
        }

        return $match
    }

    # fallback to default
    $default = $templates |
        Where-Object Name -eq "default" |
        Sort-Object @{Expression = {$_.Source -eq "user"}; Descending = $true} |
        Select-Object -First 1

    if (-not $default) {
        throw "Default template not found."
    }

    return $default
}