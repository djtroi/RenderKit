function Get-ProjectPath{
param(
    [string]$ProjectName,
    [string]$BasePath
)

Write-RenderKitLog -Level Debug -Message "Get-ProjectPath started: ProjectName='$ProjectName', BasePath='$BasePath'."

$path = Join-Path $BasePath $ProjectName
if (!(Test-Path $path)){
    Write-RenderKitLog -Level Error -Message "Project path not found: $path"
    throw "Project not found: $path"
}
return $path 
}
