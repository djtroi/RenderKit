class RenderKitMapping{
    [string]$Id
    [System.Collections.Generic.List[RenderKitType]]$Types

    RenderKitMapping([string]$id) {
        $this.Id    =   $id
        $this.Types =   [System.Collections.Generic.List[RenderKitType]]::new()
    }

    [void]AddType([RenderKitType]$type) {
        this.Types.Add($type)
    }
}

class RenderKitTemplate {
    [string]$Name
    [string[]]$Mappings

    RenderKitTemplate([string]$name) {
        $this.Name      =   $name 
        $this.Mappings  =   @()
        $this.Folders   =   @()
    }

    [void]AddMapping([string]$mappingId) {
        $this.Mappings += $mappingId 
    }

    [void]AddFolders([string]$FolderName) {
        $this.Folders += $FolderName
    }
}

class RenderKitType {
    [string]$Name
    [string[]]$Extensions

    RenderKitType([string]$Name, [string[]]$Extensions){
        $this.Name = $Name
        $this.Extensions = $Extensions
    }
}