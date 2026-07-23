[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Get-Location) 'results.sarif'),
    [string]$AnalyzerVersion = '1.25.0',
    [switch]$InstallModules
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-RenderKitAnalysisModule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version,
        [switch]$InstallIfMissing
    )

    $available = @(Get-Module -ListAvailable -Name $Name | Where-Object {
        $_.Version -eq [version]$Version
    })
    if ($available.Count -eq 0) {
        if (-not $InstallIfMissing) {
            throw "Required module '$Name' version '$Version' is not installed."
        }
        Install-Module `
            -Name $Name `
            -RequiredVersion $Version `
            -Scope CurrentUser `
            -Force `
            -AllowClobber
    }

    Import-Module -Name $Name -RequiredVersion $Version -Force
    $loaded = Get-Module -Name $Name | Where-Object Version -eq ([version]$Version) |
        Select-Object -First 1
    if (-not $loaded) {
        throw "Required module '$Name' version '$Version' could not be loaded."
    }
    Write-Information `
        "Using $Name $($loaded.Version)." `
        -InformationAction Continue
}

$resolvedRepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).ProviderPath
$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

Import-RenderKitAnalysisModule `
    -Name PSScriptAnalyzer `
    -Version $AnalyzerVersion `
    -InstallIfMissing:$InstallModules

$trackedFiles = @(& git -C $resolvedRepositoryRoot ls-files -- `
        '*.ps1' '*.psm1' '*.psd1' | Sort-Object -Unique)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not enumerate tracked PowerShell files with git ls-files.'
}
if ($trackedFiles.Count -eq 0) {
    throw 'No tracked PowerShell files were found.'
}

$sarifResults = [Collections.Generic.List[object]]::new()
$rules = @{}
foreach ($relativePath in $trackedFiles) {
    $fullPath = Join-Path $resolvedRepositoryRoot $relativePath
    try {
        foreach ($diagnostic in @(Invoke-ScriptAnalyzer `
                -Path $fullPath `
                -ErrorAction Stop)) {
            $ruleId = [string]$diagnostic.RuleName
            if (-not $rules.ContainsKey($ruleId)) {
                $rules[$ruleId] = [ordered]@{
                    id = $ruleId
                    name = $ruleId
                    shortDescription = @{ text = $ruleId }
                }
            }

            $startLine = try {
                [Math]::Max(1, [int]$diagnostic.Extent.StartLineNumber)
            }
            catch { 1 }
            $startColumn = try {
                [Math]::Max(1, [int]$diagnostic.Extent.StartColumnNumber)
            }
            catch { 1 }
            $level = switch ([string]$diagnostic.Severity) {
                'Error' { 'error' }
                'Warning' { 'warning' }
                default { 'note' }
            }
            $sarifResults.Add([ordered]@{
                ruleId = $ruleId
                level = $level
                message = @{ text = [string]$diagnostic.Message }
                locations = @([ordered]@{
                    physicalLocation = [ordered]@{
                        artifactLocation = @{
                            uri = ([string]$relativePath).Replace('\', '/')
                        }
                        region = @{
                            startLine = $startLine
                            startColumn = $startColumn
                        }
                    }
                })
            })
        }
    }
    catch {
        throw "PSScriptAnalyzer failed for '$relativePath': $($_.Exception.Message)"
    }
}

[ordered]@{
    version = '2.1.0'
    '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
    runs = @([ordered]@{
        tool = @{ driver = [ordered]@{
            name = 'PSScriptAnalyzer'
            version = $AnalyzerVersion
            informationUri = 'https://github.com/PowerShell/PSScriptAnalyzer'
            rules = @($rules.Keys | Sort-Object | ForEach-Object { $rules[$_] })
        } }
        results = @($sarifResults)
    })
} | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM

if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw "SARIF output was not created: $OutputPath"
}

Write-Information `
    "Analyzed $($trackedFiles.Count) tracked PowerShell files." `
    -InformationAction Continue
Write-Information `
    "Wrote $($sarifResults.Count) diagnostics to '$OutputPath'." `
    -InformationAction Continue
