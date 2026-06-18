[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PackagePath,

    [string]$ExpectedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackagePath = (Resolve-Path -LiteralPath $PackagePath).ProviderPath
$package = Get-Item -LiteralPath $PackagePath
$testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('RenderKit-PackageTest-{0}' -f ([guid]::NewGuid().ToString('N')))
$extractRoot = Join-Path -Path $testRoot -ChildPath 'extracted'
$archive = $null

try {
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })

    foreach ($requiredEntry in 'RenderKit.psd1', 'RenderKit.psm1') {
        if ($entryNames -notcontains $requiredEntry) {
            throw "Package '$PackagePath' does not contain required entry '$requiredEntry'."
        }
    }

    foreach ($entry in $archive.Entries) {
        if ([string]::IsNullOrEmpty($entry.Name)) {
            continue
        }

        $entryStream = $entry.Open()
        try {
            $buffer = New-Object byte[] 81920
            while ($entryStream.Read($buffer, 0, $buffer.Length) -gt 0) {
            }
        }
        finally {
            $entryStream.Dispose()
        }
    }

    $archive.Dispose()
    $archive = $null

    [System.IO.Compression.ZipFile]::ExtractToDirectory($PackagePath, $extractRoot)

    $manifestPath = Join-Path -Path $extractRoot -ChildPath 'RenderKit.psd1'
    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop

    if ($ExpectedVersion -and $manifest.Version.ToString() -ne $ExpectedVersion) {
        throw "Expected module version '$ExpectedVersion', but package contains '$($manifest.Version)'."
    }

    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    Import-Module $manifestPath -Force -ErrorAction Stop

    $importedModule = Get-Module -Name RenderKit
    if (-not $importedModule) {
        throw 'RenderKit was not loaded from the extracted package.'
    }

    $expectedFunctions = @($manifest.ExportedFunctions.Keys)
    $actualFunctions = @(Get-Command -Module RenderKit -CommandType Function | Select-Object -ExpandProperty Name)
    $missingFunctions = @($expectedFunctions | Where-Object { $actualFunctions -notcontains $_ })

    if ($missingFunctions.Count -gt 0) {
        throw "Package import is missing exported functions: $($missingFunctions -join ', ')."
    }

    [PSCustomObject]@{
        PackagePath    = $package.FullName
        PackageBytes   = $package.Length
        PackageSha256  = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
        EntryCount     = $entryNames.Count
        ModuleVersion  = $manifest.Version.ToString()
        ExportedCount  = $expectedFunctions.Count
        Validation     = 'Passed'
    }
}
finally {
    if ($null -ne $archive) {
        $archive.Dispose()
    }

    Remove-Module RenderKit -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
