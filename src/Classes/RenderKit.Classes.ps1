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
    [System.Collections.Generic.List[RenderKitFolder]]$Folders

    RenderKitTemplate([string]$name) {
        $this.Name      =   $name 
        $this.Mappings  =   @()
        $this.Folders   =   [System.Collections.Generic.List[RenderKitFolder]]::new()
    }

    [void]AddMapping([string]$mappingId) {
        $this.Mappings += $mappingId 
    }

    [void]AddFolder([RenderKitFolder]$Folder) {
        $this.Folders.Add($Folder)
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

class RenderKitFolder {
    [string]$Name
    [string]$Mapping
    [System.Collections.Generic.List[RenderKitFolder]]$SubFolders

    RenderKitFolder([string]$Name, [string]$Mapping) {
        $this.Name          =   $Name
        $this.Mapping       =   $Mapping
        $this.SubFolders    =   [System.Collections.Generic.List[RenderKitFolder]]::new()
        }

        [void]AddSubFolder([RenderKitFolder]$Folder) {
            $this.SubFolders.Add($Folder)
        }
}