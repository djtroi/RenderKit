function Resolve-ProjectTemplate {
    param(
        [string]$TemplateName,
        [string]$TemplatePath
    )

    Write-RenderKitLog -Level Debug -Message "Resolving project template..."

    #explicit path wins

    if ($TemplatePath) {

        if (!(Test-Path $TemplatePath)) {
            Write-RenderKitLog -Level Error -Message "Template not found at path: $TemplatePath"
        }

        return @{
            Name        =   [IO.Path]::GetFileNameWithoutExtension($TemplatePath)
            Path        =   (Resolve-Path $TemplatePath).Path 
            Source      =   "custom"
        }
    }

    #resolve by name (User overrides system)

    if ($TemplateName) {
        $templates = Get-RenderKitTemplates 
        $match = $templates | Where-Object Name -eq $TemplateName

        if (!($match)) {
            Write-RenderKitLog -Level Error -Message "$TemplateName not found. Available templates: $($templates.Name -join ', ')"
        }

        return @{
            Name        =   $match.Name
            Path        =   $match.Path 
            Source      =   if ($match.IsSystem) { "system" } else { "user" }
        }
    }

    #default template resolution

    Write-RenderKitLog -Level Warning -Message "No template specified. Resolving default template..."

    $templates = Get-RenderKitTemplates 
    $default = $templates | Where-Object Name -eq "default"

    if (!($default)) {
        Write-RenderKitLog -Level Error -Message "Default template not found"
    }

    return @{
        Name        =   $default.Name
        Path        =   $default.Path
        Source      =   if ($default.IsSystem) { "system" } else { "user" }
    }

}