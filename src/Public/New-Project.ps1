<#
.SYNOPSIS
Creates a new project from a template.

.DESCRIPTION
Resolves project path and template, creates metadata/logging structure, and builds folder tree.

.PARAMETER Name
Name of the new project folder.

.PARAMETER Template
Template name to use (with or without `.json` extension).
If omitted, the module's default template resolution is used.

.PARAMETER Path
Base path where the project folder should be created.
If omitted, the default project root from config is used.

.EXAMPLE
New-Project -Name "ClientA_2026"
Creates project `ClientA_2026` using default template and default project root.

.EXAMPLE
New-Project -Name "ClientA_2026" -Template "default"
Creates project with explicit template selection.

.EXAMPLE
New-Project -Name "ClientA_2026" -Template "commercial" -Path "D:\Projects"
Creates project in a custom location with a custom template.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
None. The command creates project structure on disk.

.LINK
Set-ProjectRoot

.LINK
Get-Help Get-ProjectTemplate

.LINK
https://github.com/djtroi/RenderKit
#>
function New-Project {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        [Parameter(Position = 1)]
        [string]$Template,
        [string]$Path
    )
    Write-RenderKitLog -Level Debug -Message "New-Project started: Name='$Name', Template='$Template', Path='$Path'."

    #define Template
    $ProjectRoot = Resolve-ProjectPath -ProjectName $Name -Path $Path
    #project path
    if(Test-Path $ProjectRoot) {
        Write-RenderKitLog -Level Error -Message "Project '$Name' already exists at '$ProjectRoot'."
        throw $_
    }

    #load template
    $templateObject = Get-ProjectTemplate -TemplateName $Template

    Write-RenderKitLog -Level Info -Message "Creating project '$Name' at '$ProjectRoot' using template '$($templateObject.Name)' ($($templateObject.Source))."
    if ($PSCmdlet.ShouldProcess($Name, "New Project from Templte")){
        New-RenderKitProjectFromTemplate `
            -ProjectName $Name `
            -ProjectRoot $ProjectRoot `
            -Template $templateObject
    }
    Write-RenderKitLog -Level Info -Message "Project '$Name' created successfully."
}
