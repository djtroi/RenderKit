function Get-ProjectPath{
param(
    [string]$ProjectName,
    [string]$BasePath
)
$path = Join-Path $BasePath $ProjectName
if (!(Test-Path $path)){
    throw "Project not found: $path"
}
return $path 
}