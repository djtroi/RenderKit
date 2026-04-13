Register-RenderKitFunction "New-RenderKitTemplate"
function New-RenderKitTemplate {
    <#
.SYNOPSIS
Creates a new user template file.

.DESCRIPTION
Ensures template storage exists, creates an empty template object, and saves it to disk.

.PARAMETER Name
Template name / filename to create (with or without `.json` extension).

.EXAMPLE
New-RenderKitTemplate -Name "default"
Creates template `default.json` in the user templates folder.

.EXAMPLE
New-RenderKitTemplate -Name "commercial.json"
Creates template file `commercial.json`.

.INPUTS
None. You cannot pipe input to this command.

.OUTPUTS
None. The command creates or updates a template file on disk.

.LINK
Add-FolderToTemplate

.LINK
Add-RenderKitMappingToTemplate

.LINK
https://github.com/djtroi/RenderKit
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    Write-RenderKitLog -Level Debug -Message "New-RenderKitTemplate started: Name='$Name'."

    $templateFolder = Get-RenderKitUserTemplatesRoot
    $templatePath = Get-RenderKitUserTemplatePath -TemplateName $Name

    if (Test-Path $templatePath) {
        Write-RenderKitLog -Level Error -Message "Template $Name already exists."
        return
    }

    if (!(Test-Path $templateFolder)){
        if ($PSCmdlet.ShouldProcess($Name, "Create a new Template Folder")){
        New-Item -ItemType Directory -Path $templateFolder -ErrorAction Stop | Out-Null
        }
        Write-RenderKitLog -Level Debug -Message "No template folder in AppData... creating one."
    }
    $template = [RenderKitTemplate]::new($Name)
    if ($PSCmdlet.ShouldProcess($Name, "Create a new Template")){
        Write-RenderKitTemplateFile -Template $template -Path $templatePath
    }
    Write-RenderKitLog -Level Info -Message "Template $Name created successfully."
}
