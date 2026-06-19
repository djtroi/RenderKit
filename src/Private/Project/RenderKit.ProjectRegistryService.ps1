function New-RenderKitProjectRegistry {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        tool          = 'RenderKit'
        schemaVersion = '1.0'
        updatedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        projects      = @()
    }
}

function Test-RenderKitProjectRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Registry
    )

    if ($Registry.tool -ne 'RenderKit') {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Registry.schemaVersion)) {
        return $false
    }

    $compatibility = Test-RenderKitArtifactCompatibility `
        -ArtifactType ProjectRegistry `
        -Version ([string]$Registry.schemaVersion)

    return [bool]($compatibility.CanRead -and $compatibility.CanWrite)
}

function Read-RenderKitProjectRegistry {
    [CmdletBinding()]
    param()

    $path = Get-RenderKitProjectRegistryPath
    $registry = Read-RenderKitJsonFile `
        -Path $path `
        -AllowMissing `
        -Validator { param($value) Test-RenderKitProjectRegistry $value }

    if (-not $registry) {
        return New-RenderKitProjectRegistry
    }

    if (-not ($registry.PSObject.Properties.Name -contains 'projects') -or
        $null -eq $registry.projects) {
        $registry | Add-Member -NotePropertyName projects `
            -NotePropertyValue @() `
            -Force
    }

    return $registry
}

function Write-RenderKitProjectRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Registry
    )

    $Registry.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $path = Get-RenderKitProjectRegistryPath
    Write-RenderKitJsonFileAtomic `
        -Path $path `
        -Value $Registry `
        -Depth 8 `
        -Validator { param($value) Test-RenderKitProjectRegistry $value } |
        Out-Null

    return $Registry
}

function New-RenderKitProjectRegistryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectId,
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [object]$Metadata
    )

    $fullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
    $version = $null
    if ($Metadata -and $Metadata.projectVersion) {
        $version = [string]$Metadata.projectVersion
    }

    return [PSCustomObject]@{
        id          = $ProjectId
        name        = $ProjectName
        rootPath    = $fullPath
        version     = $version
        metadataPath = Get-RenderKitProjectMetadataPath -ProjectRoot $fullPath
        exists      = [bool](Test-Path -LiteralPath $fullPath -PathType Container)
        updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Set-RenderKitProjectRegistryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectId,
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [object]$Metadata
    )

    $registry = Read-RenderKitProjectRegistry
    $entry = New-RenderKitProjectRegistryEntry `
        -ProjectId $ProjectId `
        -ProjectName $ProjectName `
        -ProjectRoot $ProjectRoot `
        -Metadata $Metadata

    $path = Get-RenderKitProjectRegistryPath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitProjectRegistry) `
        -Depth 8 `
        -Validator { param($value) Test-RenderKitProjectRegistry $value } `
        -Update {
            param($currentRegistry)

            if (-not ($currentRegistry.PSObject.Properties.Name -contains 'projects') -or
                $null -eq $currentRegistry.projects) {
                $currentRegistry | Add-Member -NotePropertyName projects `
                    -NotePropertyValue @() `
                    -Force
            }

            $remaining = @($currentRegistry.projects | Where-Object {
                [string]$_.id -ne $entry.id -and
                [string]$_.rootPath -ne $entry.rootPath
            })
            $currentRegistry.projects = @($remaining + $entry |
                Sort-Object -Property name, rootPath)
            $currentRegistry.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $currentRegistry
        } |
        Out-Null

    return $entry
}

function Remove-RenderKitProjectRegistryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectId
    )

    $path = Get-RenderKitProjectRegistryPath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitProjectRegistry) `
        -Depth 8 `
        -Validator { param($value) Test-RenderKitProjectRegistry $value } `
        -Update {
            param($currentRegistry)
            $currentRegistry.projects = @($currentRegistry.projects |
                Where-Object { [string]$_.id -ne $ProjectId })
            $currentRegistry.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $currentRegistry
        } |
        Out-Null
}

function Resolve-RenderKitProjectRegistryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )

    $registry = Read-RenderKitProjectRegistry
    $matches = @($registry.projects | Where-Object {
        [string]$_.name -eq $ProjectName -and
        [bool]$_.exists -and
        (Test-Path -LiteralPath ([string]$_.rootPath) -PathType Container)
    })

    if ($matches.Count -eq 0) {
        return $null
    }
    if ($matches.Count -gt 1) {
        throw "Multiple RenderKit projects named '$ProjectName' are registered. Provide -Path to disambiguate."
    }

    return $matches[0]
}

function Repair-RenderKitProjectRegistry {
    [CmdletBinding()]
    param()

    $path = Get-RenderKitProjectRegistryPath
    Invoke-RenderKitJsonFileTransaction `
        -Path $path `
        -DefaultValue (New-RenderKitProjectRegistry) `
        -Depth 8 `
        -Validator { param($value) Test-RenderKitProjectRegistry $value } `
        -Update {
            param($currentRegistry)

            $updated = @()
            foreach ($entry in @($currentRegistry.projects)) {
                $entry.exists = [bool](Test-Path `
                    -LiteralPath ([string]$entry.rootPath) `
                    -PathType Container)
                $entry.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
                $updated += $entry
            }
            $currentRegistry.projects = $updated
            $currentRegistry.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            return $currentRegistry
        } |
        Out-Null

    return Read-RenderKitProjectRegistry
}