function Get-Platform {
    if ($IsWindows) { return "windows" }
    if ($isMacOs) { return "macos" }
    if ($IsLinux) { return "linux" }
    else {
        return "unknown"
    }
}

function Get-RenderKitProjectMetadataPath{
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    return Join-Path $ProjectRoot ".renderkit\project.json"
}

function New-RenderKitProjectMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [Parameter(Mandatory)]
        [string]$TemplateName,
        [Parameter(Mandatory)]
        [string]$TemplateSource
    )

    return [PSCustomObject]@{
        tool            = "RenderKit"
        schemaVersion   = "1.0"

        project = @{
            id          = ([guid]::NewGuid()).guid
            name        = $ProjectName
            createdAt   = (Get-Date).ToString("o") # ISO 8601
            createdBy   = $env:USERNAME
            platform    = Get-Platform
            toolVersion = $script:RenderKitModule.Version.ToString() #$script:RenderKitVersion
        }

        paths = @{
            root        = "."
        }

        template = @{
            name        = $TemplateName
            source      = $TemplateSource
        }
    }
}

function Write-RenderKitProjectMetadata{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter(Mandatory)]
        [object]$Metadata
    )

    $renderKitDir = Join-Path $ProjectRoot ".renderkit"

    if (!(Test-Path $renderKitDir)){
        New-Item -ItemType Directory -Path $renderKitDir | Out-Null
    }
    $jsonPath = Get-RenderKitProjectMetadataPath -ProjectRoot $ProjectRoot

    $Metadata | 
    ConvertTo-Json -Depth 6 | 
    Set-Content -Path $jsonPath -Encoding UTF8
}