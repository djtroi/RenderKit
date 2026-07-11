Register-RenderKitFunction "New-MetadataTemplate"
function New-MetadataTemplate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [string]$Description,

        [switch]$Force
    )

    $path = Get-RenderKitMetadataTemplatePath -Name $Name
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and -not $Force) {
        throw "Metadata template '$Name' already exists. Use -Force to overwrite it."
    }

    if (-not $PSCmdlet.ShouldProcess($path, "Create metadata template '$Name'")) {
        return
    }

    $template = New-RenderKitMetadataTemplateObject `
        -Name $Name `
        -Description $Description
    $result = Write-RenderKitMetadataTemplate -Template $template
    return [PSCustomObject]@{
        Name = [string]$result.Template.name
        Description = [string]$result.Template.description
        Generation = [int]$result.Template.revision.generation
        FieldCount = @($result.Template.fields.PSObject.Properties).Count
        Path = [string]$result.Path
    }
}
