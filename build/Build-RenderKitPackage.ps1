[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts'),
    [switch]$SkipPackage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-RenderKitStringLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    return "'{0}'" -f $Value.Replace("'", "''")
}

function ConvertTo-RenderKitArrayLiteral {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$Value
    )

    if (-not $Value -or $Value.Count -eq 0) {
        return '@()'
    }

    $quotedValues = foreach ($item in $Value) {
        "    {0}" -f (ConvertTo-RenderKitStringLiteral -Value $item)
    }

    return "@(`r`n{0}`r`n)" -f ($quotedValues -join "`r`n")
}

function ConvertTo-RenderKitXmlLiteral {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    return [System.Security.SecurityElement]::Escape($Value)
}

function Get-RenderKitSourceFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $Path -Recurse -File -Filter '*.ps1' | Sort-Object -Property FullName)
}

function New-RenderKitDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function New-RenderKitBundledModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [Parameter(Mandatory)]
        [hashtable]$Manifest
    )

    $builder = New-Object System.Text.StringBuilder
    $publicFunctionsLiteral = ConvertTo-RenderKitArrayLiteral -Value @($Manifest.FunctionsToExport)
    $publicAliasesLiteral = ConvertTo-RenderKitArrayLiteral -Value @($Manifest.AliasesToExport)
    $moduleVersionLiteral = ConvertTo-RenderKitStringLiteral -Value ([string]$Manifest.ModuleVersion)

    [void]$builder.AppendLine('$script:RenderKitModuleRoot = $PSScriptRoot')
    [void]$builder.AppendLine('$script:RenderKitModuleVersion = {0}' -f $moduleVersionLiteral)
    [void]$builder.AppendLine('$script:RenderKitPublicFunctions = {0}' -f $publicFunctionsLiteral)
    [void]$builder.AppendLine('$script:RenderKitPublicAliases = {0}' -f $publicAliasesLiteral)
    [void]$builder.AppendLine('')
    [void]$builder.AppendLine('$moduleInfo = $ExecutionContext.SessionState.Module')
    [void]$builder.AppendLine('if ($moduleInfo -and $moduleInfo.Version) {')
    [void]$builder.AppendLine('    $script:RenderKitModuleVersion = $moduleInfo.Version.ToString()')
    [void]$builder.AppendLine('}')
    [void]$builder.AppendLine('')
    [void]$builder.AppendLine('function Register-RenderKitFunction {')
    [void]$builder.AppendLine('    [CmdletBinding()]')
    [void]$builder.AppendLine('    param(')
    [void]$builder.AppendLine('        [Parameter(Mandatory)]')
    [void]$builder.AppendLine('        [string]$Name')
    [void]$builder.AppendLine('    )')
    [void]$builder.AppendLine('')
    [void]$builder.AppendLine('    if ($script:RenderKitPublicFunctions -notcontains $Name) {')
    [void]$builder.AppendLine('        return')
    [void]$builder.AppendLine('    }')
    [void]$builder.AppendLine('}')
    [void]$builder.AppendLine('')

    foreach ($relativeSourcePath in 'Classes', 'Private', 'Public') {
        $sourcePath = Join-Path -Path $RepositoryRoot -ChildPath ('src\{0}' -f $relativeSourcePath)

        foreach ($sourceFile in Get-RenderKitSourceFiles -Path $sourcePath) {
            $relativeFile = $sourceFile.FullName.Substring($RepositoryRoot.Length).TrimStart('\')
            [void]$builder.AppendLine('# region {0}' -f $relativeFile)
            [void]$builder.AppendLine((Get-Content -LiteralPath $sourceFile.FullName -Raw).TrimEnd())
            [void]$builder.AppendLine('# endregion {0}' -f $relativeFile)
            [void]$builder.AppendLine('')
        }
    }

    [void]$builder.AppendLine("Set-Alias -Name 'projectroot' -Value 'Set-ProjectRoot' -Scope Script")
    [void]$builder.AppendLine("Set-Alias -Name 'setroot' -Value 'Set-ProjectRoot' -Scope Script")
    [void]$builder.AppendLine('')
    [void]$builder.AppendLine('Export-ModuleMember -Function $script:RenderKitPublicFunctions -Alias $script:RenderKitPublicAliases')

    Set-Content -LiteralPath $DestinationPath -Value $builder.ToString() -Encoding utf8
}

function New-RenderKitNuspec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Manifest,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $psData = $Manifest.PrivateData.PSData
    $tags = @('PSModule') + @($psData.Tags)
    $tagString = ($tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique) -join ' '

    $nuspec = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2011/08/nuspec.xsd">
  <metadata>
    <id>$(ConvertTo-RenderKitXmlLiteral -Value 'RenderKit')</id>
    <version>$(ConvertTo-RenderKitXmlLiteral -Value ([string]$Manifest.ModuleVersion))</version>
    <authors>$(ConvertTo-RenderKitXmlLiteral -Value ([string]$Manifest.Author))</authors>
    <owners>$(ConvertTo-RenderKitXmlLiteral -Value ([string]$Manifest.CompanyName))</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <license type="file">LICENSE</license>
    <projectUrl>$(ConvertTo-RenderKitXmlLiteral -Value ([string]$psData.ProjectUri))</projectUrl>
    <icon>images\RenderKit_Logo.png</icon>
    <readme>README.md</readme>
    <description>$(ConvertTo-RenderKitXmlLiteral -Value ([string]$Manifest.Description))</description>
    <releaseNotes>$(ConvertTo-RenderKitXmlLiteral -Value ([string]$psData.ReleaseNotes))</releaseNotes>
    <copyright>$(ConvertTo-RenderKitXmlLiteral -Value ([string]$Manifest.Copyright))</copyright>
    <tags>$(ConvertTo-RenderKitXmlLiteral -Value $tagString)</tags>
    <repository type="git" url="https://github.com/djtroi/RenderKit" branch="main" />
  </metadata>
  <files>
    <file src="RenderKit.psd1" />
    <file src="RenderKit.psm1" />
    <file src="README.md" />
    <file src="CHANGELOG.md" />
    <file src="LICENSE" />
    <file src="images\RenderKit_Logo.png" target="images" />
    <file src="src\Resources\**\*.*" target="src\Resources" />
  </files>
</package>
"@

    Set-Content -LiteralPath $DestinationPath -Value $nuspec -Encoding utf8
}

$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).ProviderPath
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

$manifestPath = Join-Path -Path $RepositoryRoot -ChildPath 'RenderKit.psd1'
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$moduleName = 'RenderKit'
$moduleVersion = [string]$manifest.ModuleVersion

$stageRoot = Join-Path -Path $OutputRoot -ChildPath ('staging\{0}\{1}' -f $moduleName, $moduleVersion)
$packageRoot = Join-Path -Path $OutputRoot -ChildPath 'packages'
$tempPackRoot = Join-Path -Path $OutputRoot -ChildPath ('temp\{0}\{1}' -f $moduleName, $moduleVersion)
$nupkgPath = Join-Path -Path $packageRoot -ChildPath ('{0}.{1}.nupkg' -f $moduleName, $moduleVersion)

New-RenderKitDirectory -Path $stageRoot
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
New-RenderKitDirectory -Path $tempPackRoot

New-Item -ItemType Directory -Path (Join-Path -Path $stageRoot -ChildPath 'images') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path -Path $stageRoot -ChildPath 'src') -Force | Out-Null

Copy-Item -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath 'RenderKit.psd1') -Destination (Join-Path -Path $stageRoot -ChildPath 'RenderKit.psd1')
Copy-Item -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath 'README.md') -Destination (Join-Path -Path $stageRoot -ChildPath 'README.md')
Copy-Item -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath 'CHANGELOG.md') -Destination (Join-Path -Path $stageRoot -ChildPath 'CHANGELOG.md')
Copy-Item -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath 'LICENSE') -Destination (Join-Path -Path $stageRoot -ChildPath 'LICENSE')
Copy-Item -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath 'src\assets\RenderKit_Logo.png') -Destination (Join-Path -Path $stageRoot -ChildPath 'images\RenderKit_Logo.png')
Copy-Item -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath 'src\Resources') -Destination (Join-Path -Path $stageRoot -ChildPath 'src\Resources') -Recurse

New-RenderKitBundledModule -RepositoryRoot $RepositoryRoot -DestinationPath (Join-Path -Path $stageRoot -ChildPath 'RenderKit.psm1') -Manifest $manifest
New-RenderKitNuspec -Manifest $manifest -DestinationPath (Join-Path -Path $stageRoot -ChildPath 'RenderKit.nuspec')

$csprojPath = Join-Path -Path $tempPackRoot -ChildPath 'RenderKit.Package.csproj'
$csprojContent = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <IncludeBuildOutput>false</IncludeBuildOutput>
  </PropertyGroup>
</Project>
'@
Set-Content -LiteralPath $csprojPath -Value $csprojContent -Encoding utf8

Remove-Item -LiteralPath $nupkgPath -Force -ErrorAction SilentlyContinue

if (-not $SkipPackage) {
    $env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
    $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
    $env:DOTNET_NOLOGO = '1'
    $env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = '0'
    $env:DOTNET_CLI_HOME = $OutputRoot

    Push-Location -LiteralPath $stageRoot
    try {
        $packOutput = & 'C:\Program Files\dotnet\dotnet.exe' pack $csprojPath ("/p:NuspecFile={0}" -f (Join-Path -Path $stageRoot -ChildPath 'RenderKit.nuspec')) '--output' $packageRoot '--configuration' 'Release' 2>&1
        foreach ($line in $packOutput) {
            Write-Host $line
        }

        if ($LASTEXITCODE -ne 0) {
            throw "dotnet pack failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path -Path $stageRoot -ChildPath 'RenderKit.psd1') -Force -ErrorAction Stop | Out-Null

[PSCustomObject]@{
    ModuleName  = $moduleName
    Version     = $moduleVersion
    StagePath   = $stageRoot
    PackagePath = $nupkgPath
}
