function Get-RenderKitProject{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [string]$Path
    )

    $searchRoots = @()

    if ($Path) {
        $searchRoots += $Path  
    }
    else {
        $config = Get-RenderKitProject
        if ($config.DefaultProjectPath){
            $searchRoot += $config.DefaultProjectPath
        }
    }

    foreach ($root in $searchRoots){

        $candidate = Join-Path $root $ProjectName
        if (!(Test-Path $candidate)) { continue }
        try {
            $metaPath = Join-Path $candidate "\.renderkit\project.json"
            $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
        }

        catch {
            throw "Invalid project metadata JSON in $metaPath"
        }

        #validation

        if (
            !($meta.project.id) -or
            !($meta.project.name) -or
            $meta.tool -ne "RenderKit"
        ) {
            throw "Invalid RenderKit project metadata schema"
        }

        return [PSCustomObject]@{
            id              =  $meta.project.id
            Name            =  $meta.project.name
            RootPath        =  $candidate
            MetadataPath    =  $metaPath
            Metadata        =  $meta
        }
    } 

    throw "RenderKit project $ProjectName not found"
}