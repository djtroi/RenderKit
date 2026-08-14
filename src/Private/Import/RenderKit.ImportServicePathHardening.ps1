function Get-RenderKitImportProjectCandidate {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [string]$BasePath
    )

    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace($BasePath)) {
        $roots += $BasePath
    }
    else {
        $config = Get-RenderKitConfig
        if ($config) {
            if (
                $config -is [hashtable] -and
                $config.ContainsKey('DefaultProjectPath') -and
                -not [string]::IsNullOrWhiteSpace([string]$config.DefaultProjectPath)
            ) {
                $roots += [string]$config.DefaultProjectPath
            }
            elseif (
                $config.PSObject.Properties.Name -contains 'DefaultProjectPath' -and
                -not [string]::IsNullOrWhiteSpace([string]$config.DefaultProjectPath)
            ) {
                $roots += [string]$config.DefaultProjectPath
            }
        }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($root in @($roots | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($root) -or
            -not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }

        foreach ($projectDir in @(
                Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue
            )) {
            # Build metadata paths from individual segments. Embedded Windows
            # separators are valid filename characters on Unix and can hide an
            # otherwise valid RenderKit project from discovery.
            $metadataRoot = Join-Path `
                -Path $projectDir.FullName `
                -ChildPath '.renderkit'
            $metadataPath = Join-Path `
                -Path $metadataRoot `
                -ChildPath 'project.json'
            if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
                continue
            }

            $metadata = $null
            try {
                $metadata = Get-Content `
                    -LiteralPath $metadataPath `
                    -Raw `
                    -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                continue
            }

            if (-not $metadata -or
                [string]::IsNullOrWhiteSpace([string]$metadata.tool) -or
                [string]$metadata.tool -ne 'RenderKit') {
                continue
            }

            $templateName = $null
            if ($metadata.PSObject.Properties.Name -contains 'template' -and
                $metadata.template -and
                $metadata.template.PSObject.Properties.Name -contains 'name') {
                $templateName = [string]$metadata.template.name
            }

            $createdAt = $null
            if ($metadata.PSObject.Properties.Name -contains 'project' -and
                $metadata.project -and
                $metadata.project.PSObject.Properties.Name -contains 'createdAt') {
                $createdAt = [string]$metadata.project.createdAt
            }

            $projectName = $projectDir.Name
            if ($metadata.PSObject.Properties.Name -contains 'project' -and
                $metadata.project -and
                $metadata.project.PSObject.Properties.Name -contains 'name' -and
                -not [string]::IsNullOrWhiteSpace([string]$metadata.project.name)) {
                $projectName = [string]$metadata.project.name
            }

            $candidates.Add([PSCustomObject]@{
                    Name        = $projectName
                    ProjectRoot = $projectDir.FullName
                    Template    = $templateName
                    CreatedAt   = $createdAt
                })
        }
    }

    return @($candidates.ToArray() | Sort-Object Name, ProjectRoot)
}
