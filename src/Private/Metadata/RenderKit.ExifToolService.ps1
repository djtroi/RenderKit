function Get-RenderKitExifToolBundleRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return Join-Path `
        -Path $script:RenderKitModuleRoot `
        -ChildPath 'src/Resources/ThirdParty/ExifTool'
}

function ConvertTo-RenderKitExifToolRuntimeIdentifier {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$OperatingSystem,

        [Parameter(Mandatory)]
        [string]$Architecture
    )

    $os = switch -Regex ($OperatingSystem) {
        '^(Win|Windows|Win32NT)$' { 'win'; break }
        '^(OSX|macOS|Darwin)$' { 'osx'; break }
        '^(Linux|Unix)$' { 'linux'; break }
        default { $OperatingSystem.ToLowerInvariant() }
    }

    $arch = switch -Regex ($Architecture) {
        'Arm64|Aarch64|ARM64' { 'arm64'; break }
        'X64|AMD64|x86_64' { 'x64'; break }
        'X86|I386|I686' { 'x86'; break }
        default { $Architecture.ToLowerInvariant() }
    }

    return '{0}-{1}' -f $os, $arch
}

function Get-RenderKitExifToolRuntimeIdentifier {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $os = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        'win'
    }
    else {
        try {
            if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                    [System.Runtime.InteropServices.OSPlatform]::OSX)) {
                'osx'
            }
            elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                    [System.Runtime.InteropServices.OSPlatform]::Linux)) {
                'linux'
            }
            else {
                'unknown'
            }
        }
        catch {
            'unknown'
        }
    }

    $architecture = try {
        [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    }
    catch {
        [string]$env:PROCESSOR_ARCHITECTURE
    }

    return ConvertTo-RenderKitExifToolRuntimeIdentifier `
        -OperatingSystem $os `
        -Architecture $architecture
}

function Read-RenderKitExifToolBundleManifest {
    [CmdletBinding()]
    param(
        [switch]$Reload
    )

    $manifestPath = Join-Path `
        -Path (Get-RenderKitExifToolBundleRoot) `
        -ChildPath 'manifest.json'

    if (-not $Reload -and
        $script:RenderKitExifToolBundleManifest -and
        $script:RenderKitExifToolBundleManifestPath -eq $manifestPath) {
        return $script:RenderKitExifToolBundleManifest
    }

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $null
    }

    $manifest = Read-RenderKitJsonFile -Path $manifestPath -MaximumBytes 1048576
    $script:RenderKitExifToolBundleManifest = $manifest
    $script:RenderKitExifToolBundleManifestPath = $manifestPath
    return $manifest
}

function Get-RenderKitExifToolBundleRuntime {
    [CmdletBinding()]
    param(
        [string]$RuntimeIdentifier = (Get-RenderKitExifToolRuntimeIdentifier)
    )

    $manifest = Read-RenderKitExifToolBundleManifest
    if (-not $manifest) {
        return $null
    }

    return @(
        $manifest.runtimeIdentifiers |
            Where-Object { [string]$_.rid -ieq $RuntimeIdentifier } |
            Select-Object -First 1
    )
}

function Test-RenderKitExifToolUsableFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [string]$Path
    )

    return (
        -not [string]::IsNullOrWhiteSpace($Path) -and
        (Test-Path -LiteralPath $Path -PathType Leaf)
    )
}

function Resolve-RenderKitExifToolApplication {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$PathOrName
    )

    if ([string]::IsNullOrWhiteSpace($PathOrName)) {
        return $null
    }

    if (Test-RenderKitExifToolUsableFile -Path $PathOrName) {
        return [PSCustomObject]@{
            Path = [System.IO.Path]::GetFullPath($PathOrName)
            Name = [System.IO.Path]::GetFileName($PathOrName)
        }
    }

    $command = Get-Command `
        -Name $PathOrName `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $command) {
        return $null
    }

    return [PSCustomObject]@{
        Path = [string]$command.Source
        Name = [string]$command.Name
    }
}

function New-RenderKitExifToolCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Cli', 'Host')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [ValidateSet('Environment', 'Bundled', 'System', 'Explicit')]
        [string]$Source,

        [AllowNull()]
        [string]$Path,

        [string[]]$PrefixArguments = @(),

        [string]$PayloadPath,

        [string]$DisplayName,

        [bool]$Available = $true,

        [string]$UnavailableReason
    )

    [PSCustomObject]@{
        Kind = $Kind
        Source = $Source
        Path = $Path
        PrefixArguments = @($PrefixArguments)
        PayloadPath = $PayloadPath
        DisplayName = if ([string]::IsNullOrWhiteSpace($DisplayName)) { $Path } else { $DisplayName }
        Available = [bool]$Available
        UnavailableReason = $UnavailableReason
    }
}

function Resolve-RenderKitExifToolReader {
    [CmdletBinding()]
    param()

    $bundleRoot = Get-RenderKitExifToolBundleRoot
    $runtimeIdentifier = Get-RenderKitExifToolRuntimeIdentifier
    $runtime = Get-RenderKitExifToolBundleRuntime -RuntimeIdentifier $runtimeIdentifier
    $candidates = New-Object System.Collections.Generic.List[object]

    $configuredCli = [string]$env:RENDERKIT_EXIFTOOL_PATH
    if (-not [string]::IsNullOrWhiteSpace($configuredCli)) {
        $resolvedCli = Resolve-RenderKitExifToolApplication -PathOrName $configuredCli
        $candidates.Add((New-RenderKitExifToolCandidate `
            -Kind Cli `
            -Source Environment `
            -Path $(if ($resolvedCli) { [string]$resolvedCli.Path } else { $configuredCli }) `
            -DisplayName $(if ($resolvedCli) { [string]$resolvedCli.Name } else { $configuredCli }) `
            -Available ([bool]$resolvedCli) `
            -UnavailableReason $(if ($resolvedCli) { $null } else { 'ConfiguredPathNotFound' })))
    }

    if ($runtime -and [bool]$runtime.bundled) {
        $commandPath = Join-Path `
            -Path $bundleRoot `
            -ChildPath ([string]$runtime.commandRelativePath)
        $bundleKind = [string]$runtime.bundleKind
        if ($bundleKind -ieq 'PerlScript') {
            $configuredPerl = [string]$env:RENDERKIT_EXIFTOOL_PERL
            $perl = if (-not [string]::IsNullOrWhiteSpace($configuredPerl)) {
                Resolve-RenderKitExifToolApplication -PathOrName $configuredPerl
            }
            else {
                Resolve-RenderKitExifToolApplication -PathOrName 'perl'
            }
            $bundleAvailable = (
                (Test-RenderKitExifToolUsableFile -Path $commandPath) -and
                [bool]$perl
            )
            $candidates.Add((New-RenderKitExifToolCandidate `
                -Kind Cli `
                -Source Bundled `
                -Path $(if ($perl) { [string]$perl.Path } else { $configuredPerl }) `
                -PrefixArguments @([System.IO.Path]::GetFullPath($commandPath)) `
                -PayloadPath ([System.IO.Path]::GetFullPath($commandPath)) `
                -DisplayName 'Bundled ExifTool via Perl' `
                -Available $bundleAvailable `
                -UnavailableReason $(if (-not (Test-RenderKitExifToolUsableFile -Path $commandPath)) {
                    'BundledScriptNotFound'
                }
                elseif (-not $perl) {
                    'PerlNotAvailable'
                }
                else {
                    $null
                })))
        }
        else {
            $bundleAvailable = Test-RenderKitExifToolUsableFile -Path $commandPath
            $candidates.Add((New-RenderKitExifToolCandidate `
                -Kind Cli `
                -Source Bundled `
                -Path ([System.IO.Path]::GetFullPath($commandPath)) `
                -DisplayName 'Bundled ExifTool' `
                -Available $bundleAvailable `
                -UnavailableReason $(if ($bundleAvailable) { $null } else { 'BundledExecutableNotFound' })))
        }
    }

    $configuredHost = [string]$env:RENDERKIT_EXIFTOOL_HOST
    if (-not [string]::IsNullOrWhiteSpace($configuredHost)) {
        $resolvedHost = Resolve-RenderKitExifToolApplication -PathOrName $configuredHost
        $candidates.Add((New-RenderKitExifToolCandidate `
            -Kind Host `
            -Source Environment `
            -Path $(if ($resolvedHost) { [string]$resolvedHost.Path } else { $configuredHost }) `
            -PrefixArguments @('exiftool', 'run', '--') `
            -DisplayName $(if ($resolvedHost) { [string]$resolvedHost.Name } else { $configuredHost }) `
            -Available ([bool]$resolvedHost) `
            -UnavailableReason $(if ($resolvedHost) { $null } else { 'ConfiguredHostNotFound' })))
    }

    $systemCommand = Get-RenderKitMetadataCommand -CommandName @('exiftool', 'exiftool.exe')
    if ($systemCommand) {
        $systemPath = [string]$systemCommand.Source
        $isDuplicate = @(
            $candidates |
                Where-Object {
                    [bool]$_.Available -and
                    -not [string]::IsNullOrWhiteSpace([string]$_.Path) -and
                    [string]$_.Path -ieq $systemPath
                }
        ).Count -gt 0
        if (-not $isDuplicate) {
            $candidates.Add((New-RenderKitExifToolCandidate `
                -Kind Cli `
                -Source System `
                -Path $systemPath `
                -DisplayName ([string]$systemCommand.Name)))
        }
    }

    $availableCandidates = @($candidates | Where-Object { [bool]$_.Available })
    $first = @($availableCandidates | Select-Object -First 1)
    $cliCandidates = @($candidates | Where-Object { [string]$_.Kind -eq 'Cli' })
    $hostCandidates = @($candidates | Where-Object { [string]$_.Kind -eq 'Host' })

    [PSCustomObject]@{
        Id = 'ExifTool'
        Available = [bool]$first
        Mode = if ($first) { [string]$first.Kind } else { 'Unavailable' }
        Source = if ($first) { [string]$first.Source } else { $null }
        RuntimeIdentifier = $runtimeIdentifier
        CommandPath = if ($first -and [string]$first.Kind -eq 'Cli') { [string]$first.Path } else { $null }
        CommandName = if ($first -and [string]$first.Kind -eq 'Cli') { [string]$first.DisplayName } else { $null }
        HostPath = if ($first -and [string]$first.Kind -eq 'Host') { [string]$first.Path } else { $null }
        Candidates = @($candidates.ToArray())
        CliCandidates = $cliCandidates
        HostCandidates = $hostCandidates
    }
}

function Invoke-RenderKitExifToolCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Candidate,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $commandArguments = @($Candidate.PrefixArguments) + @($Arguments)
    $output = & ([string]$Candidate.Path) @commandArguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "ExifTool $($Candidate.Kind.ToLowerInvariant()) exited with code $exitCode`: $($output -join "`n")"
    }

    return @($output | ForEach-Object { [string]$_ })
}

function Invoke-RenderKitExifToolCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [object]$Reader,

        [string]$CommandPath
    )

    if (-not $Reader) {
        if (-not [string]::IsNullOrWhiteSpace($CommandPath)) {
            $Reader = [PSCustomObject]@{
                Candidates = @(
                    New-RenderKitExifToolCandidate `
                        -Kind Cli `
                        -Source Explicit `
                        -Path $CommandPath
                )
            }
        }
        else {
            $Reader = Resolve-RenderKitExifToolReader
        }
    }

    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($Reader.Candidates)) {
        if (-not [bool]$candidate.Available) {
            continue
        }

        try {
            $output = Invoke-RenderKitExifToolCandidate `
                -Candidate $candidate `
                -Arguments $Arguments
            return [PSCustomObject]@{
                Output = @($output)
                Backend = [string]$candidate.Kind
                Source = [string]$candidate.Source
                Path = [string]$candidate.Path
                PayloadPath = [string]$candidate.PayloadPath
                Errors = @($errors.ToArray())
            }
        }
        catch {
            $errors.Add(
                ('{0}/{1} failed: {2}' -f
                    ([string]$candidate.Kind).ToLowerInvariant(),
                    [string]$candidate.Source,
                    $_.Exception.Message)
            )
        }
    }

    if ($errors.Count -gt 0) {
        throw "ExifTool failed through all configured backends: $($errors -join '; ')"
    }

    throw 'ExifTool is not available. Add the bundled runtime, configure RENDERKIT_EXIFTOOL_PATH or RENDERKIT_EXIFTOOL_HOST, or install exiftool on PATH.'
}
