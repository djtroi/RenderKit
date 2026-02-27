function Get-RenderKitProject{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [string]$Path
    )

    Write-RenderKitLog -Level Debug -Message "Get-RenderKitProject started: ProjectName='$ProjectName', Path='$Path'."

    $searchRoots = @()

    if ($Path) {
        $searchRoots += $Path  
    }
    else {
        $config = Get-RenderKitConfig
        if ($config.DefaultProjectPath){
            $searchRoots += $config.DefaultProjectPath
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
            Write-RenderKitLog -Level Error -Message "Invalid project metadata JSON in '$metaPath'."
            throw "Invalid project metadata JSON in $metaPath"
        }

        #validation

        if (
            !($meta.project.id) -or
            !($meta.project.name) -or
            $meta.tool -ne "RenderKit"
        ) {
            Write-RenderKitLog -Level Error -Message "Invalid RenderKit project metadata schema in '$metaPath'."
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

    Write-RenderKitLog -Level Error -Message "RenderKit project '$ProjectName' not found in search roots: $($searchRoots -join ', ')."
    throw "RenderKit project $ProjectName not found"
}
