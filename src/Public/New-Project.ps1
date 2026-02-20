function New-Project {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        [Parameter(Position = 1)]
        [string]$Template,
        [string]$Path
    )
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

    New-RenderKitProjectFromTemplate `
        -ProjectName $Name `
        -ProjectRoot $ProjectRoot `
        -Template $templateObject

    Write-RenderKitLog -Level Info -Message "Project '$Name' created successfully."
}
