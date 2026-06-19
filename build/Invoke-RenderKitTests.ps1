[CmdletBinding()]
param(
    [string]$Path = './Tests',

    [string]$TestResultPath,

    [Version]$MinimumPesterVersion = '5.5.0',

    [switch]$InstallPester
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$loadedPester = Get-Module -Name Pester
if ($loadedPester) {
    Remove-Module -Name Pester -Force
}

$availablePester = @(Get-Module -Name Pester -ListAvailable |
    Where-Object { $_.Version -ge $MinimumPesterVersion } |
    Sort-Object -Property Version -Descending)

if ($availablePester.Count -eq 0 -and $InstallPester) {
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module `
        -Name Pester `
        -MinimumVersion $MinimumPesterVersion `
        -Scope CurrentUser `
        -Force `
        -SkipPublisherCheck
}

Import-Module -Name Pester -MinimumVersion $MinimumPesterVersion -Force -ErrorAction Stop

$activePester = Get-Module -Name Pester
if (-not $activePester -or $activePester.Version -lt $MinimumPesterVersion) {
    throw "RenderKit tests require Pester $MinimumPesterVersion or newer. Run './build/Invoke-RenderKitTests.ps1 -InstallPester' or import Pester 5 before calling Invoke-Pester."
}

$configuration = New-PesterConfiguration
$configuration.Run.Path = $Path
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'

if (-not [string]::IsNullOrWhiteSpace($TestResultPath)) {
    $testResultDirectory = Split-Path -Parent $TestResultPath
    if (-not [string]::IsNullOrWhiteSpace($testResultDirectory)) {
        New-Item -ItemType Directory -Path $testResultDirectory -Force | Out-Null
    }

    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = 'NUnitXml'
    $configuration.TestResult.OutputPath = $TestResultPath
}

$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0) {
    throw "$($result.FailedCount) Pester test(s) failed."
}

return $result