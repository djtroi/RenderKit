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
        $registered = Resolve-RenderKitProjectRegistryEntry `
            -ProjectName $ProjectName
        if ($registered) {
            $Path = Split-Path -Path ([string]$registered.rootPath) -Parent
            $searchRoots += $Path
        }

        $config = Get-RenderKitConfig
        if ($config.DefaultProjectPath -and
            $searchRoots -notcontains $config.DefaultProjectPath){
            $searchRoots += $config.DefaultProjectPath
        }
    }

    foreach ($root in $searchRoots){

        $candidate = Join-Path $root $ProjectName
        if (!(Test-Path $candidate)) { continue }
        try {
            $metaPath = Get-RenderKitProjectMetadataPath -ProjectRoot $candidate
            $meta = Read-RenderKitJsonFile -Path $metaPath
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

        $project = [PSCustomObject]@{
            id              =  $meta.project.id
            Name            =  $meta.project.name
            RootPath        =  $candidate
            MetadataPath    =  $metaPath
            Metadata        =  $meta
            Status          =  Get-RenderKitProjectStatus -Metadata $meta
        }

        Set-RenderKitProjectRegistryEntry `
            -ProjectId ([string]$project.id) `
            -ProjectName ([string]$project.Name) `
            -ProjectRoot ([string]$project.RootPath) `
            -Metadata $meta |
            Out-Null

        return $project
    }

    Write-RenderKitLog -Level Error -Message "RenderKit project '$ProjectName' not found in search roots: $($searchRoots -join ', ')."
    throw "RenderKit project $ProjectName not found"
}
