#Get the Project name that you want to backup 
#--> read out all the folders and create an array of cache files that should be deleted 
#--> delete cache files 
#--> delete empty folder 
#--> get the project folder and zip it 
New-Alias -Name Archive-Project -Value Backup-Project
New-Alias -Name archive -Value Backup-Project
function Backup-Project{
param(
    [parameter(Mandatory)]
    [string]$projectName,
    [string]$path
)

foreach($files in [System.IO.DirectoryInfo]::new($path).EnumerateFiles()){

}
$cache = @(
    @{Ext = ".cache"}
    @{Ext = ".tmp"}

)
foreach($c in $cache){
    if(!([String]::IsNullOrEmpty($c.Path))){
        Test-Directory -Path $c.Path
    }
    
}


}
function Get-EmptyFolders {
    param(
        [Parameter(Mandatory)]
        [string]$path,
        [Paramater(Mandatory)]
        [string]$dirInfo = [System.IO.DirectoryInfo]::new($path)
    )
}

function Remove-EmptyFolders{
    param(
        
    )
}